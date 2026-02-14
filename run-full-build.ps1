[CmdletBinding()]
param(
  [string]$WorkDir = "",
  [string]$ImageName = "riscv-gcc-builder-full",
  [string]$ContainerName = "riscv-gcc-build-full",
  [int]$JobsStage1 = 32,
  [int]$JobsFinal = 32,
  [int]$MakeRetries = 6,
  [int]$MakeRetryDelay = 8,
  [string]$HttpProxy = $env:HTTP_PROXY,
  [string]$HttpsProxy = $env:HTTPS_PROXY,
  [switch]$NoCache,
  [switch]$SkipImageBuild,
  [switch]$CreateTar,
  [switch]$KeepContainer
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($WorkDir)) {
  $WorkDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw "docker command not found. Please install Docker Desktop first."
}

$WorkDir = (Resolve-Path $WorkDir).Path
$Dockerfile = Join-Path $WorkDir "Dockerfile.builder"
$BuildScript = Join-Path $WorkDir "build.sh"
$OutDir = Join-Path $WorkDir "out"
$OutputRoot = Join-Path $OutDir "riscv"
$Artifact = Join-Path $OutDir "riscv-rv32-win.tar"
$LogFile = "build-run-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss")

if (-not (Test-Path $Dockerfile)) {
  throw "Missing file: $Dockerfile"
}
if (-not (Test-Path $BuildScript)) {
  throw "Missing file: $BuildScript"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not $SkipImageBuild) {
  Write-Host "==> Building image: $ImageName"
  $buildArgs = @("build", "-f", $Dockerfile, "-t", $ImageName)
  if ($NoCache) {
    $buildArgs += "--no-cache"
  }
  if ($HttpProxy) {
    $buildArgs += @("--build-arg", "HTTP_PROXY=$HttpProxy", "--build-arg", "http_proxy=$HttpProxy")
  }
  if ($HttpsProxy) {
    $buildArgs += @("--build-arg", "HTTPS_PROXY=$HttpsProxy", "--build-arg", "https_proxy=$HttpsProxy")
  }
  $buildArgs += $WorkDir

  & docker @buildArgs
  if ($LASTEXITCODE -ne 0) {
    throw "docker build failed, exit code: $LASTEXITCODE"
  }
}

Write-Host "==> Removing stale container: $ContainerName (if exists)"
& docker rm -f $ContainerName 2>$null | Out-Null

Write-Host "==> Running full build in container: $ContainerName"
Write-Host "    log file: $LogFile"

$runArgs = @(
  "run",
  "--name", $ContainerName,
  "-v", "${WorkDir}:/work",
  "-v", "${OutDir}:/out"
)
if (-not $KeepContainer) {
  $runArgs += "--rm"
}
if ($HttpProxy) {
  $runArgs += @("-e", "HTTP_PROXY=$HttpProxy", "-e", "http_proxy=$HttpProxy")
}
if ($HttpsProxy) {
  $runArgs += @("-e", "HTTPS_PROXY=$HttpsProxy", "-e", "https_proxy=$HttpsProxy")
}
$runArgs += @(
  "-e", "JOBS_STAGE1=$JobsStage1",
  "-e", "JOBS_FINAL=$JobsFinal",
  "-e", "MAKE_RETRIES=$MakeRetries",
  "-e", "MAKE_RETRY_DELAY=$MakeRetryDelay",
  "-e", "OUTPUT_TAR=$([int]$CreateTar.IsPresent)",
  $ImageName,
  "/bin/bash", "-lc",
  "set -o pipefail; bash /work/build.sh 2>&1 | tee /work/$LogFile"
)

& docker @runArgs
$runRc = $LASTEXITCODE
if ($runRc -ne 0) {
  throw "docker run/build failed, exit code: $runRc"
}

if (-not (Test-Path $OutputRoot)) {
  throw "Output directory not found: $OutputRoot"
}

Write-Host "==> Output directory generated: $OutputRoot"

$required = @(
  (Join-Path $OutputRoot "bin\\riscv32-unknown-elf-gcc.exe"),
  (Join-Path $OutputRoot "bin\\riscv32-unknown-elf-g++.exe"),
  (Join-Path $OutputRoot "bin\\riscv32-unknown-elf-gdb.exe"),
  (Join-Path $OutputRoot "bin\\riscv32-unknown-elf-as.exe"),
  (Join-Path $OutputRoot "bin\\riscv32-unknown-elf-ld.exe"),
  (Join-Path $OutputRoot "bin\\riscv32-unknown-elf-readelf.exe"),
  (Join-Path $OutputRoot "bin\\libstdc++-6.dll"),
  (Join-Path $OutputRoot "bin\\libgcc_s_seh-1.dll"),
  (Join-Path $OutputRoot "riscv32-unknown-elf\\include\\stdio.h"),
  (Join-Path $OutputRoot "riscv32-unknown-elf\\lib\\libstdc++.a")
)

Write-Host "==> Checking required files in output directory..."
foreach ($entry in $required) {
  if (-not (Test-Path $entry)) {
    throw "Output check failed, missing: $entry"
  }
  Write-Host "    OK  $entry"
}

if ($CreateTar) {
  if (-not (Test-Path $Artifact)) {
    throw "CreateTar was requested, but tar file not found: $Artifact"
  }
  $artifactInfo = Get-Item $Artifact
  $sizeGB = [Math]::Round($artifactInfo.Length / 1GB, 2)
  Write-Host "==> Tar generated: $Artifact ($sizeGB GB)"
}

Write-Host "==> Done"
Write-Host "    Build log: $(Join-Path $WorkDir $LogFile)"
