[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

function Write-Section {
  param([Parameter(Mandatory)][string]$Title)
  Write-Host ""
  Write-Host "== $Title =="
}

function Test-Command {
  param([Parameter(Mandatory)][string]$Name)
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Find-OpenAIBundledSource {
  $found = @()

  Get-Command codex -All -ErrorAction SilentlyContinue |
    Where-Object { $_.Source -and (Split-Path -Leaf $_.Source) -eq "codex.exe" } |
    ForEach-Object {
      $resourcesDir = Split-Path -Parent $_.Source
      $candidate = Join-Path $resourcesDir "plugins\openai-bundled"
      if (Test-Path -LiteralPath $candidate) {
        $found += Get-Item -LiteralPath $candidate
      }
    }

  $windowsApps = Join-Path $env:ProgramFiles "WindowsApps"
  if (Test-Path -LiteralPath $windowsApps) {
    Get-ChildItem -LiteralPath $windowsApps -Directory -Filter "OpenAI.Codex_*" -ErrorAction SilentlyContinue |
      ForEach-Object {
        $candidate = Join-Path $_.FullName "app\resources\plugins\openai-bundled"
        if (Test-Path -LiteralPath $candidate) {
          $found += Get-Item -LiteralPath $candidate
        }
      }
  }

  $found |
    Sort-Object FullName -Unique |
    Sort-Object LastWriteTime -Descending
}

function Find-SkyPackageJson {
  $root = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\runtimes\cua_node"
  if (-not (Test-Path -LiteralPath $root)) {
    return @()
  }

  Get-ChildItem -LiteralPath $root -Recurse -Filter package.json -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like "*node_modules\@oai\sky\package.json" } |
    Sort-Object LastWriteTime -Descending
}

$exportSubpath = "./dist/project/cua/sky_js/src/targets/windows/internal/computer_use_client_base.js"
$internalRelative = "dist\project\cua\sky_js\src\targets\windows\internal\computer_use_client_base.js"

Write-Section "Environment"
Write-Host "OS: $([System.Environment]::OSVersion.VersionString)"
Write-Host "User: $env:USERNAME"
Write-Host "Home: $HOME"

Write-Section "Codex CLI"
$codexCommands = Get-Command codex -All -ErrorAction SilentlyContinue
if (-not $codexCommands) {
  Write-Warning "codex command was not found on PATH."
} else {
  $codexCommands | Format-Table Source, CommandType, Version -AutoSize
}

if (Test-Command codex) {
  Write-Section "Codex Plugin Marketplaces"
  & codex plugin marketplace list

  Write-Section "Codex Plugins"
  & codex plugin list
}

Write-Section "Bundled Marketplace Source"
$sources = @(Find-OpenAIBundledSource)
if ($sources.Count -eq 0) {
  Write-Warning "Could not find app\resources\plugins\openai-bundled under WindowsApps."
} else {
  $sources | Select-Object FullName, LastWriteTime | Format-Table -AutoSize
}

Write-Section "@oai/sky Runtime"
$packages = @(Find-SkyPackageJson)
if ($packages.Count -eq 0) {
  Write-Warning "Could not find @oai/sky package.json under LOCALAPPDATA OpenAI Codex runtimes."
} else {
  foreach ($package in $packages) {
    Write-Host "Package: $($package.FullName)"
    try {
      $json = Get-Content -LiteralPath $package.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
      $skyRoot = Split-Path -Parent $package.FullName
      $internalFile = Join-Path $skyRoot $internalRelative
      $hasExport = $false
      if ($null -ne $json.exports) {
        $hasExport = [bool]($json.exports.PSObject.Properties.Name -contains $exportSubpath)
      }
      Write-Host "  name: $($json.name)"
      Write-Host "  version: $($json.version)"
      Write-Host "  internal file exists: $(Test-Path -LiteralPath $internalFile)"
      Write-Host "  export present: $hasExport"
    } catch {
      Write-Warning "  Failed to inspect package: $($_.Exception.Message)"
    }
  }
}

Write-Section "Summary"
Write-Host "If openai-bundled is missing, use register-openai-bundled.ps1."
Write-Host "If @oai/sky export is missing and the internal file exists, use patch-sky-exports.ps1."
