using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using Microsoft.Win32;

internal sealed class InstallerOptions
{
    public bool ShowHelp;
    public bool Silent;
    public bool AddPath = true;
    public string Source;
    public string Target;
}

internal static class Program
{
    private static int Main(string[] args)
    {
        string tempExtractRoot = null;
        try
        {
            InstallerOptions options = ParseArgs(args);
            if (options.ShowHelp)
            {
                PrintHelp();
                return 0;
            }

            string exeDir = AppDomain.CurrentDomain.BaseDirectory;
            string source = ResolveSource(options.Source, exeDir);
            string target = ResolveTarget(options.Target);

            Log(options, "Source: " + source);
            Log(options, "Target: " + target);

            string stagedRoot;
            if (File.Exists(source))
            {
                if (!source.EndsWith(".tar", StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidOperationException("Only .tar archive is supported when source is a file.");
                }

                tempExtractRoot = Path.Combine(Path.GetTempPath(), "riscv-installer-" + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(tempExtractRoot);

                RunProcess("tar", "-xf \"" + source + "\" -C \"" + tempExtractRoot + "\"");

                stagedRoot = Path.Combine(tempExtractRoot, "riscv");
                if (!Directory.Exists(stagedRoot))
                {
                    string[] dirs = Directory.GetDirectories(tempExtractRoot);
                    if (dirs.Length == 1)
                    {
                        stagedRoot = dirs[0];
                    }
                }
            }
            else if (Directory.Exists(source))
            {
                stagedRoot = NormalizeSourceDirectory(source);
            }
            else
            {
                throw new InvalidOperationException("Source not found: " + source);
            }

            EnsureToolchainRoot(stagedRoot);

            if (Directory.Exists(target))
            {
                Directory.Delete(target, true);
            }

            CopyDirectory(stagedRoot, target);
            EnsureTargetBinutilsCompat(target);
            ValidateInstalled(target);

            if (options.AddPath)
            {
                AddToUserPath(Path.Combine(target, "bin"));
                Environment.SetEnvironmentVariable("RISCV_TOOLCHAIN_ROOT", target, EnvironmentVariableTarget.User);
                Log(options, "Added user PATH and RISCV_TOOLCHAIN_ROOT.");
            }

            WriteInstallInfo(target);
            Log(options, "Install completed.");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("ERROR: " + ex.Message);
            return 1;
        }
        finally
        {
            if (!string.IsNullOrEmpty(tempExtractRoot))
            {
                TryDelete(tempExtractRoot);
            }
        }
    }

    private static InstallerOptions ParseArgs(string[] args)
    {
        var options = new InstallerOptions();
        var values = new Queue<string>(args);

        while (values.Count > 0)
        {
            string raw = values.Dequeue();
            string key = raw.Trim();

            if (key == "-h" || key == "--help" || key == "/?")
            {
                options.ShowHelp = true;
                continue;
            }

            if (MatchKey(key, "silent"))
            {
                options.Silent = true;
                continue;
            }

            if (MatchKey(key, "add-path"))
            {
                options.AddPath = true;
                continue;
            }

            if (MatchKey(key, "no-path"))
            {
                options.AddPath = false;
                continue;
            }

            if (MatchKey(key, "source"))
            {
                options.Source = ReadValue(values, key);
                continue;
            }

            if (MatchKey(key, "target"))
            {
                options.Target = ReadValue(values, key);
                continue;
            }

            throw new ArgumentException("Unknown argument: " + key);
        }

        return options;
    }

    private static bool MatchKey(string raw, string expected)
    {
        string key = raw.TrimStart('-', '/');
        return string.Equals(key, expected, StringComparison.OrdinalIgnoreCase);
    }

    private static string ReadValue(Queue<string> values, string key)
    {
        if (values.Count == 0)
        {
            throw new ArgumentException("Missing value for " + key);
        }

        return values.Dequeue();
    }

    private static void PrintHelp()
    {
        Console.WriteLine("RISC-V Toolchain Installer");
        Console.WriteLine("Usage:");
        Console.WriteLine("  riscv-toolchain-installer.exe [--source <path>] [--target <path>] [--silent] [--no-path]");
        Console.WriteLine();
        Console.WriteLine("Source:");
        Console.WriteLine("  - folder containing toolchain root 'riscv' or toolchain files directly");
        Console.WriteLine("  - or .tar archive containing 'riscv' root");
        Console.WriteLine();
        Console.WriteLine("Default target:");
        Console.WriteLine("  %LocalAppData%\\Programs\\riscv-toolchain");
    }

    private static string ResolveSource(string source, string exeDir)
    {
        if (!string.IsNullOrEmpty(source))
        {
            return Path.GetFullPath(source);
        }

        string localDir = Path.Combine(exeDir, "riscv");
        if (Directory.Exists(localDir))
        {
            return localDir;
        }

        string localTar = Path.Combine(exeDir, "riscv-rv32-win.tar");
        if (File.Exists(localTar))
        {
            return localTar;
        }

        throw new InvalidOperationException("No source specified and no default source found next to installer.");
    }

    private static string ResolveTarget(string target)
    {
        if (!string.IsNullOrEmpty(target))
        {
            return Path.GetFullPath(target);
        }

        string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(localAppData, "Programs", "riscv-toolchain");
    }

    private static string NormalizeSourceDirectory(string source)
    {
        string candidate = Path.GetFullPath(source);
        string nested = Path.Combine(candidate, "riscv");

        if (Directory.Exists(Path.Combine(candidate, "bin")) &&
            Directory.Exists(Path.Combine(candidate, "riscv32-unknown-elf")))
        {
            return candidate;
        }

        if (Directory.Exists(nested) &&
            Directory.Exists(Path.Combine(nested, "bin")) &&
            Directory.Exists(Path.Combine(nested, "riscv32-unknown-elf")))
        {
            return nested;
        }

        return candidate;
    }

    private static void EnsureToolchainRoot(string root)
    {
        if (!Directory.Exists(root))
        {
            throw new InvalidOperationException("Toolchain root does not exist: " + root);
        }

        string[] requiredDirs =
        {
            Path.Combine(root, "bin"),
            Path.Combine(root, "riscv32-unknown-elf")
        };

        foreach (string dir in requiredDirs)
        {
            if (!Directory.Exists(dir))
            {
                throw new InvalidOperationException("Invalid toolchain layout, missing directory: " + dir);
            }
        }
    }

    private static void ValidateInstalled(string installRoot)
    {
        string[] required =
        {
            Path.Combine(installRoot, "bin", "riscv32-unknown-elf-gcc.exe"),
            Path.Combine(installRoot, "bin", "riscv32-unknown-elf-g++.exe"),
            Path.Combine(installRoot, "bin", "riscv32-unknown-elf-gdb.exe"),
            Path.Combine(installRoot, "bin", "riscv32-unknown-elf-readelf.exe"),
            Path.Combine(installRoot, "bin", "libstdc++-6.dll"),
            Path.Combine(installRoot, "bin", "libgcc_s_seh-1.dll"),
            Path.Combine(installRoot, "libexec", "gcc", "riscv32-unknown-elf", "15.2.0", "cc1.exe")
        };

        foreach (string file in required)
        {
            if (!File.Exists(file))
            {
                throw new InvalidOperationException("Installed output missing: " + file);
            }
        }
    }

    private static void EnsureTargetBinutilsCompat(string installRoot)
    {
        string hostBin = Path.Combine(installRoot, "bin");
        string targetBin = Path.Combine(installRoot, "riscv32-unknown-elf", "bin");
        Directory.CreateDirectory(targetBin);

        string[] tools =
        {
            "as",
            "ld",
            "ar",
            "nm",
            "ranlib",
            "objcopy",
            "objdump",
            "strip",
            "size",
            "readelf"
        };

        foreach (string tool in tools)
        {
            string targetTool = Path.Combine(targetBin, tool + ".exe");
            if (File.Exists(targetTool))
            {
                continue;
            }

            string prefixedTool = Path.Combine(hostBin, "riscv32-unknown-elf-" + tool + ".exe");
            if (File.Exists(prefixedTool))
            {
                File.Copy(prefixedTool, targetTool, true);
            }
        }
    }

    private static void AddToUserPath(string binPath)
    {
        string current = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.User) ?? string.Empty;
        string normalizedBin = NormalizePathForCompare(binPath);
        string[] parts = current.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries);

        foreach (string part in parts)
        {
            if (string.Equals(NormalizePathForCompare(part), normalizedBin, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }
        }

        string updated = current;
        if (!string.IsNullOrEmpty(updated) && !updated.EndsWith(";", StringComparison.Ordinal))
        {
            updated += ";";
        }
        updated += binPath;

        Environment.SetEnvironmentVariable("Path", updated, EnvironmentVariableTarget.User);
    }

    private static string NormalizePathForCompare(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return string.Empty;
        }

        string full = Path.GetFullPath(path.Trim());
        return full.TrimEnd('\\', '/');
    }

    private static void WriteInstallInfo(string installRoot)
    {
        string infoFile = Path.Combine(installRoot, "INSTALL_INFO.txt");
        File.WriteAllText(
            infoFile,
            "InstalledAt=" + DateTime.UtcNow.ToString("o") + Environment.NewLine +
            "InstallRoot=" + installRoot + Environment.NewLine
        );
    }

    private static void RunProcess(string fileName, string arguments)
    {
        var psi = new ProcessStartInfo(fileName, arguments);
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;

        using (Process p = Process.Start(psi))
        {
            string stdout = p.StandardOutput.ReadToEnd();
            string stderr = p.StandardError.ReadToEnd();
            p.WaitForExit();

            if (p.ExitCode != 0)
            {
                throw new InvalidOperationException(
                    "Command failed (" + fileName + " " + arguments + "), exit code: " + p.ExitCode +
                    Environment.NewLine + stdout + Environment.NewLine + stderr
                );
            }
        }
    }

    private static void CopyDirectory(string source, string destination)
    {
        Directory.CreateDirectory(destination);

        foreach (string dir in Directory.GetDirectories(source, "*", SearchOption.AllDirectories))
        {
            string rel = dir.Substring(source.Length).TrimStart('\\', '/');
            Directory.CreateDirectory(Path.Combine(destination, rel));
        }

        foreach (string file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
        {
            string rel = file.Substring(source.Length).TrimStart('\\', '/');
            string targetFile = Path.Combine(destination, rel);
            string targetDir = Path.GetDirectoryName(targetFile);
            if (!Directory.Exists(targetDir))
            {
                Directory.CreateDirectory(targetDir);
            }
            File.Copy(file, targetFile, true);
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, true);
            }
        }
        catch
        {
            // Best-effort cleanup only.
        }
    }

    private static void Log(InstallerOptions options, string message)
    {
        if (!options.Silent)
        {
            Console.WriteLine(message);
        }
    }
}
