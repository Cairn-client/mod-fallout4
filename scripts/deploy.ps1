<#
.SYNOPSIS
    F4MP one-click build + deploy.

.DESCRIPTION
    Builds the F4SE plugin (f4mp.dll) and copies it -- plus the Papyrus scripts --
    straight into your Fallout 4 "Data" folder, creating any missing folders.
    Auto-detects Visual Studio's MSBuild and your Fallout 4 install.

    For someone with no knowledge: just double-click deploy.bat and read the
    coloured summary at the end. Anything red is a manual step the script can't
    do for you (and tells you why).

.PARAMETER Fallout4Path
    Full path to your "Fallout 4" folder, e.g.
    "C:\Program Files (x86)\Steam\steamapps\common\Fallout 4".
    Only needed if auto-detection fails.

.PARAMETER Configuration
    Debug (default) or Release.

.PARAMETER SkipBuild
    Don't rebuild; just deploy whatever was last built.

.PARAMETER BuildServer
    Also build f4mp_server.exe (it does NOT get copied into the game folder).

.PARAMETER SetEnvVar
    Also set the FALLOUT4_PATH user environment variable so future plain
    Visual Studio builds auto-copy the DLL on their own.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1
#>
[CmdletBinding()]
param(
    [string]$Fallout4Path,
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [switch]$SkipBuild,
    [switch]$BuildServer,
    [switch]$SetEnvVar
)

$ErrorActionPreference = 'Stop'

# ---------- tiny helpers for friendly output ----------
function Info($m) { Write-Host "[ .. ] $m" -ForegroundColor Cyan }
function Good($m) { Write-Host "[ OK ] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "[FAIL] $m" -ForegroundColor Red }

# repo root is the parent of the folder this script lives in (\Fallout4Multiplayer\scripts\)
$RepoRoot = Split-Path -Parent $PSScriptRoot
Info "Repo root: $RepoRoot"

# ---------- locate MSBuild ----------
function Find-MSBuild {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $found = & $vswhere -latest -prerelease -products * `
            -requires Microsoft.Component.MSBuild `
            -find 'MSBuild\**\Bin\MSBuild.exe' 2>$null | Select-Object -First 1
        if ($found -and (Test-Path $found)) { return $found }
    }
    foreach ($p in @(
            'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe',
            'C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe',
            'C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe')) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

# ---------- locate Fallout 4 ----------
function Find-Fallout4 {
    # 1) Bethesda installer registry key
    foreach ($key in @(
            'HKLM:\SOFTWARE\WOW6432Node\Bethesda Softworks\Fallout4',
            'HKLM:\SOFTWARE\Bethesda Softworks\Fallout4')) {
        try {
            $v = (Get-ItemProperty -Path $key -ErrorAction Stop).'installed path'
            if ($v -and (Test-Path (Join-Path $v 'Fallout4.exe'))) { return $v.TrimEnd('\') }
        }
        catch {}
    }

    # 2) Walk every Steam library listed in libraryfolders.vdf
    $steam = $null
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        try {
            $p = (Get-ItemProperty -Path $key -ErrorAction Stop)
            if ($p.SteamPath) { $steam = $p.SteamPath }
            elseif ($p.InstallPath) { $steam = $p.InstallPath }
            if ($steam) { break }
        }
        catch {}
    }
    if (-not $steam) { $steam = 'C:\Program Files (x86)\Steam' }

    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    $libs = @($steam)
    if (Test-Path $vdf) {
        foreach ($line in Get-Content $vdf) {
            if ($line -match '"path"\s+"(.+?)"') {
                $libs += ($Matches[1] -replace '\\\\', '\')
            }
        }
    }
    foreach ($lib in ($libs | Select-Object -Unique)) {
        $candidate = Join-Path $lib 'steamapps\common\Fallout 4'
        if (Test-Path (Join-Path $candidate 'Fallout4.exe')) { return $candidate }
    }

    # 3) common fixed paths
    foreach ($p in @(
            'C:\Program Files (x86)\Steam\steamapps\common\Fallout 4',
            'D:\SteamLibrary\steamapps\common\Fallout 4',
            'E:\SteamLibrary\steamapps\common\Fallout 4')) {
        if (Test-Path (Join-Path $p 'Fallout4.exe')) { return $p }
    }
    return $null
}

# ===================================================================
Write-Host ''
Write-Host '=== F4MP build + deploy ===' -ForegroundColor White
Write-Host ''

# --- resolve Fallout 4 path ---
if (-not $Fallout4Path) { $Fallout4Path = Find-Fallout4 }
if (-not $Fallout4Path -or -not (Test-Path (Join-Path $Fallout4Path 'Fallout4.exe'))) {
    Fail "Could not find your Fallout 4 install."
    Fail "Re-run with:  -Fallout4Path `"X:\path\to\Fallout 4`""
    exit 1
}
$Fallout4Path = $Fallout4Path.TrimEnd('\')
Good "Fallout 4: $Fallout4Path"

# --- game version sanity warning (mod targets 1.10.163) ---
$ver = (Get-Item (Join-Path $Fallout4Path 'Fallout4.exe')).VersionInfo.ProductVersion
if ($ver -and -not $ver.StartsWith('1.10.163')) {
    Warn "Game version is $ver. This mod targets 1.10.163 (classic) and is built"
    Warn "against F4SE 0.6.23. It will NOT load on this version -- you must"
    Warn "downgrade Fallout 4 to 1.10.163 to actually run it in-game."
}

# --- build ---
if (-not $SkipBuild) {
    $msbuild = Find-MSBuild
    if (-not $msbuild) { Fail "MSBuild not found. Install Visual Studio with the C++ workload."; exit 1 }
    Good "MSBuild: $msbuild"

    $projects = @("$RepoRoot\f4mp\f4mp.vcxproj")
    if ($BuildServer) { $projects += "$RepoRoot\f4mp_server\f4mp_server.vcxproj" }

    foreach ($proj in $projects) {
        Info "Building $(Split-Path -Leaf $proj) ($Configuration|x64) ..."
        & $msbuild $proj /p:Configuration=$Configuration /p:Platform=x64 `
            /p:SolutionDir="$RepoRoot\" /v:minimal /nologo
        if ($LASTEXITCODE -ne 0) { Fail "Build failed for $proj"; exit 1 }
        Good "Built $(Split-Path -Leaf $proj)"
    }
}

# --- locate built DLL ---
$dll = "$RepoRoot\x64\$Configuration\f4mp.dll"
if (-not (Test-Path $dll)) { Fail "f4mp.dll not found at $dll (build it first)."; exit 1 }

# --- deploy: DLL ---
$pluginDir = Join-Path $Fallout4Path 'Data\F4SE\Plugins'
New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null
Copy-Item $dll (Join-Path $pluginDir 'f4mp.dll') -Force
Good "Copied f4mp.dll -> Data\F4SE\Plugins\"

# --- deploy: Papyrus script SOURCES (.psc) ---
$srcDir = "$RepoRoot\f4mp\scripts"
$userSrcDir = Join-Path $Fallout4Path 'Data\Scripts\Source\User'
New-Item -ItemType Directory -Force -Path $userSrcDir | Out-Null
$pscFiles = @('F4MP.psc', 'F4MPQuest.psc', 'F4MPPlayer.psc', 'F4MPFirePoint.psc', 'F4MPEntitySync.psc')
foreach ($f in $pscFiles) {
    $p = Join-Path $srcDir $f
    if (Test-Path $p) { Copy-Item $p $userSrcDir -Force }
}
Good "Copied Papyrus sources -> Data\Scripts\Source\User\"

# --- compile Papyrus to .pex if the Creation Kit compiler is present ---
$papyrus = Join-Path $Fallout4Path 'Papyrus Compiler\PapyrusCompiler.exe'
$scriptsOut = Join-Path $Fallout4Path 'Data\Scripts'
if (Test-Path $papyrus) {
    New-Item -ItemType Directory -Force -Path $scriptsOut | Out-Null
    $baseSrc = Join-Path $Fallout4Path 'Data\Scripts\Source\Base'
    $importPath = "$srcDir;$userSrcDir;$baseSrc"
    $flags = 'Institute_Papyrus_Flags.flg'
    $compiledAll = $true
    foreach ($f in @('F4MP.psc', 'F4MPQuest.psc', 'F4MPPlayer.psc', 'F4MPFirePoint.psc')) {
        $p = Join-Path $srcDir $f
        if (-not (Test-Path $p)) { continue }
        Info "Compiling $f ..."
        & $papyrus $p -import="$importPath" -output="$scriptsOut" -flags="$flags" -optimize
        if ($LASTEXITCODE -ne 0) { $compiledAll = $false; Warn "Failed to compile $f" }
    }
    if ($compiledAll) { Good "Compiled .pex -> Data\Scripts\" }
    else { Warn "Some scripts did not compile (see messages above)." }
}
else {
    Warn "Creation Kit Papyrus compiler not found -- skipped .pex compilation."
    Warn "Install the Fallout 4 Creation Kit to compile scripts, then re-run."
}

# --- optionally persist FALLOUT4_PATH so plain VS builds auto-copy the DLL ---
if ($SetEnvVar) {
    [Environment]::SetEnvironmentVariable('FALLOUT4_PATH', $Fallout4Path, 'User')
    Good "Set FALLOUT4_PATH (user env). Future VS builds will auto-copy the DLL."
}

# ---------- summary ----------
Write-Host ''
Write-Host '=== Done. Remaining MANUAL steps the script cannot do: ===' -ForegroundColor White
Warn  "1. Install F4SE 0.6.23 (game runtime 1.10.163) into the Fallout 4 folder."
Warn  "2. Add the F4MP .esp plugin + its assets (NOT in this repo -- get it from"
Warn  "   the upstream author) to Data\, and enable it in your plugin list."
if ($ver -and -not $ver.StartsWith('1.10.163')) {
    Warn "3. Downgrade Fallout 4 to 1.10.163 (current install is $ver)."
}
Write-Host ''
Good  "Plugin + scripts are in place. Launch via f4se_loader.exe, press F1 to connect."
Write-Host ''
