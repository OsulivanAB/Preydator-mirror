param(
    [string]$Version = "1.7.3",
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"

$addonRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonName = Split-Path -Leaf $addonRoot

if (-not $OutputDirectory -or $OutputDirectory.Trim() -eq "") {
    $OutputDirectory = Split-Path -Parent $addonRoot
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}

$zipPath = Join-Path $OutputDirectory ("{0}-{1}.zip" -f $addonName, $Version)
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

$stagingDir = Join-Path $addonRoot ".release-staging"
if (Test-Path -LiteralPath $stagingDir) {
    Remove-Item -LiteralPath $stagingDir -Recurse -Force
}

New-Item -ItemType Directory -Path $stagingDir | Out-Null
$stagingAddonDir = Join-Path $stagingDir $addonName
New-Item -ItemType Directory -Path $stagingAddonDir | Out-Null

Get-ChildItem -LiteralPath $addonRoot -Force | Where-Object {
    $_.Name -ne ".release-staging" -and
    $_.Name -ne "issues" -and
    $_.Name -ne "CURSEFORGE_DESCRIPTION.md" -and
    $_.Name -ne ".gitattributes" -and
    $_.Name -ne ".git" -and
    $_.Name -ne ".vscode" -and
    $_.Name -ne "build-release.ps1"
} | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $stagingAddonDir -Recurse -Force
}

Compress-Archive -Path (Join-Path $stagingDir "*") -DestinationPath $zipPath -CompressionLevel Optimal -Force
Remove-Item -LiteralPath $stagingDir -Recurse -Force

Write-Host ("Release package created: {0}" -f $zipPath)
