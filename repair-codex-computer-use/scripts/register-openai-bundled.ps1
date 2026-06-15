[CmdletBinding()]
param(
  [string]$Source,
  [string]$Target = (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Codex\openai-bundled-fixed-raw"),
  [switch]$Apply,
  [switch]$InstallPlugins
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

function Backup-CodexConfig {
  $backupDir = Join-Path $HOME (".codex\backups\openai-bundled-register-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
  New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

  $config = Join-Path $HOME ".codex\config.toml"
  $state = Join-Path $HOME ".codex\.codex-global-state.json"

  if (Test-Path -LiteralPath $config) {
    Copy-Item -LiteralPath $config -Destination (Join-Path $backupDir "config.toml") -Force
  }
  if (Test-Path -LiteralPath $state) {
    Copy-Item -LiteralPath $state -Destination (Join-Path $backupDir ".codex-global-state.json") -Force
  }

  return $backupDir
}

function Copy-DirectoryBytes {
  param(
    [Parameter(Mandatory)][string]$From,
    [Parameter(Mandatory)][string]$To
  )

  New-Item -ItemType Directory -Path $To -Force | Out-Null

  foreach ($dir in Get-ChildItem -LiteralPath $From -Recurse -Directory -Force) {
    $relative = $dir.FullName.Substring($From.Length).TrimStart("\")
    New-Item -ItemType Directory -Path (Join-Path $To $relative) -Force | Out-Null
  }

  foreach ($file in Get-ChildItem -LiteralPath $From -Recurse -File -Force) {
    $relative = $file.FullName.Substring($From.Length).TrimStart("\")
    $dest = Join-Path $To $relative
    $destDir = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $destDir)) {
      New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllBytes($dest, [System.IO.File]::ReadAllBytes($file.FullName))
  }
}

if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
  throw "codex command was not found on PATH."
}

if (-not $Source) {
  $candidates = @(Find-OpenAIBundledSource)
  if ($candidates.Count -eq 0) {
    throw "Could not find openai-bundled under WindowsApps. Pass -Source explicitly."
  }
  $Source = $candidates[0].FullName
}

if (-not (Test-Path -LiteralPath $Source)) {
  throw "Source does not exist: $Source"
}

$marketplace = Join-Path $Source ".agents\plugins\marketplace.json"
if (-not (Test-Path -LiteralPath $marketplace)) {
  throw "Source does not look like a Codex marketplace: $Source"
}

Write-Host "Source: $Source"
Write-Host "Target: $Target"

if (-not $Apply) {
  Write-Host "Dry run only. Re-run with -Apply to copy and register the marketplace."
  if ($InstallPlugins) {
    Write-Host "-InstallPlugins was provided, but no plugins will be installed without -Apply."
  }
  exit 0
}

if (Test-Path -LiteralPath $Target) {
  throw "Target already exists. Refusing to overwrite: $Target"
}

$backupDir = Backup-CodexConfig
Write-Host "Backed up Codex config to: $backupDir"

Copy-DirectoryBytes -From $Source -To $Target

$sourceFiles = (Get-ChildItem -LiteralPath $Source -Recurse -File -Force).Count
$targetFiles = (Get-ChildItem -LiteralPath $Target -Recurse -File -Force).Count
if ($sourceFiles -ne $targetFiles) {
  throw "Copy incomplete: source=$sourceFiles target=$targetFiles"
}

& codex plugin marketplace add $Target
if ($LASTEXITCODE -ne 0) {
  throw "codex plugin marketplace add failed."
}

if ($InstallPlugins) {
  & codex plugin add chrome@openai-bundled
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to install chrome@openai-bundled."
  }

  & codex plugin add computer-use@openai-bundled
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to install computer-use@openai-bundled."
  }
}

Write-Host "Done. Restart Codex Desktop or start a new thread if tools do not appear immediately."
