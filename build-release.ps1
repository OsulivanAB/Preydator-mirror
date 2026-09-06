param(
    [string]$Version = "4.0.0",
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

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

$stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString("N"))
$stagingAddonDir = Join-Path $stagingDir $addonName

try {
    New-Item -ItemType Directory -Path $stagingAddonDir -Force | Out-Null

    # Files reachable from Preydator.toc's active load list, the media/sound assets
    # code paths reference at runtime, plus the two player-facing docs (README/
    # CHANGELOG) worth shipping alongside the addon itself. Everything else at repo
    # root (CLAUDE.md, PREYDATOR_AGENT.md, PREYDATOR_ARCHITECTURE.md,
    # CURSEFORGE_DESCRIPTION.md, issues/, this script itself, etc.) is developer-only
    # and deliberately excluded, same as the superseded pre-rewrite files (old
    # Modules/*.lua monoliths, unused media) -- see Preydator.toc's trailing comment
    # block for why each superseded file is still kept in the working tree but must
    # not ship.
    $releaseInclude = @(
        "Preydator.toc",
        "Preydator.lua",
        "README.md",
        "CHANGELOG.md",
        "Locales",
        "Core\State.lua",
        "Core\Settings.lua",
        "Core\SlashCommands.lua",
        "Core\Adapters",
        "Core\Runtime",
        "Modules\HuntScanner",
        "UI",
        "media\Preydator_64.png",
        "media\Preydator_Normal_Difficulty.png",
        "media\Preydator_Hard_Difficulty.png",
        "media\Preydator_Nightmare_Difficulty.png",
        "sounds\predator-alert.ogg",
        "sounds\predator-ambush.ogg",
        "sounds\predator-snarl-01.ogg",
        "sounds\predator-torment.ogg",
        "sounds\predator-kill.ogg",
        "sounds\well-we-ve-prepared-a-trap-for-this-predator.ogg",
        "sounds\predator-kills-its-prey-to-survive.ogg",
        "sounds\echo-of-predation.ogg"
    )

    foreach ($entry in $releaseInclude) {
        $sourcePath = Join-Path $addonRoot $entry
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            throw ("Release include is missing: {0}" -f $entry)
        }

        $destinationPath = Join-Path $stagingAddonDir $entry
        $destinationParent = Split-Path -Parent $destinationPath
        if (-not (Test-Path -LiteralPath $destinationParent)) {
            New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
        }

        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Recurse -Force
    }

    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $stagingDir,
        $zipPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    if (-not (Test-Path -LiteralPath $zipPath)) {
        throw ("Release package was not created: {0}" -f $zipPath)
    }

    $archiveInfo = Get-Item -LiteralPath $zipPath
    if ($archiveInfo.Length -le 0) {
        throw ("Release package is empty: {0}" -f $zipPath)
    }

    Write-Host ("Release package created: {0}" -f $zipPath)
    Write-Host ("Release package size: {0} bytes" -f $archiveInfo.Length)
}
finally {
    if (Test-Path -LiteralPath $stagingDir) {
        Remove-Item -LiteralPath $stagingDir -Recurse -Force
    }
}
