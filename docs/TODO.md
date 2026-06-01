# F4MP — Incomplete & Buggy Spots (TODO)

Catalog from a code read of the plugin (`f4mp/`) and server (`f4mp_server/`) on 2026-06-01.
Priority focus: **keeping players connected to each other** (connection stability, client + server).

Severity legend: 🔴 critical (breaks/destabilizes MP) · 🟠 important · 🟡 polish/incomplete.

---

## A. Connection stability (PRIORITY)

### 🔴 A1. Server disables peer timeout entirely → zombie players never cleaned up
`f4mp_server/Server.h:56` — `enet_peer_timeout(event->peer, UINT32_MAX, UINT32_MAX, UINT32_MAX)`
sets the enet timeout to "never". A client that crashes, alt-F4s, or loses its network
*never* triggers `LIBRG_CONNECTION_DISCONNECT`, so its `librg_entity` and `Player` object live
forever. Every other client keeps seeing a frozen ghost, and entity slots leak over time.
- **Fix:** use a real timeout (e.g. enet defaults: `enet_peer_timeout(peer, 32, 5000, 30000)` =
  reset after 5s of no ACK, hard limit 30s). Pick values, then verify ghosts disappear when a
  client is killed.
- **Why it was set:** almost certainly to stop disconnects during long Papyrus stalls (loading
  screens) — see A3. Fixing A3 (app-level keepalive) lets us safely re-enable the timeout.

### 🔴 A2. Client has no reconnect / disconnect recovery
`f4mp/f4mp.cpp:625` `OnConnectRefuse` only logs `_ERROR`; `f4mp.cpp:631` `OnDisonnect` just
forwards to `player`. There is no retry, no backoff, no user-facing notification, and the
spawned remote-player actors are **not** cleaned up on the local side.
- **Fix:** on disconnect → fire a Papyrus event so `F4MPQuest` can notify the player and delete
  all cloned actors (it already tracks them in `players[]`/`playerIDs[]`). Add an optional
  auto-reconnect with capped exponential backoff. Re-send appearance/worn-items on reconnect.

### 🔴 A3. Client tick is driven by a Papyrus 0-second timer → starves during loading/menus
`F4MPQuest.psc:196` `OnTimer` → `F4MP.Tick()` → re-`StartTimer(0, tickTimerID)`. `F4MP::Tick`
(`f4mp.cpp:1013`) is what calls `librg_tick`. The Papyrus VM is **paused** during loading
screens, the pause menu, and dialogue, so `librg_tick` stops → no packets in/out → the link
goes half-open. Today this "works" only because A1 disabled the server timeout.
- **Fix:** decouple network ticking from the Papyrus VM. Options: run `librg_tick` on an F4SE
  task/own thread, or at minimum send an application-level heartbeat so both ends know the peer
  is alive across VM pauses. This is the linchpin that makes A1 safe to fix.

### 🟠 A4. `Connect()` starts timers before knowing if the connection succeeded
`F4MPQuest.psc:122-130` calls `StartTimer` for tick + update **before** `F4MP.Connect` returns,
and ignores the bool result. On a failed connect the timers keep ticking a dead context.
- **Fix:** only start timers when `F4MP.Connect` returns true; stop them on disconnect/failure.

### 🟠 A5. Fragile object lifetime: `delete this` in event handlers
Server `Entity::OnDisonnect` (`Entity.cpp:70`) and `Player::OnConnectRefuse`
(`Player.cpp:34`) both `delete this`. If librg ever delivers the event twice, or another
handler touches the entity after deletion in the same tick, that's a use-after-free / double
free → server crash (= everyone drops).
- **Fix:** null out `entity->user_data`/`peer->data` *before* delete (order is currently
  delete-then-null in `Entity::OnDisonnect`), and guard all `Entity::Get(...)` call sites for
  null (most already do; audit the message handlers).

### 🟠 A6. No config validation on either side
Server `main.cpp:18-24` reads `address`/`port` from `server_config.txt` with no validation —
a malformed file yields a garbage bind address/port and a silent failure to listen. Client
`config.txt` (`f4mp.cpp:75-86`) similarly trusts the file.
- **Fix:** validate address/port; on bind failure, log clearly and exit non-zero (server) or
  surface an error to the player (client).

### 🟡 A7. No graceful server shutdown / no connection logging summary
`f4mp_server/main.cpp:40` is `while(true){ Tick(); }` with no signal handling. Can't drain
clients or save state on exit. Also no periodic "N players connected" status line.
- **Fix:** trap Ctrl-C, broadcast a shutdown notice, `librg_network_stop` cleanly.

---

## B. Incomplete / stubbed features

### 🟠 B1. NPC sync — shared enemy health/death now wired (Level 1 in progress)
Server `NPC.cpp` is 13 lines (just serializes formID + owner on create). Spawn + position +
skeleton pose for NPCs already flow through the shared `Character`/`Entity` base path
(`SyncWorld` → server `OnSpawnEntity` → librg entity-create → client `NPC::OnEntityCreate`
→ `SetRef`), so the same placed enemies appear and move on both clients (relies on identical
load orders for matching formIDs). The `librg_message_send_all` broadcast in the server
`OnSpawnEntity` (`Server.h:189`) stays commented out on purpose — librg already streams
entity-create to all clients.

**Done (2026-06-01, untested at runtime — needs DLL rebuild + Papyrus recompile + 2 clients):**
shared **health/death**, mirroring the proven `Player` health pattern.
- `f4mp/NPC.{h,cpp}`: the controlling (authority) client streams the enemy's `health` fraction
  in `OnClientUpdate`; receivers read it in `OnEntityUpdate`, store it, and `Kill` their local
  copy once it reaches 0 (guarded by a `killed` flag). Byte layout stays symmetric because
  `Character::OnEntityUpdate` always consumes exactly the transforms+syncTime the authority wrote.
- `f4mp.cpp`: `SetEntVarNum`/`GetEntVarNum` generalized from `GetAs<Player>` to `Entity::Get`
  so the `health` Number works on NPC entities too (anim variants stay Player-specific).
- `F4MPQuest.psc`: new `npcSyncTimerID` poll (`SyncSharedNPCHealth`) pushes each nearby enemy's
  `GetValuePercentage(healthAV)` into its entity via the existing `SetEntVarNum` native. Only the
  owner actually streams it out; on non-owners it's a harmless local write.

**Still TODO for full Level 1:**
- **Cross-client damage routing.** Today an enemy only loses health on the machine whose player
  hits it; that owner then streams the result. If a *non-owner* shoots a shared enemy, the hit
  must travel to the owner to register. The `Hit`/`HitData` channel + server `OnHit`
  (routes to `librg_entity_control_get(hittee)`) is the right pipe — extend it so an NPC hittee
  applies `DamageValue` on the owner's real actor (mirror `F4MPPlayer.OnHit` for shared NPCs).
- Throttle the cell scan in `SyncSharedNPCHealth` (currently re-arms at 0s like the other timers
  — fold into the A3 tick-cadence fix).
- Optionally stop the receiver's local AI from re-deriving its own health (prevent revive jitter).

### 🟠 B2. Building / settlement sync is half-wired
`SyncWorld` (`f4mp.cpp:1072`) scans the player's cell for static objects (formType 36) and
collects `newBuildings`, and there are `SpawnBuilding`/`RemoveBuilding` message types + server
relays, but the receive/apply side and the "transform-only update" HACK (`SpawnBuildingData.baseFormID == 0`)
look unfinished. Settlement building is not reliably replicated.

### 🟡 B3. Dialogue / topic-info ("Speak") system is experimental
Large blocks in `f4mp.cpp` (`Connect` topic-info registration, the `Tick` topic-info remainder
loop, `TopicInfoBegin`) and big commented-out switch tables (`f4mp.cpp:178+`). The whole
NPC-speech replication path is exploratory and likely noisy/incomplete.

### 🟡 B4. Animation sync is partial / hardcoded
`Player::OnClientUpdate` (`Player.cpp:79`) maps movement to a fixed set of jog animations only;
jump states are commented out (`F4MPQuest.psc:185-188`), and there's a `// TODO: move this to the
Animation class` note. `weaponFire` fires `PlayerFireWeapon` but `OnFireWeapon` Papyrus handler
is commented out (`F4MPQuest.psc:91-98`).

### 🟡 B5. Appearance/worn-item sync has self-described HACKs and possible leaks
`Player::SetAppearance` (`Player.cpp:242`) has author comments: *"there might be some memory
leaks ... i'm sorry i don't know better"*, and TODOs for texture sync (`:312`) and tint sync
(`:380`). Worn items are matched by **full name string** (`client.h:89`), which is fragile across
load orders.

---

## C. Latent bugs (correctness)

### 🟠 C1. Inverted condition in `GetAction`
`f4mp.cpp:145` — `if (std::string(actions[i]->GetFullName()).compare(name.c_str()))` returns the
action when names **differ** (`.compare` returns 0 on a match). Should be `== 0`. Returns the
wrong action / first non-match.

### 🟡 C2. Hardcoded magic values
Server spawn point `(886, -426, -1550)` (`Server.h:45`); connect keybind F1=112 and target
`localhost:7779` (`F4MPQuest.psc:135-140`); runtime guard `RUNTIME_VERSION_1_10_163`
(`main.cpp:28`). Fine for a prototype; should be config-driven before wider testing.

### 🟡 C3. Multi-instance ("split client") machinery is complex and fragile
`activeInstance`/`nextActiveInstance` + `instances[]` vector (`f4mp.cpp:22-34`, `1057-1069`),
toggled by key 113. Each instance owns its own `librg_ctx`. Easy source of subtle bugs; document
or gate behind a flag.

### 🟡 C4. `Player::GetInteger` does an unchecked map lookup
`Player.cpp:131` — `integers.find(name)->second` dereferences `end()` if the key is missing
(author comment: *"HACK: horrible"*). Crash risk.

---

## Suggested order of attack (stability first)
1. **A3** (decouple ticking / heartbeat) → unblocks **A1** (re-enable server timeout) → **A2**
   (client reconnect + cleanup). This trio is what actually keeps players connected.
2. **A5 / A4 / A6** — harden lifetime, connect flow, and config.
3. **C1, C4** quick correctness fixes.
4. Then feature work: **B1** (NPC sync) and **B2** (buildings) for real shared gameplay.

---

## On "shared campaign / progression" (your question)
See `docs/SHARED_PROGRESSION.md` for the full answer. Short version: **partial yes, full no** —
the current "clone the player" design replicates *appearance + position + a few stats*, not quest
state, world state, or saves. True shared campaign progression is a large new subsystem, not a
tweak. Details and a phased plan are in that doc.
