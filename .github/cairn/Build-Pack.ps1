# Copyright (C) 2026 the Cairn contributors. SPDX-License-Identifier: GPL-3.0-only (as the project it is part of)
<#
.SYNOPSIS
    Builds the Cairn mod pack for Fallout 4 Multiplayer (F4MP): release\Cairn-Pack-fallout4-<version>.zip and release\pack-index.json
    (what the Cairn launcher reads to see a newer pack exists).

.DESCRIPTION
    An *external* pack (docs in the launcher repository: docs/PACKS.md): the mod goes into the game's own folder (installDir ".":
    Data\f4mp.esp, Data\F4SE\Plugins\f4mp.dll and the Papyrus scripts), and the game is started with F4SE (launch f4se_loader.exe).

      mod\   the "Data" folder of the upstream release (F4MP-v0.2-spike.zip, pinned by its SHA-256 in UPSTREAM.md)
      bin\   fo4-bridge.exe (the launcher's setup program: game version, F4SE, plugin switched on, loose files; built from
             .github\cairn\Fo4Bridge) and f4mp_server.exe (the mod's dedicated server, for direct-IP play)
      pack.json      the contract with the launcher
      manifest.txt   MOD|<path>|<size>|<sha256> and BIN|<path>|<size>|<sha256>, one line per file

    The pack's version is the VERSION file (strict X.Y.Z, this fork's own); the upstream release it carries is the pack's "upstream".
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Upstream,   # F4MP-v0.2-spike.zip
    [Parameter(Mandatory)][string] $Bridge      # fo4-bridge.exe
)

$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$version = (Get-Content (Join-Path $root 'VERSION') -TotalCount 1).Trim()
if ($version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw "VERSION must be strict X.Y.Z, got '$version'" }

# the upstream archive is a third-party input: it is the one the maintainers named, byte for byte
$notes = Get-Content (Join-Path $root 'UPSTREAM.md') -Raw
$expected = [regex]::Match($notes, '(?m)^upstream-sha256:\s*([0-9a-fA-F]{64})').Groups[1].Value
$upstreamVersion = [regex]::Match($notes, '(?m)^upstream-version:\s*(\S+)').Groups[1].Value
if (-not $expected -or -not $upstreamVersion) { throw 'UPSTREAM.md must carry upstream-version: and upstream-sha256:' }
$have = (Get-FileHash $Upstream -Algorithm SHA256).Hash
if ($have -ne $expected.ToUpperInvariant()) { throw "the upstream archive is not the pinned one (sha256 $have, expected $expected)" }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$release = Join-Path $root 'release'
$stage = Join-Path $release 'pack-stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'mod'), (Join-Path $stage 'bin') | Out-Null

function Expand-Safe([string] $zipPath, [string] $dest, [scriptblock] $pick) {
    $destFull = [IO.Path]::GetFullPath($dest).TrimEnd('\') + '\'
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $zipPath))
    try {
        foreach ($e in $zip.Entries) {
            $name = $e.FullName -replace '\\', '/'   # some archivers write backslashes
            if ($name.EndsWith('/')) { continue }
            $rel = & $pick $name
            if (-not $rel) { continue }
            $target = [IO.Path]::GetFullPath((Join-Path $dest ($rel -replace '/', '\')))
            if (-not $target.StartsWith($destFull, [StringComparison]::OrdinalIgnoreCase)) { throw "the archive has a path outside its folder: $($e.FullName)" }
            New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true)
        }
    } finally { $zip.Dispose() }
}

# Data\... goes to the game's Data folder; the server goes to bin; the installer scripts and the README are not part of the pack
Expand-Safe $Upstream (Join-Path $stage 'mod') { param($n) if ($n -like 'Data/*') { $n } }
Expand-Safe $Upstream (Join-Path $stage 'bin') { param($n) if ($n -eq 'f4mp_server.exe') { $n } }
Copy-Item $Bridge (Join-Path $stage 'bin\fo4-bridge.exe')
foreach ($n in @('mod\Data\f4mp.esp', 'mod\Data\F4SE\Plugins\f4mp.dll', 'mod\Data\Scripts\F4MP.pex', 'bin\f4mp_server.exe', 'bin\fo4-bridge.exe')) {
    if (-not (Test-Path (Join-Path $stage $n))) { throw "the pack is missing $n" }
}

function Get-Sha256([string] $Path) { (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

$launcherMin = '0.3.27'   # the launcher that runs a pack's own program (setup, logs) for an external mod
$packJson = [ordered]@{
    schema         = 2
    id             = 'fallout4'
    game           = 'fallout4'
    version        = $version
    upstream       = $upstreamVersion
    kind           = 'external'
    installDir     = '.'
    optionsProgram = 'bin/fo4-bridge.exe'
    setup          = $true
    launch         = 'f4se_loader.exe'
    launcherMin    = $launcherMin
}
[IO.File]::WriteAllText((Join-Path $stage 'pack.json'), (($packJson | ConvertTo-Json) + "`n"), (New-Object System.Text.UTF8Encoding($false)))

$lines = New-Object System.Collections.Generic.List[string]
foreach ($kind in @('mod', 'bin')) {
    $dir = Join-Path $stage $kind
    foreach ($f in Get-ChildItem $dir -Recurse -File | Sort-Object FullName) {
        $rel = $f.FullName.Substring($dir.Length + 1)
        $lines.Add(('{0}|{1}|{2}|{3}' -f $kind.ToUpperInvariant(), $rel, $f.Length, (Get-Sha256 $f.FullName)))
    }
}
[IO.File]::WriteAllText((Join-Path $stage 'manifest.txt'), (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))

$zipName = "Cairn-Pack-fallout4-$version.zip"
$zipPath = Join-Path $release $zipName
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
$fs = [IO.File]::Open($zipPath, 'Create')
try {
    $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in Get-ChildItem $stage -Recurse -File) {
            $rel = $f.FullName.Substring($stage.Length + 1) -replace '\\', '/'
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $rel, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $zip.Dispose() }
} finally { $fs.Dispose() }

$index = [ordered]@{
    schema      = 2
    id          = 'fallout4'
    game        = 'fallout4'
    version     = $version
    upstream    = $upstreamVersion
    kind        = 'external'
    file        = $zipName
    sha256      = Get-Sha256 $zipPath
    size        = (Get-Item $zipPath).Length
    launcherMin = $launcherMin
}
[IO.File]::WriteAllText((Join-Path $release 'pack-index.json'), (($index | ConvertTo-Json) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "pack: $zipPath ($([math]::Round((Get-Item $zipPath).Length / 1MB, 1)) MB), version $version, F4MP $upstreamVersion, $($lines.Count) files"
