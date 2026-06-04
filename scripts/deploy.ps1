<#
.SYNOPSIS
    F4MP one-click build + deploy (and optional auto-download of F4SE and the mod).

.DESCRIPTION
    - Builds the F4SE plugin (f4mp.dll) and copies it + the Papyrus scripts into
      your Fallout 4 "Data" folder (creating missing folders).
    - Optionally downloads & installs F4SE 0.6.23 (the 1.10.163 build) and the
      upstream F4MP mod (f4mp.esp + baseline compiled scripts), enables the plugin,
      and sets the loose-files ini so the mod loads.
    - Auto-detects Visual Studio's MSBuild and your Fallout 4 install.

    For someone with no knowledge: double-click setup-everything.bat (does it all),
    or deploy.bat (just build + copy). Read the coloured summary at the end --
    anything red is a manual step the script can't do (and tells you why).

.PARAMETER Fallout4Path
    Path to your "Fallout 4" folder. Only needed if auto-detection fails.
.PARAMETER Configuration   Debug (default) or Release.
.PARAMETER SkipBuild       Don't rebuild; just deploy/copy.
.PARAMETER BuildServer     Also build f4mp_server.exe (not copied into the game).
.PARAMETER GetF4SE         Download + install F4SE 0.6.23 into the game folder.
.PARAMETER GetMod          Download + install the F4MP mod (f4mp.esp + scripts) and enable it.
.PARAMETER SetEnvVar       Persist FALLOUT4_PATH so plain VS builds auto-copy the DLL.
.PARAMETER All             Shortcut for -GetF4SE -GetMod -SetEnvVar.
.PARAMETER CreationKitPath Path to the Creation Kit folder (auto-detected if omitted).
.PARAMETER Uninstall       Remove the F4MP mod files this script installed (see -RemoveF4SE).
.PARAMETER RemoveF4SE      With -Uninstall, also remove the F4SE loader files.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1 -All
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string]$Fallout4Path,
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [switch]$SkipBuild,
    [switch]$BuildServer,
    [switch]$Steam,
    [switch]$GetF4SE,
    [switch]$GetMod,
    [switch]$SetEnvVar,
    [switch]$All,
    [string]$CreationKitPath,
    [switch]$Uninstall,
    [switch]$RemoveF4SE
)

$ErrorActionPreference = 'Stop'
# GitHub / silverlock require TLS 1.2 (Windows PowerShell 5.1 doesn't always default to it).
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

if ($All) { $GetF4SE = $true; $GetMod = $true; $SetEnvVar = $true }

# ---- download URLs (verified June 2026) ----
$F4SE_URL = 'https://f4se.silverlock.org/beta/f4se_0_06_23.7z'
$MOD_URL = 'https://github.com/cokwa/F4MP-Archive/releases/download/v0.1-indev/release-0.1indev.zip'

# ---------- friendly output ----------
function Info($m) { Write-Host "[ .. ] $m" -ForegroundColor Cyan }
function Good($m) { Write-Host "[ OK ] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "[FAIL] $m" -ForegroundColor Red }

$RepoRoot = Split-Path -Parent $PSScriptRoot
Info "Repo root: $RepoRoot"

# ---------- generic helpers ----------
function Download-File($url, $dest) {
    Info "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    Good "Saved $([math]::Round((Get-Item $dest).Length/1MB,2)) MB -> $(Split-Path -Leaf $dest)"
}

# Merge-copy every file under $src into $dst, preserving relative structure.
function Copy-Tree($src, $dst) {
    $src = (Resolve-Path $src).Path.TrimEnd('\')
    Get-ChildItem -Path $src -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($src.Length).TrimStart('\')
        $target = Join-Path $dst $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item $_.FullName $target -Force
    }
}

function Find-MSBuild {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $found = & $vswhere -latest -prerelease -products * -requires Microsoft.Component.MSBuild `
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

function Find-Fallout4 {
    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Bethesda Softworks\Fallout4',
            'HKLM:\SOFTWARE\Bethesda Softworks\Fallout4')) {
        try {
            $v = (Get-ItemProperty -Path $key -ErrorAction Stop).'installed path'
            if ($v -and (Test-Path (Join-Path $v 'Fallout4.exe'))) { return $v.TrimEnd('\') }
        }
        catch {}
    }
    $steam = $null
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        try {
            $p = Get-ItemProperty -Path $key -ErrorAction Stop
            if ($p.SteamPath) { $steam = $p.SteamPath } elseif ($p.InstallPath) { $steam = $p.InstallPath }
            if ($steam) { break }
        }
        catch {}
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

# ---------- Creation Kit (Papyrus compiler) ----------
function Find-CreationKit($fo4) {
    if ($CreationKitPath -and (Test-Path (Join-Path $CreationKitPath 'Papyrus Compiler\PapyrusCompiler.exe'))) {
        return $CreationKitPath.TrimEnd('\')
    }
    # CK installed straight into the game folder (classic layout)
    if (Test-Path (Join-Path $fo4 'Papyrus Compiler\PapyrusCompiler.exe')) { return $fo4 }
    # CK as a separate Steam app folder, e.g. "...\steamapps\common\Fallout 4 1946160"
    $parent = Split-Path -Parent $fo4
    $sib = Get-ChildItem $parent -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'Papyrus Compiler\PapyrusCompiler.exe') } |
        Select-Object -First 1
    if ($sib) { return $sib.FullName }
    return $null
}

# Extract the CK's Base.zip (vanilla script sources + the flags file) if not already done.
function Ensure-BaseSources($ckRoot) {
    $base = Join-Path $ckRoot 'Data\Scripts\Source\Base'
    if (Test-Path (Join-Path $base 'Actor.psc')) { return $base }
    $zip = Join-Path $base 'Base.zip'
    if (-not (Test-Path $zip)) { return $null }
    Info "Extracting base script sources (Base.zip) ..."
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [System.IO.Compression.ZipFile]::OpenRead($zip)
    foreach ($e in $z.Entries) {
        if ($e.Name) {
            $t = Join-Path $base $e.FullName
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $t) | Out-Null
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $t, $true)
        }
    }
    $z.Dispose()
    return $base
}

# ---------- uninstall ----------
function Uninstall-Mod($fo4) {
    $data = Join-Path $fo4 'Data'
    $count = 0
    $targets = @((Join-Path $data 'F4SE\Plugins\f4mp.dll'),
        (Join-Path $data 'F4SE\Plugins\steam_api64_f4mp.dll'), (Join-Path $data 'f4mp.esp'))
    foreach ($pat in @('Scripts\F4MP*.pex', 'Scripts\Fragments\Quests\QF_F4MP_*.pex', 'Scripts\Source\User\F4MP*.psc')) {
        Get-ChildItem (Join-Path $data (Split-Path $pat -Parent)) -Filter (Split-Path $pat -Leaf) -ErrorAction SilentlyContinue |
            ForEach-Object { $targets += $_.FullName }
    }
    foreach ($t in $targets) {
        if (Test-Path $t) { Remove-Item $t -Force; Good "Removed $t"; $count++ }
    }
    $pl = Join-Path $env:LOCALAPPDATA 'Fallout4\plugins.txt'
    if (Test-Path $pl) {
        (Get-Content $pl) | Where-Object { $_ -notmatch '(?i)^\*?f4mp\.esp$' } | Set-Content $pl
        Good "Removed f4mp.esp from plugins.txt"
    }
    [Environment]::SetEnvironmentVariable('FALLOUT4_PATH', $null, 'User')
    Good "Cleared FALLOUT4_PATH"
    if ($RemoveF4SE) {
        foreach ($f in @('f4se_loader.exe', 'f4se_1_10_163.dll', 'f4se_steam_loader.dll', 'f4se_readme.txt', 'f4se_whatsnew.txt')) {
            $p = Join-Path $fo4 $f
            if (Test-Path $p) { Remove-Item $p -Force; Good "Removed $f"; $count++ }
        }
        Warn "Left F4SE's Data\Scripts entries (they share vanilla names -- removing risks the game)."
    }
    else { Info "Left F4SE installed (pass -RemoveF4SE to also remove its loader files)." }
    Warn "Left the Fallout4Custom.ini loose-files setting (other mods may rely on it)."
    Good "Uninstall complete -- removed $count file(s)."
}

# ---------- F4SE 0.6.23 ----------
function Install-F4SE($fo4) {
    $arc = Join-Path $env:TEMP 'f4se_0_06_23.7z'
    $ext = Join-Path $env:TEMP 'f4se_extract'
    Download-File $F4SE_URL $arc
    Remove-Item $ext -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $ext | Out-Null
    # bsdtar (libarchive) ships in Windows 10/11 System32 and reads .7z -- no 7-Zip needed.
    $systar = Join-Path $env:WINDIR 'System32\tar.exe'
    Push-Location $ext; & $systar -xf $arc; $code = $LASTEXITCODE; Pop-Location
    if ($code -ne 0) { Fail "Could not extract F4SE (.7z). Install 7-Zip and extract manually."; return }
    $inner = Get-ChildItem $ext -Directory | Where-Object { $_.Name -like 'f4se_*' } | Select-Object -First 1
    if (-not $inner) { Fail "Unexpected F4SE archive layout."; return }
    Copy-Tree $inner.FullName $fo4    # loaders -> game root, Data\Scripts\*.pex -> game Data
    if (Test-Path (Join-Path $fo4 'f4se_loader.exe')) { Good "Installed F4SE 0.6.23 (launch with f4se_loader.exe)." }
    else { Warn "F4SE copied but f4se_loader.exe not found -- check manually." }
}

# ---------- F4MP mod (f4mp.esp + baseline scripts) ----------
function Install-Mod($fo4) {
    $arc = Join-Path $env:TEMP 'f4mp_indev.zip'
    $ext = Join-Path $env:TEMP 'f4mp_indev_x'
    Download-File $MOD_URL $arc
    Remove-Item $ext -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $ext | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($arc, $ext)
    $clientZip = Join-Path $ext 'f4mp-client.zip'
    $clientDir = Join-Path $ext 'client'
    [System.IO.Compression.ZipFile]::ExtractToDirectory($clientZip, $clientDir)

    $data = Join-Path $fo4 'Data'
    New-Item -ItemType Directory -Force -Path $data | Out-Null
    Copy-Item (Join-Path $clientDir 'f4mp.esp') (Join-Path $data 'f4mp.esp') -Force
    Good "Installed f4mp.esp -> Data\"
    # Baseline compiled scripts + the CK-generated quest fragment (we have no source for the fragment).
    Copy-Tree (Join-Path $clientDir 'Scripts') (Join-Path $data 'Scripts')
    Good "Installed baseline .pex (incl. quest fragment) -> Data\Scripts\"

    Enable-Plugin
    Set-LooseFilesIni
}

# Enable f4mp.esp in the load order.
function Enable-Plugin {
    $pl = Join-Path $env:LOCALAPPDATA 'Fallout4\plugins.txt'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $pl) | Out-Null
    $lines = @()
    if (Test-Path $pl) { $lines = Get-Content $pl }
    if (-not ($lines -match '(?i)^\*?f4mp\.esp$')) {
        Add-Content -Path $pl -Value '*f4mp.esp'
        Good "Enabled f4mp.esp in plugins.txt"
    }
    else { Good "f4mp.esp already in plugins.txt" }
}

# Allow loose files (the .pex scripts) to load.
function Set-LooseFilesIni {
    # FO4 reads config from the Documents KNOWN folder, which OneDrive often
    # redirects off %USERPROFILE%\Documents. Resolve the real path so the ini
    # lands where the game looks (else loose .pex scripts never load).
    $docs = Join-Path $env:USERPROFILE 'Documents'
    try {
        $p = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).Personal
        if ($p) { $docs = [Environment]::ExpandEnvironmentVariables($p).TrimEnd('\') }
    } catch {}
    $ini = Join-Path $docs 'My Games\Fallout4\Fallout4Custom.ini'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ini) | Out-Null
    $content = ''
    if (Test-Path $ini) { $content = Get-Content $ini -Raw }
    if ($content -notmatch '(?i)bInvalidateOlderFiles\s*=\s*1') {
        if ($content -and -not $content.EndsWith("`n")) { $content += "`r`n" }
        $content += "[Archive]`r`nbInvalidateOlderFiles=1`r`nsResourceDataDirsFinal=`r`n"
        Set-Content -Path $ini -Value $content -Encoding ASCII
        Good "Enabled loose files in Fallout4Custom.ini"
    }
    else { Good "Loose files already enabled in Fallout4Custom.ini" }
}

# ===================================================================
Write-Host ''
Write-Host '=== F4MP build + deploy ===' -ForegroundColor White
Write-Host ''

if (-not $Fallout4Path) { $Fallout4Path = Find-Fallout4 }
if (-not $Fallout4Path -or -not (Test-Path (Join-Path $Fallout4Path 'Fallout4.exe'))) {
    Fail "Could not find your Fallout 4 install."
    Fail "Re-run with:  -Fallout4Path `"X:\path\to\Fallout 4`""
    exit 1
}
$Fallout4Path = $Fallout4Path.TrimEnd('\')
Good "Fallout 4: $Fallout4Path"

if ($Uninstall) {
    Write-Host ''
    Uninstall-Mod $Fallout4Path
    Write-Host ''
    exit 0
}

$ver = (Get-Item (Join-Path $Fallout4Path 'Fallout4.exe')).VersionInfo.ProductVersion
$wrongVer = $ver -and -not $ver.StartsWith('1.10.163')
if ($wrongVer) {
    Warn "Game version is $ver. This mod needs 1.10.163 (classic). It will NOT load"
    Warn "until you downgrade Fallout 4 to 1.10.163 (Steam can't do this automatically)."
}

if ($GetF4SE) { Install-F4SE $Fallout4Path }
if ($GetMod) { Install-Mod $Fallout4Path }

if (-not $SkipBuild) {
    $msbuild = Find-MSBuild
    if (-not $msbuild) { Fail "MSBuild not found. Install Visual Studio with the C++ workload."; exit 1 }
    Good "MSBuild: $msbuild"
    $projects = @("$RepoRoot\f4mp\f4mp.vcxproj")
    if ($BuildServer) { $projects += "$RepoRoot\f4mp_server\f4mp_server.vcxproj" }
    foreach ($proj in $projects) {
        $extra = @()
        if ($Steam -and $proj -like '*f4mp.vcxproj') { $extra += '/p:F4MPSteam=true' }
        Info "Building $(Split-Path -Leaf $proj) ($Configuration|x64)$(if ($extra) { ' [Steam]' }) ..."
        & $msbuild $proj /p:Configuration=$Configuration /p:Platform=x64 /p:SolutionDir="$RepoRoot\" $extra /v:minimal /nologo
        if ($LASTEXITCODE -ne 0) { Fail "Build failed for $proj"; exit 1 }
        Good "Built $(Split-Path -Leaf $proj)"
    }
}

$dll = "$RepoRoot\x64\$Configuration\f4mp.dll"
if (-not (Test-Path $dll)) { Fail "f4mp.dll not found at $dll (build it first)."; exit 1 }

# Our freshly-built DLL overwrites the older one from the mod download.
$pluginDir = Join-Path $Fallout4Path 'Data\F4SE\Plugins'
New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null
Copy-Item $dll (Join-Path $pluginDir 'f4mp.dll') -Force
Good "Copied our f4mp.dll -> Data\F4SE\Plugins\"

# Steam build loads its Steam networking API from a PRIVATELY-NAMED copy of the SDK
# redistributable, so the game's own (old) steam_api64.dll is never touched.
if ($Steam) {
    $shimSrc = "$RepoRoot\steamworks_sdk_164\sdk\redistributable_bin\win64\steam_api64.dll"
    if (Test-Path $shimSrc) {
        Copy-Item $shimSrc (Join-Path $pluginDir 'steam_api64_f4mp.dll') -Force
        Good "Copied Steam shim -> Data\F4SE\Plugins\steam_api64_f4mp.dll (game's steam_api64.dll untouched)"
    }
    else { Warn "Steamworks SDK DLL not found at $shimSrc -- Steam co-op natives (F5/F6) will no-op." }
}

$srcDir = "$RepoRoot\f4mp\scripts"
$userSrcDir = Join-Path $Fallout4Path 'Data\Scripts\Source\User'
New-Item -ItemType Directory -Force -Path $userSrcDir | Out-Null
foreach ($f in @('F4MP.psc', 'F4MPQuest.psc', 'F4MPPlayer.psc', 'F4MPFirePoint.psc', 'F4MPEntitySync.psc')) {
    $p = Join-Path $srcDir $f
    if (Test-Path $p) { Copy-Item $p $userSrcDir -Force }
}
Good "Copied Papyrus sources -> Data\Scripts\Source\User\"

# Recompile our updated scripts (enables the new NPC sync / damage routing) if the CK is present.
# Compiler must see, in priority order: our sources, then F4SE's extended sources (they define
# RegisterForExternalEvent / RegisterForKey / InstanceData), then the vanilla Base sources.
$ckRoot = Find-CreationKit $Fallout4Path
$scriptsOut = Join-Path $Fallout4Path 'Data\Scripts'
if ($ckRoot) {
    Good "Creation Kit: $ckRoot"
    $pc = Join-Path $ckRoot 'Papyrus Compiler\PapyrusCompiler.exe'
    $ckBase = Ensure-BaseSources $ckRoot
    $f4seSrc = Join-Path $Fallout4Path 'Data\Scripts\Source'
    New-Item -ItemType Directory -Force -Path $scriptsOut | Out-Null

    if (-not (Test-Path (Join-Path $f4seSrc 'ScriptObject.psc'))) {
        Warn "F4SE script sources missing from $f4seSrc -- the scripts won't compile."
        Warn "Run with -GetF4SE (or -All) first; skipping .pex compile (baseline .pex kept)."
    }
    elseif (-not $ckBase) {
        Warn "Base script sources (Base.zip) not found in the CK; skipping .pex compile."
    }
    else {
        $importPath = "$srcDir;$f4seSrc;$ckBase"
        $ok = $true
        foreach ($name in @('F4MP', 'F4MPQuest', 'F4MPPlayer', 'F4MPFirePoint')) {
            Info "Compiling $name ..."
            & $pc $name -import="$importPath" -output="$scriptsOut" -flags='Institute_Papyrus_Flags.flg' -optimize 2>&1 |
                Select-Object -Last 2 | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray }
            if ($LASTEXITCODE -ne 0) { $ok = $false; Warn "Failed to compile $name" }
        }
        if ($ok) { Good "Compiled updated .pex -> Data\Scripts\ (NEW features active)" }
        else { Warn "Some scripts failed to compile -- baseline .pex left in place." }
    }
}
else {
    Warn "Creation Kit not found -- using baseline .pex from the mod download."
    Warn "Our NEW features (NPC sync / damage routing) stay dormant until you install the"
    Warn "Creation Kit (or pass -CreationKitPath) and re-run; it recompiles the scripts."
}

if ($SetEnvVar) {
    [Environment]::SetEnvironmentVariable('FALLOUT4_PATH', $Fallout4Path, 'User')
    Good "Set FALLOUT4_PATH (user env)."
}

# ---------- summary ----------
Write-Host ''
Write-Host '=== Done. Remaining MANUAL steps the script cannot do: ===' -ForegroundColor White
# Report on actual presence, not just whether the flag was passed this run.
if (-not (Test-Path (Join-Path $Fallout4Path 'f4se_loader.exe'))) { Warn "- F4SE not installed (run with -GetF4SE or -All)." }
if (-not (Test-Path (Join-Path $Fallout4Path 'Data\f4mp.esp'))) { Warn "- f4mp.esp not installed (run with -GetMod or -All)." }
if ($wrongVer) { Warn "- Downgrade Fallout 4 to 1.10.163 (current: $ver). Steam can't automate this." }
Write-Host ''
Good  "When on 1.10.163 with F4SE: launch f4se_loader.exe, load a save, press F1 to connect."
Write-Host ''
