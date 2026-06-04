<#
.SYNOPSIS
  Read-only diagnostic for the "main menu shows but the buttons are missing"
  problem. Run this ON THE PC THAT FAILS and send the whole output back.

.DESCRIPTION
  Touches nothing. It reports the machine-specific state that survives a game
  reinstall and that causes a buttonless main menu on Fallout 4 1.10.163:
    - game version + whether you launched via f4se_loader
    - plugins.txt load order, and any ENABLED plugin whose file or master is missing
      (a missing master = the classic "no main-menu buttons" cause)
    - the [Archive] loose-files ini block
    - whether the deployed f4mp.dll is a Debug build (won't load without Visual
      Studio's debug C++ runtime on a normal gaming PC)
    - F4SE's own log lines about loading/skipping f4mp.dll
    - whether steam_api64.dll was swapped by an old Steam-spike build

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Diagnose-F4MP.ps1
#>
param([string]$Fallout4Path)

function Sec($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function OK($m) { Write-Host "[ OK ] $m" -ForegroundColor Green }
function WARN($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function BAD($m) { Write-Host "[FAIL] $m" -ForegroundColor Red }

# ---- locate Fallout 4 ----
function Find-Fallout4 {
    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Bethesda Softworks\Fallout4',
            'HKLM:\SOFTWARE\Bethesda Softworks\Fallout4')) {
        try { $v = (Get-ItemProperty $key -ErrorAction Stop).'installed path'
            if ($v -and (Test-Path (Join-Path $v 'Fallout4.exe'))) { return $v.TrimEnd('\') } } catch {}
    }
    $steam = $null
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        try { $p = Get-ItemProperty $key -ErrorAction Stop
            if ($p.SteamPath) { $steam = $p.SteamPath } elseif ($p.InstallPath) { $steam = $p.InstallPath }
            if ($steam) { break } } catch {}
    }
    if (-not $steam) { $steam = 'C:\Program Files (x86)\Steam' }
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'; $libs = @($steam)
    if (Test-Path $vdf) { foreach ($l in Get-Content $vdf) { if ($l -match '"path"\s+"(.+?)"') { $libs += ($Matches[1] -replace '\\\\', '\') } } }
    foreach ($lib in ($libs | Select-Object -Unique)) {
        $c = Join-Path $lib 'steamapps\common\Fallout 4'
        if (Test-Path (Join-Path $c 'Fallout4.exe')) { return $c }
    }
    return $null
}

if (-not $Fallout4Path) { $Fallout4Path = Find-Fallout4 }
if (-not $Fallout4Path -or -not (Test-Path (Join-Path $Fallout4Path 'Fallout4.exe'))) {
    BAD "Could not find Fallout 4. Re-run with: .\Diagnose-F4MP.ps1 -Fallout4Path `"X:\path\to\Fallout 4`""; exit 1
}
$Fallout4Path = $Fallout4Path.TrimEnd('\')
$data = Join-Path $Fallout4Path 'Data'

# Resolve the REAL "Documents" known folder (OneDrive often redirects it away
# from %USERPROFILE%\Documents). The game uses the known-folder path; the
# installer used the literal path -- if they differ, the game never sees the ini.
$litDocs = Join-Path $env:USERPROFILE 'Documents'
$realDocs = $litDocs
try {
    $p = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).Personal
    if ($p) { $realDocs = [Environment]::ExpandEnvironmentVariables($p).TrimEnd('\') }
} catch {}
$redirected = ($realDocs -and ($realDocs -ne $litDocs.TrimEnd('\')))

Sec "Fallout 4 install"
Write-Host "Path: $Fallout4Path"
$ver = (Get-Item (Join-Path $Fallout4Path 'Fallout4.exe')).VersionInfo.ProductVersion
if ($ver -and $ver.StartsWith('1.10.163')) { OK "Version $ver (correct)" } else { BAD "Version $ver -- mod needs 1.10.163" }
if (Test-Path (Join-Path $Fallout4Path 'f4se_loader.exe')) { OK "f4se_loader.exe present (launch the game with THIS, not the normal launcher)" }
else { BAD "f4se_loader.exe MISSING -- F4SE not installed" }

Sec "Load order  (%LOCALAPPDATA%\Fallout4\plugins.txt)"
$pl = Join-Path $env:LOCALAPPDATA 'Fallout4\plugins.txt'
if (-not (Test-Path $pl)) { WARN "No plugins.txt found." }
else {
    $lines = Get-Content $pl | Where-Object { $_ -and $_ -notmatch '^\s*#' }
    if (-not $lines) { WARN "plugins.txt is empty." }
    foreach ($line in $lines) {
        $enabled = $line -match '^\*'
        $name = $line.TrimStart('*').Trim()
        $tag = if ($enabled) { 'ENABLED ' } else { 'disabled' }
        $file = Join-Path $data $name
        if (Test-Path $file) {
            # check masters declared in the plugin header for missing files
            $missing = @()
            try {
                $bytes = [IO.File]::ReadAllBytes($file)
                $txt = -join ($bytes | ForEach-Object { [char]$_ })
                foreach ($m in [regex]::Matches($txt, '([\w \-\.\(\)]+\.es[pml])')) {
                    $mn = $m.Groups[1].Value.Trim()
                    if ($mn -and $mn -ne $name -and -not (Test-Path (Join-Path $data $mn)) -and ($missing -notcontains $mn)) { $missing += $mn }
                }
            } catch {}
            if ($missing.Count) { BAD "$tag $name  -> MISSING MASTER(S): $($missing -join ', ')   <-- this blanks the main menu" }
            else { OK "$tag $name" }
        } else {
            if ($enabled) { WARN "$tag $name  -> file NOT in Data (will be ignored)" } else { Write-Host "[ -- ] $tag $name (not present)" }
        }
    }
}

Sec "Documents folder (OneDrive redirection check)"
Write-Host "Literal %USERPROFILE%\Documents : $litDocs"
Write-Host "Real (known-folder) Documents   : $realDocs"
if ($redirected) {
    BAD "Documents is REDIRECTED (likely OneDrive). The game reads/writes the REAL path;"
    BAD "  the installer wrote ini/log to the LITERAL path -> game never sees the loose-files"
    BAD "  ini and F4SE's log looks 'missing'. THIS can blank the menu. Fix below."
} else { OK "Documents not redirected (game and installer agree on the path)." }

Sec "Loose-files ini  (Fallout4Custom.ini)"
$iniReal = Join-Path $realDocs 'My Games\Fallout4\Fallout4Custom.ini'
$iniLit  = Join-Path $litDocs  'My Games\Fallout4\Fallout4Custom.ini'
# The path the GAME actually uses is the real (known-folder) one.
if (Test-Path $iniReal) {
    $inv = (Get-Content $iniReal -Raw) -match '(?i)bInvalidateOlderFiles\s*=\s*1'
    if ($inv) { OK "REAL ini has bInvalidateOlderFiles=1  ($iniReal)" }
    else { BAD "REAL ini missing bInvalidateOlderFiles=1 -> loose F4MP scripts won't load  ($iniReal)" }
} else {
    BAD "No Fallout4Custom.ini at the REAL path the game uses: $iniReal"
}
if ($redirected -and (Test-Path $iniLit)) {
    WARN "A stale copy exists at the literal path ($iniLit) -- the game IGNORES it."
}

Sec "F4MP files in Data"
$dll = Join-Path $data 'F4SE\Plugins\f4mp.dll'
$esp = Join-Path $data 'f4mp.esp'
if (Test-Path $esp) { OK "f4mp.esp present" } else { BAD "f4mp.esp MISSING from Data" }
if (Test-Path $dll) {
    $size = (Get-Item $dll).Length
    OK "f4mp.dll present ($([math]::Round($size/1MB,1)) MB)"
    # Debug build detection: debug CRT imports + larger size
    try {
        $b = [IO.File]::ReadAllBytes($dll); $s = -join ($b | ForEach-Object { [char]$_ })
        $debug = ($s -match 'VCRUNTIME140D\.dll') -or ($s -match 'ucrtbased\.dll') -or ($s -match 'MSVCP140D\.dll')
        if ($debug) { BAD "f4mp.dll is a DEBUG build (imports debug CRT). It will NOT load on a PC without Visual Studio. Ship a RELEASE build." }
        else { OK "f4mp.dll links the redistributable (release) CRT" }
    } catch {}
} else { BAD "f4mp.dll MISSING from Data\F4SE\Plugins" }

Sec "F4SE log  (did F4SE actually run?)"
$logCandidates = @(
    (Join-Path $realDocs 'My Games\Fallout4\F4SE\f4se.log'),
    (Join-Path $litDocs  'My Games\Fallout4\F4SE\f4se.log'),
    (Join-Path $Fallout4Path 'f4se.log')
) | Select-Object -Unique
$log = $logCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($log) {
    OK "F4SE log found -> F4SE IS injecting. Log: $log"
    Get-Content $log | Where-Object { $_ -match '(?i)plugin|f4mp|version|loaded|fail|error|unable' } | Select-Object -Last 25 | ForEach-Object { Write-Host "  $_" }
} else {
    BAD "NO f4se.log anywhere -> F4SE is NOT injecting on this PC. The game is booting"
    BAD "  WITHOUT the script extender, which breaks F4MP's menu scripts (no buttons)."
    Write-Host "  Looked in:"; $logCandidates | ForEach-Object { Write-Host "    $_" }
    Write-Host "  Causes: (1) launching Fallout4.exe/Steam Play instead of f4se_loader.exe," -ForegroundColor Gray
    Write-Host "          (2) antivirus/Defender blocking f4se_loader.exe injection or its log write." -ForegroundColor Gray
}

Sec "steam_api64.dll  (old Steam-spike builds swapped this)"
if (Test-Path (Join-Path $Fallout4Path 'steam_api64.dll.orig')) {
    BAD "steam_api64.dll.orig backup present -> an old F4MP Steam build SWAPPED your steam_api64.dll. Heal: Install-F4MP.ps1 -Uninstall"
} else { OK "No steam_api64.dll.orig backup (not swapped by an old build)" }

Write-Host "`nDone. Send this entire output back." -ForegroundColor White
