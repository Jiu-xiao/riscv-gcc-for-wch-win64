[CmdletBinding()]
param(
  [string]$WorkDir = "",
  [string]$SourceFile = "",
  [string]$OutputDir = "",
  [string]$ExeName = "riscv-toolchain-installer.exe",
  [switch]$VerboseOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-CscPath {
  $candidates = @(
    "C:\\Windows\\Microsoft.NET\\Framework64\\v4.0.30319\\csc.exe",
    "C:\\Windows\\Microsoft.NET\\Framework\\v4.0.30319\\csc.exe"
  )
  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }
  throw "csc.exe not found. Expected .NET Framework compiler under C:\\Windows\\Microsoft.NET\\Framework*\\v4.0.30319\\csc.exe"
}

if ([string]::IsNullOrWhiteSpace($WorkDir)) {
  $WorkDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$WorkDir = (Resolve-Path $WorkDir).Path

if ([string]::IsNullOrWhiteSpace($SourceFile)) {
  $SourceFile = Join-Path $WorkDir "installer\\ToolchainInstaller.cs"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = Join-Path $WorkDir "out\\installer"
}

$SourceFile = (Resolve-Path $SourceFile).Path
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$csc = Resolve-CscPath
$outExe = Join-Path $OutputDir $ExeName

Write-Host "==> Building installer exe"
Write-Host "    csc: $csc"
Write-Host "    src: $SourceFile"
Write-Host "    out: $outExe"

$args = @(
  "/nologo",
  "/target:exe",
  "/optimize+",
  "/platform:anycpu",
  "/out:$outExe",
  $SourceFile
)

if ($VerboseOutput) {
  & $csc @args
} else {
  & $csc @args | Out-Null
}

if ($LASTEXITCODE -ne 0) {
  throw "Installer compile failed, exit code: $LASTEXITCODE"
}

$exeInfo = Get-Item $outExe
Write-Host "==> Done: $($exeInfo.FullName) ($($exeInfo.Length) bytes)"
