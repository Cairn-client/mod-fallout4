# F4MP


Fallout 4 Multiplayer Mod.

> **This project is experimental and not "playable" in the normal sense.** Expect
> game-breaking bugs and crashes. **Back up your game and saves before using it.**
> No other mods are supported at the same time.

This is a fork of [cokwa/F4MP](https://github.com/cokwa/F4MP/) with additional
work on **shared combat** (see below).

---

## What's new in this fork

The base mod uses a *"clone the player"* model: it shares each player's appearance,
position, and animation as a puppet actor, but every player is otherwise in their
own single-player world (separate quests, loot, enemies, saves).

This fork adds **Level 1 shared combat** — you now fight the *same* enemies together:

- **Shared NPC health & death.** The client that owns a given enemy (the first to
  see it) streams that enemy's health fraction; everyone else mirrors it and kills
  their local copy when it dies. So when one player drops a raider, it drops for
  both of you.
- **Cross-client damage routing.** If a player who does *not* own an enemy shoots it,
  the hit is routed to the owning client, applied to the authoritative actor, and the
  resulting health/death streams back. (The owner's own hits are applied locally, so
  damage is never double-counted.)

Implementation notes live in [`docs/SHARED_PROGRESSION.md`](docs/SHARED_PROGRESSION.md)
(what shared progression is/isn't possible) and [`docs/TODO.md`](docs/TODO.md)
(remaining work: connection-stability fixes, settlement sync, the "shared combat"
roadmap, and known polish items).

> **Status:** the C++ plugin **and** the Papyrus scripts both compile cleanly, and the
> full build/deploy pipeline is verified. The new combat features have **not** yet been
> runtime-tested in-game (that needs two connected clients on Fallout 4 1.10.163).

---

## Requirements

| For… | You need |
|------|----------|
| Running the mod | **Fallout 4 `1.10.163`** (the "classic"/pre-Next-Gen build) + **[F4SE `0.6.23`](https://f4se.silverlock.org/)** |
| Building the plugin/server | **Visual Studio 2022/2026** with the **Desktop development with C++** workload (MSVC v143) |
| Recompiling the Papyrus scripts | the **Fallout 4 Creation Kit** (free on Steam — it provides the Papyrus compiler) |

> ⚠️ **Game version matters.** The current Steam build of Fallout 4 is the Next-Gen
> update, which F4SE 0.6.23 and this plugin **will not** load. You must run the game on
> **1.10.163**. Downgrading is a manual Steam step the helper script cannot automate.

---

## How to install & play

There are two paths, depending on whether you just want to **play** or want to
**build from source**. Pick one.

---

### A) Players — easiest (no Visual Studio, no Creation Kit, no source code)

Use the prebuilt **release** — you run a single installer.

1. **Download** the latest `F4MP-Steam-*.zip` from the **[Releases page](../../releases)**.
2. **Extract the whole zip.** Your browser saves it to your **Downloads** folder; right-click
   the zip → **Extract All**. Keep `Install-F4MP.bat`, `Install-F4MP.ps1`, `README.txt`, and the
   `Data` folder together in the extracted folder.
3. **Right-click `Install-F4MP.bat` → "Run as administrator."**
   It auto-detects Fallout 4, checks the version, downloads **F4SE 0.6.23** if it's missing,
   copies the mod files in, and enables the plugin.
   *(If your game isn't found, run `Install-F4MP.ps1 -Fallout4Path "X:\...\Fallout 4"` from a terminal.)*
4. Make sure Fallout 4 is on **1.10.163** — see [Requirements](#requirements). Downgrade first
   if you're on the Next-Gen update.
5. **Launch the game with `f4se_loader.exe`** (in your Fallout 4 folder — *not* the normal Steam
   Play button). Load a save.
6. **Connect:**
   - **Steam co-op** (both players Steam friends, both on this build): one presses **F5** to host
     a lobby, the other presses **F6** to join.
   - **Classic direct-IP:** press **F1** (requires a running server — see [Server](#server)).

> 🟢 **Players do _not_ need Visual Studio, the Creation Kit, or this source repo — just the release zip.**

---

### B) Developers — build from source

This path **does** require **Visual Studio 2022/2026** (or the standalone *Build Tools for Visual
Studio*) with the **Desktop development with C++** workload, plus the **Creation Kit** to recompile
the Papyrus scripts. See [Requirements](#requirements).

The helper scripts in [`scripts/`](scripts/) build and install everything for you:

- **Full setup** — double-click **`scripts\setup-everything.bat`** (needs internet). It auto-detects
  your *already-installed* Visual Studio's MSBuild **(it does _not_ install Visual Studio — you must
  have it first)** and your Fallout 4 install, builds `f4mp.dll`, downloads & installs F4SE 0.6.23 +
  the mod, enables it, and compiles the Papyrus scripts (if the CK is present).
- **Rebuild + redeploy your local changes** — double-click **`scripts\deploy.bat`** (no downloads).

#### Script options
Run from a terminal (or append after the `.bat`):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1 [options]
```

| Option | Effect |
|--------|--------|
| `-All` | `-GetF4SE -GetMod -SetEnvVar` (what `setup-everything.bat` runs). |
| `-GetF4SE` | Download + install F4SE 0.6.23 into the game folder. |
| `-GetMod` | Download + install `f4mp.esp` + baseline scripts and enable the plugin. |
| `-SetEnvVar` | Persist `FALLOUT4_PATH` so plain Visual Studio builds auto-copy the DLL. |
| `-BuildServer` | Also build `f4mp_server.exe`. |
| `-SkipBuild` | Don't rebuild; just (re)deploy. |
| `-Configuration Release` | Build Release instead of Debug. |
| `-Fallout4Path "X:\...\Fallout 4"` | Use this if the game isn't auto-detected. |
| `-CreationKitPath "X:\...\Fallout 4 1946160"` | Use this if the CK isn't auto-detected. |
| `-Uninstall` | Remove the F4MP files this script installed (DLL, esp, scripts, plugin entry). |
| `-RemoveF4SE` | With `-Uninstall`, also remove the F4SE loader files. |

The script auto-detects the Creation Kit whether it's installed inside the game folder
or as a separate Steam app folder (e.g. `…\steamapps\common\Fallout 4 1946160`), extracts
the base script sources from `Base.zip`, and compiles using F4SE's extended sources so
the new features are active. If the CK isn't present, the baseline `.pex` from the mod
download are used and the new features stay dormant until you install the CK and re-run.

---

## Where files are deployed

All under your `…\steamapps\common\Fallout 4\` folder:

| File | Location | Installed by |
|------|----------|--------------|
| `f4mp.dll` | `Data\F4SE\Plugins\` | script (`deploy`) |
| `F4MP*.psc` (sources) | `Data\Scripts\Source\User\` | script |
| `F4MP*.pex` (compiled) | `Data\Scripts\` | script *(needs CK)* |
| `f4mp.esp` + quest fragment | `Data\` / `Data\Scripts\Fragments\Quests\` | script (`-GetMod`) |
| F4SE 0.6.23 (`f4se_loader.exe`, `f4se_1_10_163.dll`, …) | game root + `Data\` | script (`-GetF4SE`) |

### Where does `f4mp.esp` come from?
The mod plugin is **not** in this source repo. It ships in the upstream release
[`cokwa/F4MP-Archive`, `v0.1-indev`](https://github.com/cokwa/F4MP-Archive/releases/tag/v0.1-indev)
(`release-0.1indev.zip` → nested `f4mp-client.zip` → `f4mp.esp`). The `-GetMod` option
downloads and installs it for you.

---

## Manual build (if you prefer)

Repo root = the folder containing `f4se.sln`.

**Plugin (`f4mp.dll`):**
```
msbuild f4mp\f4mp.vcxproj /p:Configuration=Debug /p:Platform=x64 /p:SolutionDir=<repo-root>\
```
**Server (`f4mp_server.exe`, no game/F4SE dependency):**
```
msbuild f4mp_server\f4mp_server.vcxproj /p:Configuration=Debug /p:Platform=x64 /p:SolutionDir=<repo-root>\
```
Build output lands in `x64\Debug\`. Setting the `FALLOUT4_PATH` environment variable makes
the plugin's post-build step auto-copy `f4mp.dll` into `Data\F4SE\Plugins\`.

> **Plugin build prerequisite (not in this repo):** the plugin references the F4SE SDK as
> sibling folders (`..\f4se\`, `..\f4se_common\`, `..\..\common\`). Clone
> [ianpatt/f4se](https://github.com/ianpatt/f4se) (`v0.6.23`) and
> [ianpatt/common](https://github.com/ianpatt/common), place `f4se/`, `f4se_common/`,
> `xbyak/`, and `common/` per those paths, retarget them to v143, and set
> `WindowsTargetPlatformVersion` to `10.0`. The **server** has no such dependency.

---

## Server

```
# build once (or use deploy.ps1 -BuildServer)
msbuild f4mp_server\f4mp_server.vcxproj /p:Configuration=Debug /p:Platform=x64 /p:SolutionDir=<repo-root>\
```
Create `server_config.txt` next to `f4mp_server.exe`: **line 1** = bind address (usually
`localhost`), **line 2** = port (default `7779`), **line 3** (optional) = player spawn point
`x y z` (defaults to `886 -426 -1550`). Then run:
```
f4mp_server.exe
```
Anyone on your local network can connect. To play over the internet, forward port **`7779`**
(both **TCP & UDP**); joiners put your public IP in their `config.txt`
(`Documents\My Games\Fallout4\F4MP\config.txt`).

`config.txt` is read by the client at load: **line 1** = host address (IP/hostname; blank = `localhost`),
**line 2** = port (optional, defaults to `7779`). Pressing **F1** in-game connects to whatever it specifies,
so a non-default host port no longer needs a recompile — just edit the file. Example:
```
203.0.113.7
7779
```

## Running the game

Launch Fallout 4 via **`f4se_loader.exe`** (not the normal launcher) and load a save. Then connect one of two ways:

**Steam co-op (no server, no IP — recommended):** both players must be Steam friends on the same build.
- One player presses **`F5`** to host a Steam lobby.
- The other presses **`F6`** to join it.
- The console window prints `RECV "hello…"` / `RECV "ack…"` once the peer link is up.

**Classic direct-IP:**
1. Start `f4mp_server.exe`.
2. Launch via `f4se_loader.exe`, load a save.
3. Press **`F1`** to connect.

---

## License & credits

F4MP — Copyright (C) 2020 Hyunsung Go. See [`LICENSE`](LICENSE).
Upstream: <https://github.com/cokwa/F4MP/>.
