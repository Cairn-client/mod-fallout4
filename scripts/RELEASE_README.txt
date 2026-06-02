**************************************************************
 *** IN DEVELOPMENT ***  Unfinished / experimental software.
 Expect bugs, crashes, and broken features. Back up your saves.
**************************************************************

==============================================================
 F4MP - Fallout 4 Multiplayer (Steam build)  -  install guide
==============================================================

WHAT THIS IS
  A co-op mod for Fallout 4. This build includes the experimental Steam
  Networking spike: friends can connect by Steam lobby (press F5 to host,
  F6 to join) with no port-forwarding or IP sharing.

  This is in-development / spike software. Expect bugs and crashes. Back up
  your saves first. Do not run other Fallout 4 mods alongside it.

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
  3. Both players must be Steam friends (the co-op lobby is friends-only),
     and both must have THIS SAME build installed.

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

------------------------------------------------------------
 HOW TO PLAY
------------------------------------------------------------
  1. Launch the game with  f4se_loader.exe  (NOT the normal launcher / Steam
     Play button).
  2. Load a save. A small console window opens showing F4MP status.
  3. Co-op (Steam):
        - One player presses  F5  to HOST a lobby.
        - The other presses   F6  to JOIN (finds the friend's lobby).
        - The console prints   RECV "hello..."  /  RECV "ack..."  when the
          peer-to-peer link is up.
     (The classic direct-IP path is still on F1; see the project README.)

------------------------------------------------------------
 UNINSTALL
------------------------------------------------------------
     .\Install-F4MP.ps1 -Uninstall

------------------------------------------------------------
 Project: https://github.com/saywhy2me/Fallout4Multiplayer
==============================================================
