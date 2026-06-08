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

### 🟠 A2. Client disconnect recovery — cleanup half DONE (2026-06-01); reconnect half remaining
- ✅ **Cleanup (done):** `F4MP::OnDisonnect` now raises an `OnDisconnect` external event;
  `F4MPQuest.OnDisconnect` deletes all cloned remote-player actors and cancels the network
  timers, plus a user-facing notification. No more lingering ghost clones / timers on a dead
  context. Compiles (C++ + Papyrus). Not runtime-tested.
- ⏳ **Reconnect (remaining, needs runtime):** auto-reconnect with capped exponential backoff,
  and re-send appearance/worn-items on reconnect (`OnConnectRefuse` still only logs). Pairs with
  A3/A1 and needs a 1.10.163 runtime to validate (timing, re-handshake, no duplicate clones).

### 🟢 A3. Client tick is driven by a Papyrus 0-second timer → starves during loading/menus — CODE LANDED (2026-06-07), runtime-test owed
`F4MPQuest.psc:196` `OnTimer` → `F4MP.Tick()` → re-`StartTimer(0, tickTimerID)`. `F4MP::Tick`
(`f4mp.cpp:1013`) is what calls `librg_tick`. The Papyrus VM is **paused** during loading
screens, the pause menu, and dialogue, so `librg_tick` stops → no packets in/out → the link
goes half-open. Today this "works" only because A1 disabled the server timeout.
- **Fix:** decouple network ticking from the Papyrus VM. This is the linchpin that makes A1 safe.

**Concrete implementation plan (ready to build; needs 2-client runtime validation — do NOT land blind):**
There is already an F4SE delay functor (`f4mp.cpp` ~`301`, registered on `PostLoadGame`) that
reschedules every ~1ms on the **main thread** and runs across Papyrus VM pauses (it drives
animation via `librg_entity_iterate(... OnTick())`). Use it as the single network driver:
1. **Single-thread the ctx.** Move `librg_tick(&instance->ctx)` from the Papyrus `F4MP::Tick`
   into that functor. Make the Papyrus tick timer stop calling the network path. This avoids a
   data race (today the Papyrus VM thread and the main-thread functor would both touch `ctx`).
2. **Move `SyncWorld` to the functor too**, throttled to ~every 100ms (not 1ms — it's a full
   cell scan + message sends). Running it on the main thread is also *safer* for game-object
   access than the current Papyrus-thread call.
3. **Keep one owner of `ctx`.** After this, only the functor calls `librg_tick` / `SyncWorld` /
   `librg_message_send_*`; Papyrus natives that send (`PlayerHit`, `PlayerFireWeapon`) should
   enqueue into a small thread-safe queue the functor flushes, OR be guarded by a single
   `std::mutex` around all `ctx` access. Prefer the single-owner queue (no lock-sprawl).
4. **Watch the split-client machinery** (`activeInstance`/`instances[]`, C3): the
   `nextActiveInstance` bookkeeping currently lives in `F4MP::Tick`; it must move with the tick.
- **Why not landed yet:** this changes the network threading model; a wrong move crashes on
  connect, and it can't be validated without FO4 1.10.163 + two clients. Implement + test
  together once a runtime exists; then A1 (re-enable server timeout) becomes safe.

**✅ IMPLEMENTED 2026-06-07 (code, build-verified Debug x64; NOT YET runtime-tested):**
- The F4SE main-thread delay functor (`f4mp.cpp` PostLoadGame `OnTick::Run`) now drives the
  network: it runs `SyncWorld` throttled to ~10 Hz, then `librg_tick` over every split-client
  instance throttled to ~30 Hz (the validated Phase-1 cap), then advances `activeInstance` +
  grows the instance pool. Independent throttles via function-local `static double` (shared
  across functor instances, so even a duplicate PostLoadGame functor can't double-tick).
- `F4MP::Tick` (Papyrus native) is gutted of the network loop + instance advancement; it now
  only drains deferred topic-info registrations (kept Papyrus-side because it raises Papyrus
  external events). `F4MPQuest.psc` tickTimer therefore no longer governs the pump (comments
  updated; `.pex` unchanged — comment-only edit).
- **Chose the single-mutex guard, not the queue.** Added `static std::recursive_mutex
  F4MP::networkMutex` + `using NetLock`. Every ctx/instance/entity-data access is serialized:
  the functor's whole network block, and the natives `Connect`/`Disconnect`/`SetClient`/
  `IsConnected`/`Tick`/`SyncWorld`/`FetchEntity`/`PlayerHit`/`PlayerFireWeapon`/`Set|GetEntVar*`/
  `Set|GetEntityPosition`/`IsEntityValid`/`IsEntityMine`/`Get(Player)EntityID`/`SetEntityRef` +
  the `TopicInfoBegin` Speak send. Recursive because the functor locks once around `librg_tick`,
  whose receive handlers re-enter via `FetchEntity`. No second lock exists → no deadlock; the
  receive handlers now also run on the main thread (safer for game-object access).
- **Runtime test still owed (2 × FO4 1.10.163 clients):** confirm connect doesn't crash, that
  the link survives a loading screen / pause menu (the whole point), and that movement/health/
  building sync still flow. Only after this passes is **A1** (re-enable server peer timeout)
  safe to land.

### ✅ A4. `Connect()` starts timers before knowing if the connection succeeded — DONE (2026-06-01)
`F4MPQuest.Connect` now captures `F4MP.Connect`'s result and only `StartTimer`s the
tick/update/npc-sync timers when it's true. (Stop-on-disconnect is folded into A2.)
Papyrus recompiles clean. Not runtime-tested.

### 🟠 A5. Fragile object lifetime: `delete this` in event handlers
Server `Entity::OnDisonnect` (`Entity.cpp:70`) and `Player::OnConnectRefuse`
(`Player.cpp:34`) both `delete this`. If librg ever delivers the event twice, or another
handler touches the entity after deletion in the same tick, that's a use-after-free / double
free → server crash (= everyone drops).
- **Fix:** null out `entity->user_data`/`peer->data` *before* delete (order is currently
  delete-then-null in `Entity::OnDisonnect`), and guard all `Entity::Get(...)` call sites for
  null (most already do; audit the message handlers).

### ✅ A6. No config validation on either side — DONE (2026-06-01)
Server clamps an invalid/missing port back to 7779 with a warning and logs the bind target
(`address:port`, or "all interfaces"). Client defaults a blank `config.txt` host to `localhost`.
Turns silent bind/connect failures into clear messages. Compiles. Not runtime-tested.

### ✅ A7. Graceful server shutdown + connection logging — DONE (2026-06-02)
`f4mp_server/main.cpp` now traps `SIGINT`/`SIGTERM` (handler flips a `g_running`
flag; the `while(true)` became `while(g_running)`). On exit it `delete server`s so
`~Server()` runs `librg_network_stop`/`librg_free` and clients see a clean disconnect
instead of a half-open link. Added `Server::PlayerCount()` (iterates
`LIBRG_ENTITY_ALIVE|LIBRG_ENTITY_CLIENT`) and a 15s periodic
`[status] N player(s) connected` line (printed only when the count changes).
Build-verified Debug x64 + boot-tested (binds, prints status, stable). Commit `49da092`.
- Not done (needs client + runtime): broadcasting an in-game shutdown *notice* to
  clients requires a new MessageType + client/Papyrus handling — deferred.

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

**Done (2026-06-01, untested at runtime):** **cross-client damage routing.** A non-owner's hits
on a shared enemy now travel to the owner, who applies them to the authoritative actor; the
resulting health streams back via the NPC health sync.
- `f4mp/NPC.{h,cpp}`: `mine` flag (set in `OnClientUpdate`, since librg only streams that to the
  controller) + `IsMine()`. `f4mp.cpp`: `IsEntityMine` native; `OnHit` extended so an NPC hittee
  fires the `OnNPCHit` external event on the owner instead of the player-only path.
- `F4MPQuest.psc`: `RegisterForHitEvent` on each shared enemy in the sync loop; `Event OnHit`
  routes the local player's damage via `PlayerHit` **only when `!IsEntityMine`** (the owner's own
  hits already count locally — routing them would double the damage); `Function OnNPCHit` applies
  `DamageValue(healthAV, damage)` on the owner. Server needs no change: its `OnHit` already routes
  `HitData` to `librg_entity_control_get(hittee)` = the owner.

**Still TODO for full Level 1:**
- Throttle the cell scan in `SyncSharedNPCHealth` (currently re-arms at 0s like the other timers
  — fold into the A3 tick-cadence fix).
- A non-owner's *local* enemy copy still takes real weapon damage before the owner's value
  overwrites it, so HP can briefly diverge on the shooter's screen (converges on death). Cleanest
  fix is making non-owner copies damage-immune puppets (drifts toward Level 2 authority model).
- Routed damage uses `InstanceData.GetAttackDamage` (base weapon damage), not the fully-resolved
  hit (armor/resistances/perks). Good enough for L1; revisit if balance matters.

### 🟠 B2. Building / settlement sync — receive side hardened (2026-06-02)
`SyncWorld` (`f4mp.cpp`) scans the player's cell for static objects (formType 36) and collects
`newBuildings`; `SpawnBuilding`/`RemoveBuilding` message types + server relays exist. The
receive/apply handlers were wired but crash-prone.

**Done (2026-06-02, C++ only, build-verified, untested at runtime):** receive-side hardening.
- `OnSpawnBuilding`: guard the base-form lookup (null on load-order mismatch) and the
  `PlaceAtMe_Native` result (could return null → the old code dereferenced it via
  `MoveTo`/`building->formID` and crashed the client). Also erase a stale `knownBuildings`
  entry before overwriting a re-spawned `uniqueID`. The transform-only update path
  (`baseFormID == 0`) now has a clear "drop if we have no local copy yet" comment.
- `OnRemoveBuilding`: fixed a **use-after-free** — `building` is an iterator into
  `self.buildings`, and the erase loop deleted that key from every instance (incl. self),
  invalidating it before `building->second.formID` was read (UAF even with one instance).
  Now caches the key + local formID into locals before the loop.

**Still TODO (needs 2-client runtime):**
- Transform updates only flow from the original placer: a receiver that moves a received
  building broadcasts a key `(receiverPlayerID, receiverLocalFormID)` the original placer
  can't match, so the move isn't echoed back. Needs a shared/canonical building ID.
- Out-of-order delivery: a transform update arriving before its spawn is dropped (no buffering).
- The build-detection cell scan still re-arms at 0s like the other timers (fold into A3).

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

### ✅ C1. Inverted condition in `GetAction` — DONE (2026-06-01)
Now compares `== 0`, so `GetAction` returns the action whose name actually matches instead of
the first non-matching one. Compiles.

### ✅ C2. Hardcoded magic values — DONE (2026-06-02)
- ✅ **Connect port** is now read from `config.txt` (line 2; defaults 7779, validated). The
  F1 keybind calls `Connect("", 0)` so config drives both host **and** port; an explicit
  positive port from any caller still wins (`f4mp.cpp` LoadConfig + Connect, `client.h` Config,
  `F4MPQuest.psc`). Lets a user reach a friend on a non-default port without recompiling.
  README + RELEASE_README document the config format.
- ✅ **Server spawn point** is config-driven: optional `x y z` line after address+port in
  `server_config.txt` (`Server.h` ctor + member; `f4mp_server/main.cpp` parse). Defaults to the
  original `(886,-426,-1550)` when absent/malformed (all-or-nothing parse). Server logs the spawn
  point at boot. Boot-tested: `100.5 -200.25 -300.75` read back correctly.
- ✅ **Connect keybind** de-magicked: `F4MPQuest.psc` now has a single named `connectKeyCode = 112`
  (F1) used in both `OnInit` `RegisterForKey` and `OnKeyDown`. (Full file-config for a keybind
  would need a new native + can't be runtime-tested; a single named source is the sensible level.)
- ✅ **Runtime guard `RUNTIME_VERSION_1_10_163`** (`f4mp/main.cpp`): deliberately left a fixed
  compile-time ABI gate — the DLL is built against 1.10.163 offsets/RTTI, so loading on another
  runtime would crash, not "work with a config tweak". Added a comment documenting the decision.
- Build-verified: server + plugin (Debug x64) and `F4MPQuest.pex` recompiled clean (CK 2.8.0.4).

### 🟡 C3. Multi-instance ("split client") machinery is complex and fragile
`activeInstance`/`nextActiveInstance` + `instances[]` vector (`f4mp.cpp:22-34`, `1057-1069`),
toggled by key 113. Each instance owns its own `librg_ctx`. Easy source of subtle bugs; document
or gate behind a flag.

### ✅ C4. Unchecked map lookups — DONE (2026-06-01)
Both `Player::GetInteger` and `Entity::GetNumber` now check the iterator and return 0 for a
missing key instead of dereferencing `end()`. Removes a latent client crash. Compiles.

---

## Suggested order of attack (stability first)
1. ✅ **A4 / A6** (connect flow + config) and ✅ **C1 / C4** (correctness/crash) — DONE 2026-06-01,
   the safe, compile-verified wins.
2. **A3** (decouple ticking / heartbeat) → unblocks **A1** (re-enable server timeout) → **A2**
   (client reconnect + cleanup). **This trio is the remaining priority** and is the risky part:
   A3 changes the network-tick threading (currently driven by a Papyrus 0-sec timer that stalls
   during loads/menus), so it needs careful implementation **and runtime validation** with two
   clients before A1's timeout re-enable is safe.
3. **A5** — harden object lifetime (`delete this` in server event handlers).
4. Then feature work: **B1** (NPC sync) and **B2** (buildings) for real shared gameplay.

---

## On "shared campaign / progression" (your question)
See `docs/SHARED_PROGRESSION.md` for the full answer. Short version: **partial yes, full no** —
the current "clone the player" design replicates *appearance + position + a few stats*, not quest
state, world state, or saves. True shared campaign progression is a large new subsystem, not a
tweak. Details and a phased plan are in that doc.
