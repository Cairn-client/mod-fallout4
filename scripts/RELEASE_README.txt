**************************************************************
 *** IN DEVELOPMENT ***  Unfinished / experimental software.
 Expect bugs, crashes, and broken features. Back up your saves.
**************************************************************

==============================================================
 F4MP - Fallout 4 Multiplayer (classic direct-IP)  -  install guide
==============================================================

WHAT THIS IS
  A co-op mod for Fallout 4. Players connect directly: one person hosts
  (runs the included f4mp_server.exe), the others enter the host's IP and
  connect in-game with F1. No Steam lobby is used in this build.

  This is in-development software. Expect bugs and crashes. Back up your
  saves first. Do not run other Fallout 4 mods alongside it.

  (A Steam-relay transport that needs no IP sharing is still in development
  and is NOT included here - an earlier spike build of it could prevent the
  game from launching, so it has been removed from this release.)

------------------------------------------------------------
 REQUIREMENTS (every player needs these)
------------------------------------------------------------
  1. Fallout 4 on the PC version, downgraded to 1.10.163 (the "classic" /
     pre-Next-Gen build). The mod will NOT load on 1.11.x (Next-Gen).
     Steam's normal "update" UI cannot downgrade for you - search
     "Fallout 4 1.10.163 downgrade" for the current method (depot download
     or a 1.10.163 backup).
  2. F4SE 0.6.23 (the 1.10.163 build). The installer downloads this for you
     if it's missing.
  3. Everyone installs THIS SAME build. To connect, players need the host's
     IP address and the host must allow the F4MP port (7779 TCP+UDP) through
     their firewall / router (port-forward) for internet play; on a LAN no
     forwarding is needed.

------------------------------------------------------------
 HOW TO INSTALL
------------------------------------------------------------
  1. Extract this whole zip somewhere (keep "Data" next to the installer).
  2. Right-click  Install-F4MP.bat  ->  "Run as administrator".
     (Admin matters if Fallout 4 is under "C:\Program Files (x86)".)
     The installer auto-detects Fallout 4, checks the version, installs F4SE
     if needed, copies the mod files, and enables the plugin.

     If auto-detect fails, open PowerShell in this folder and run:
        .\Install-F4MP.ps1 -Fallout4Path "X:\path\to\Fallout 4"

  This installer does NOT touch Fallout 4's steam_api64.dll. (If a previous
  Steam-spike build of F4MP swapped yours and the game stopped launching,
  run  .\Install-F4MP.ps1 -Uninstall  to restore the original.)

------------------------------------------------------------
 HOW TO PLAY
------------------------------------------------------------
  1. Launch the game with  f4se_loader.exe  (NOT the normal launcher / Steam
     Play button).
  2. Load a save. A small console window opens showing F4MP status.
  3. Direct-IP co-op:
        - One player runs  f4mp_server.exe  to host (default port 7779).
        - Each other player sets the host's address in  config.txt
          (blank = localhost), then presses  F1  in-game to connect.
        - The console shows connection status.

------------------------------------------------------------
 UNINSTALL
------------------------------------------------------------
     .\Install-F4MP.ps1 -Uninstall

------------------------------------------------------------
 Project: https://github.com/saywhy2me/Fallout4Multiplayer
==============================================================
