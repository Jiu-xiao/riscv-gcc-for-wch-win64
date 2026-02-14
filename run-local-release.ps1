[CmdletBinding()]
param(
  [string]$WorkDir = "",
  [switch]$SkipToolchainBuild,
  [switch]$SkipImageBuild,
  [switch]$NoCache,
  [switch]$CreateTar,
  [int]$JobsStage1 = 32,
  [int]$JobsFinal = 32,
  [string]$HttpProxy = $env:HTTP_PROXY,
  [string]$HttpsProxy = $env:HTTPS_PROXY
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($WorkDir)) {
  $WorkDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$WorkDir = (Resolve-Path $WorkDir).Path

if (-not $SkipToolchainBuild) {
  Write-Host "==> Step 1/3: build toolchain (docker)"
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $WorkDir "run-full-build.ps1"),
    "-JobsStage1", $JobsStage1,
    "-JobsFinal", $JobsFinal
  )
  if ($SkipImageBuild) { $args += "-SkipImageBuild" }
  if ($NoCache) { $args += "-NoCache" }
  if ($CreateTar) { $args += "-CreateTar" }
  if ($HttpProxy) { $args += @("-HttpProxy", $HttpProxy) }
  if ($HttpsProxy) { $args += @("-HttpsProxy", $HttpsProxy) }

  & powershell @args
  if ($LASTEXITCODE -ne 0) {
    throw "run-full-build.ps1 failed, exit code: $LASTEXITCODE"
  }
}

Write-Host "==> Step 2/3: build installer exe"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $WorkDir "build-installer.ps1")
if ($LASTEXITCODE -ne 0) {
  throw "build-installer.ps1 failed, exit code: $LASTEXITCODE"
}

Write-Host "==> Step 3/3: installer smoke test"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $WorkDir "test-installer.ps1") -RebuildInstaller
if ($LASTEXITCODE -ne 0) {
  throw "test-installer.ps1 failed, exit code: $LASTEXITCODE"
}

Write-Host "==> Local release workflow passed"
