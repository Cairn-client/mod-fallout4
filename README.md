# F4MP
[![Discord](https://img.shields.io/discord/729620961346977862.svg?label=&logo=discord&logoColor=ffffff&color=7389D8&labelColor=6A7EC2)](https://discord.gg/pKDHVvf)

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

## Quick start (recommended)

Helper scripts in [`scripts/`](scripts/) build everything and install it for you.

### Full setup (downloads F4SE + the mod, builds, installs, enables)
Double-click **`scripts\setup-everything.bat`** (needs an internet connection). It:

1. auto-detects Visual Studio's MSBuild and your Fallout 4 install,
2. builds `f4mp.dll`,
3. downloads & installs **F4SE 0.6.23** into the game folder,
4. downloads & installs the **F4MP mod** (`f4mp.esp` + scripts) and enables it,
5. compiles the updated Papyrus scripts to `.pex` *(if the Creation Kit is installed)*,
6. prints a coloured summary — anything yellow is a manual step it can't do.

### Just rebuild + redeploy your local changes
Double-click **`scripts\deploy.bat`** (no downloads — builds `f4mp.dll`, copies it and
the scripts into the game).

### Script options
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
Create `server_config.txt` next to `f4mp_server.exe` with the bind address (usually
`localhost`), then run:
```
f4mp_server.exe
```
Anyone on your local network can connect. To play over the internet, forward port **`7779`**
(both **TCP & UDP**); joiners put your public IP in their `config.txt`
(`Documents\My Games\Fallout4\F4MP\config.txt`).

## Running the game

1. Start `f4mp_server.exe`.
2. Launch Fallout 4 via **`f4se_loader.exe`** (not the normal launcher).
3. Load a save and press **`F1`** to connect.

---

## License & credits

F4MP — Copyright (C) 2020 Hyunsung Go. See [`LICENSE`](LICENSE).
Upstream: <https://github.com/cokwa/F4MP/>.
