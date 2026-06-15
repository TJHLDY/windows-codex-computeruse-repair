[CmdletBinding()]
param(
  [string]$PackageJson,
  [string]$ExpectedVersion = "0.4.10",
  [switch]$SkipVersionCheck,
  [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ExportSubpath = "./dist/project/cua/sky_js/src/targets/windows/internal/computer_use_client_base.js"
$InternalRelative = "dist\project\cua\sky_js\src\targets\windows\internal\computer_use_client_base.js"

function Find-SkyPackageJson {
  $root = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\runtimes\cua_node"
  if (-not (Test-Path -LiteralPath $root)) {
    return @()
  }

  Get-ChildItem -LiteralPath $root -Recurse -Filter package.json -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like "*node_modules\@oai\sky\package.json" } |
    Sort-Object LastWriteTime -Descending
}

function Get-BinRootFromSkyRoot {
  param([Parameter(Mandatory)][string]$SkyRoot)
  $oaiDir = Split-Path -Parent $SkyRoot
  $nodeModulesDir = Split-Path -Parent $oaiDir
  return Split-Path -Parent $nodeModulesDir
}

function Test-Import {
  param([Parameter(Mandatory)][string]$SkyRoot)

  $binRoot = Get-BinRootFromSkyRoot -SkyRoot $SkyRoot
  $nodeExe = Join-Path $binRoot "node.exe"
  if (-not (Test-Path -LiteralPath $nodeExe)) {
    Write-Warning "Could not find runtime node.exe at: $nodeExe"
    return
  }

  Push-Location $binRoot
  try {
    & $nodeExe --input-type=module -e "import { WindowsComputerUseClientBase } from '@oai/sky/dist/project/cua/sky_js/src/targets/windows/internal/computer_use_client_base.js'; console.log(typeof WindowsComputerUseClientBase);"
    if ($LASTEXITCODE -ne 0) {
      throw "Import test failed."
    }
  } finally {
    Pop-Location
  }
}

if (-not $PackageJson) {
  $candidates = @(Find-SkyPackageJson)
  if ($candidates.Count -eq 0) {
    throw "Could not find @oai/sky package.json. Pass -PackageJson explicitly."
  }
  if ($candidates.Count -gt 1 -and $Apply) {
    Write-Host "Multiple @oai/sky package.json files found:"
    $candidates | Select-Object FullName, LastWriteTime | Format-Table -AutoSize
    throw "Pass -PackageJson explicitly when using -Apply with multiple candidates."
  }
  $PackageJson = $candidates[0].FullName
}

if (-not (Test-Path -LiteralPath $PackageJson)) {
  throw "PackageJson does not exist: $PackageJson"
}

$skyRoot = Split-Path -Parent $PackageJson
$internalFile = Join-Path $skyRoot $InternalRelative

if (-not (Test-Path -LiteralPath $internalFile)) {
  throw "Expected internal file is missing: $internalFile"
}

$json = Get-Content -LiteralPath $PackageJson -Raw -Encoding UTF8 | ConvertFrom-Json
if ($json.name -ne "@oai/sky") {
  throw "Package is not @oai/sky: $($json.name)"
}

if (-not $SkipVersionCheck -and $json.version -ne $ExpectedVersion) {
  throw "Expected @oai/sky version $ExpectedVersion, found $($json.version). Use -SkipVersionCheck only if you understand the risk."
}

if ($null -eq $json.exports) {
  throw "package.json has no exports object. Refusing to create a new export map automatically."
}

$exportProperties = $json.exports.PSObject.Properties
$alreadyPresent = [bool]($exportProperties.Name -contains $ExportSubpath)

Write-Host "PackageJson: $PackageJson"
Write-Host "Version: $($json.version)"
Write-Host "Internal file exists: True"
Write-Host "Export present: $alreadyPresent"

if ($alreadyPresent) {
  Test-Import -SkyRoot $skyRoot
  Write-Host "No patch needed."
  exit 0
}

if (-not $Apply) {
  Write-Host "Dry run only. Re-run with -Apply to add the missing export."
  exit 0
}

$backup = "$PackageJson.bak-exports-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item -LiteralPath $PackageJson -Destination $backup -Force
Write-Host "Backup: $backup"

$json.exports | Add-Member -NotePropertyName $ExportSubpath -NotePropertyValue $ExportSubpath
$json | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $PackageJson -Encoding UTF8

Test-Import -SkyRoot $skyRoot
Write-Host "Patched @oai/sky exports successfully."

