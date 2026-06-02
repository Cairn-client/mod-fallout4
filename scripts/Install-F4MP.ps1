<#
.SYNOPSIS
  Standalone installer for F4MP (Fallout 4 Multiplayer), classic direct-IP build.

.DESCRIPTION
  Drops the bundled mod files into your Fallout 4 install, enables the plugin,
  and sets the loose-files ini. Designed to run from inside the extracted
  release folder (the one that also contains the "Data" folder) on a machine
  that does NOT have the source repo or Visual Studio.

  It will:
    - auto-detect your Fallout 4 install (Bethesda/Steam registry, Steam
      library folders, then common paths),
    - check the game is 1.10.163 (the version this mod requires) and warn if not,
    - install F4SE 0.6.23 if it's missing (downloads from silverlock; pass
      -SkipF4SE to skip), and
    - copy the mod files, enable *f4mp.esp, and set bInvalidateOlderFiles=1.

.PARAMETER Fallout4Path
  Path to your Fallout 4 folder (the one with Fallout4.exe). Auto-detected if omitted.

.PARAMETER SkipF4SE
  Don't download/install F4SE even if it's missing (you'll install it yourself).

.PARAMETER Uninstall
  Remove the files this installer added and disable the plugin.

.EXAMPLE
  Right-click Install-F4MP.bat -> Run as administrator   (recommended)

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File Install-F4MP.ps1 -Fallout4Path "D:\SteamLibrary\steamapps\common\Fallout 4"
#>
param(
    [string]$Fallout4Path,
    [switch]$SkipF4SE,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocol]::Tls12 } catch {}

$PkgRoot  = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$F4SE_URL = 'https://f4se.silverlock.org/beta/f4se_0_06_23.7z'

function Info($m) { Write-Host "[ .. ] $m" -ForegroundColor Cyan }
function Good($m) { Write-Host "[ OK ] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "[FAIL] $m" -ForegroundColor Red }

function Find-Fallout4 {
    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Bethesda Softworks\Fallout4',
            'HKLM:\SOFTWARE\Bethesda Softworks\Fallout4')) {
        try {
            $v = (Get-ItemProperty -Path $key -ErrorAction Stop).'installed path'
            if ($v -and (Test-Path (Join-Path $v 'Fallout4.exe'))) { return $v.TrimEnd('\') }
        } catch {}
    }
    $steam = $null
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        try {
            $p = Get-ItemProperty -Path $key -ErrorAction Stop
            if ($p.SteamPath) { $steam = $p.SteamPath } elseif ($p.InstallPath) { $steam = $p.InstallPath }
            if ($steam) { break }
        } catch {}
    }
    if (-not $steam) { $steam = 'C:\Program Files (x86)\Steam' }
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    $libs = @($steam)
    if (Test-Path $vdf) {
        foreach ($line in Get-Content $vdf) {
            if ($line -match '"path"\s+"(.+?)"') { $libs += ($Matches[1] -replace '\\\\', '\') }
        }
    }
    foreach ($lib in ($libs | Select-Object -Unique)) {
        $c = Join-Path $lib 'steamapps\common\Fallout 4'
        if (Test-Path (Join-Path $c 'Fallout4.exe')) { return $c }
    }
    foreach ($p in @('C:\Program Files (x86)\Steam\steamapps\common\Fallout 4',
            'D:\SteamLibrary\steamapps\common\Fallout 4', 'E:\SteamLibrary\steamapps\common\Fallout 4')) {
        if (Test-Path (Join-Path $p 'Fallout4.exe')) { return $p }
    }
    return $null
}

function Copy-Tree($src, $dst) {
    $src = (Resolve-Path $src).Path.TrimEnd('\')
    Get-ChildItem -Path $src -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($src.Length).TrimStart('\')
        $target = Join-Path $dst $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item $_.FullName $target -Force
    }
}

function Install-F4SE($fo4) {
    $arc = Join-Path $env:TEMP 'f4se_0_06_23.7z'
    $ext = Join-Path $env:TEMP 'f4se_extract'
    Info "Downloading F4SE 0.6.23 ..."
    Invoke-WebRequest -Uri $F4SE_URL -OutFile $arc -UseBasicParsing
    Remove-Item $ext -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $ext | Out-Null
    $systar = Join-Path $env:WINDIR 'System32\tar.exe'   # bsdtar reads .7z on Win10/11
    if (-not (Test-Path $systar)) { Fail "tar.exe not found; install F4SE 0.6.23 manually from $F4SE_URL"; return }
    Push-Location $ext; & $systar -xf $arc; $code = $LASTEXITCODE; Pop-Location
    if ($code -ne 0) { Fail "Could not extract F4SE. Install it manually from $F4SE_URL"; return }
    $inner = Get-ChildItem $ext -Directory | Where-Object { $_.Name -like 'f4se_*' } | Select-Object -First 1
    if (-not $inner) { Fail "Unexpected F4SE archive layout; install it manually."; return }
    Copy-Tree $inner.FullName $fo4
    if (Test-Path (Join-Path $fo4 'f4se_loader.exe')) { Good "Installed F4SE 0.6.23." }
    else { Warn "F4SE copied but f4se_loader.exe not found -- check manually." }
}

function Enable-Plugin {
    $pl = Join-Path $env:LOCALAPPDATA 'Fallout4\plugins.txt'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $pl) | Out-Null
    $lines = @()
    if (Test-Path $pl) { $lines = Get-Content $pl }
    if (-not ($lines -match '(?i)^\*?f4mp\.esp$')) {
        Add-Content -Path $pl -Value '*f4mp.esp'
        Good "Enabled *f4mp.esp in plugins.txt"
    } else { Good "f4mp.esp already enabled in plugins.txt" }
}

function Set-LooseFilesIni {
    $ini = Join-Path $env:USERPROFILE 'Documents\My Games\Fallout4\Fallout4Custom.ini'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ini) | Out-Null
    $content = ''
    if (Test-Path $ini) { $content = Get-Content $ini -Raw }
    if ($content -notmatch '(?i)bInvalidateOlderFiles\s*=\s*1') {
        if ($content -and -not $content.EndsWith("`n")) { $content += "`r`n" }
        $content += "[Archive]`r`nbInvalidateOlderFiles=1`r`nsResourceDataDirsFinal=`r`n"
        Set-Content -Path $ini -Value $content -Encoding ASCII
        Good "Enabled loose files in Fallout4Custom.ini"
    } else { Good "Loose files already enabled in Fallout4Custom.ini" }
}

function Uninstall-Mod($fo4) {
    $data = Join-Path $fo4 'Data'
    $targets = @((Join-Path $data 'F4SE\Plugins\f4mp.dll'), (Join-Path $data 'f4mp.esp'))
    foreach ($rel in @('Scripts', 'Scripts\Fragments\Quests')) {
        Get-ChildItem (Join-Path $data $rel) -Filter '*F4MP*.pex' -ErrorAction SilentlyContinue |
            ForEach-Object { $targets += $_.FullName }
    }
    foreach ($t in $targets) { if (Test-Path $t) { Remove-Item $t -Force; Good "Removed $t" } }
    $pl = Join-Path $env:LOCALAPPDATA 'Fallout4\plugins.txt'
    if (Test-Path $pl) {
        (Get-Content $pl) | Where-Object { $_ -notmatch '(?i)^\*?f4mp\.esp$' } | Set-Content $pl
        Good "Disabled f4mp.esp in plugins.txt"
    }
    # Heal machines bricked by an older release that swapped in the SDK 1.64
    # steam_api64.dll: restore the game's original from the .orig backup if present.
    $bak = Join-Path $fo4 'steam_api64.dll.orig'
    if (Test-Path $bak) {
        Copy-Item $bak (Join-Path $fo4 'steam_api64.dll') -Force
        Remove-Item $bak -Force
        Good "Restored game's original steam_api64.dll (healed an older Steam-build install)"
    }
    Good "Uninstall complete."
}

# ===================================================================
Write-Host ''
Write-Host '=== F4MP (Fallout 4 Multiplayer) installer ===' -ForegroundColor White
Write-Host ''

if (-not $Fallout4Path) { $Fallout4Path = Find-Fallout4 }
if (-not $Fallout4Path -or -not (Test-Path (Join-Path $Fallout4Path 'Fallout4.exe'))) {
    Fail "Could not find your Fallout 4 install."
    Fail "Re-run from a terminal with:  .\Install-F4MP.ps1 -Fallout4Path `"X:\path\to\Fallout 4`""
    exit 1
}
$Fallout4Path = $Fallout4Path.TrimEnd('\')
Good "Fallout 4: $Fallout4Path"

if ($Uninstall) { Write-Host ''; Uninstall-Mod $Fallout4Path; Write-Host ''; exit 0 }

# Version gate
$ver = (Get-Item (Join-Path $Fallout4Path 'Fallout4.exe')).VersionInfo.ProductVersion
if ($ver -and -not $ver.StartsWith('1.10.163')) {
    Warn "Game version is $ver, but this mod needs 1.10.163 (classic)."
    Warn "The files will install, but the mod will NOT load until you downgrade"
    Warn "Fallout 4 to 1.10.163 (Steam can't do this through the normal update UI)."
} else {
    Good "Game version: $ver (correct)"
}

# F4SE
if (-not (Test-Path (Join-Path $Fallout4Path 'f4se_loader.exe'))) {
    if ($SkipF4SE) {
        Warn "F4SE not found and -SkipF4SE set. Install F4SE 0.6.23 yourself: $F4SE_URL"
    } else {
        Install-F4SE $Fallout4Path
    }
} else {
    Good "F4SE present (f4se_loader.exe)."
}

# Mod files
$srcData = Join-Path $PkgRoot 'Data'
if (-not (Test-Path $srcData)) {
    Fail "Bundled 'Data' folder not found next to this script ($srcData)."
    Fail "Run the installer from inside the extracted release folder."
    exit 1
}
Copy-Tree $srcData (Join-Path $Fallout4Path 'Data')
Good "Installed mod files (f4mp.dll + f4mp.esp + scripts) -> Data\"

Enable-Plugin
Set-LooseFilesIni

Write-Host ''
Good "Done. To play:"
Write-Host "  1. Make sure Fallout 4 is on 1.10.163 (see warning above if not)." -ForegroundColor Gray
Write-Host "  2. Launch the game with f4se_loader.exe (NOT the normal Fallout4 launcher)." -ForegroundColor Gray
Write-Host "  3. Load a save. A console window opens showing F4MP status." -ForegroundColor Gray
Write-Host "  4. Classic direct-IP co-op: one player runs f4mp_server.exe; others set the" -ForegroundColor Gray
Write-Host "     host address in config.txt and connect in-game. (Steam relay is WIP and" -ForegroundColor Gray
Write-Host "     not shipped in this build.)" -ForegroundColor Gray
Write-Host ''
