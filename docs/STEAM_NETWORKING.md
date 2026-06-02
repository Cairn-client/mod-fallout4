# F4MP over Steam Networking — design & plan

**Branch:** `steam-net`
**Goal:** let players connect without port-forwarding/IP sharing by moving the
transport from raw UDP (enet) to **Steam Networking** (`ISteamNetworkingSockets` /
`ISteamNetworkingMessages` + Steam Datagram Relay), with friend-invite/lobby discovery.

> This is a design document, not finished work. Nothing here changes runtime
> behaviour yet. It exists so the transport rewrite can be done in reviewable steps.

---

## 1. Why

Current internet play needs the host to port-forward **UDP 7779** and share their
public IP, and it dies behind CGNAT (see `docs/TODO.md` and the README). Steam
Networking gives, for free, to any Steam-initialised app:

- **NAT punch-through + Valve relay fallback** — no router config, works behind CGNAT.
- **Connect by SteamID + lobby/friend invites** — no IP typing.
- **IP privacy** — peers never see each other's address.

It does **not** fix link stability (loading-screen stalls, no reconnect, disabled
timeouts — `TODO.md` A1–A3). Those must be fixed regardless of transport; ordering
matters (see §8).

---

## 2. Current architecture (what we're changing)

Two layers, and the code is coupled to **both**:

- **librg** (`thirdparty/librg`) — replication: entity create/update/remove,
  visibility/streaming, and the message channels in `f4mp/common.h`
  (`MessageType::Hit/FireWeapon/SpawnEntity/SyncEntity/...`).
- **enet** — the actual UDP transport under librg.

Coupling points to be aware of:
- `f4mp_server/Server.h` — `librg_network_start(&ctx, librg_address{port, host})`
  (wraps `enet_host_create`), and **direct enet calls** like
  `enet_peer_timeout(...)` (`Server.h:56`).
- `f4mp/f4mp.cpp` — client `librg_init` (`LIBRG_MODE_CLIENT`), `librg_network_start`
  to dial `host:port`; messages via `librg_message_send_all/except/to`.
- `f4mp_server/main.cpp` — standalone process, reads `server_config.txt` (`host port`,
  default `7779`), `while(true){ Tick(); }`.
- `f4mp/scripts/F4MPQuest.psc` — `Connect("", 7779)` on F1; host address comes from
  `Documents\My Games\Fallout4\F4MP\config.txt`.

There is **no transport abstraction** in this librg version, so Steam networking means
replacing or bridging enet while keeping librg's replication intact.

---

## 3. Target architecture

Two decisions:

### 3a. Hosting model — pivot to a listen server (host is a player)
The standalone `f4mp_server.exe` is a **non-Steam process**; using Steam sockets there
needs the Steam **Game Server API** (`SteamGameServer_Init`) under an App ID, which is
awkward and a ToS gray area under Bethesda's App ID (377160). The Steam-native model is:

- **One player's game hosts** (a *listen server*). That process already has Steam
  initialised by Fallout 4, so `SteamNetworkingSockets()` is available immediately.
- Others **join by SteamID via a lobby/invite**.

Plan: keep the existing dedicated server + IP path as a **fallback transport** (LAN /
power users), and add Steam P2P as the default. Transport is selected at startup.

### 3b. Transport — bridge enet datagrams over Steam (least-invasive)
Keep librg + enet's reliability/sequencing; replace only enet's **socket I/O** so each
enet packet is carried 1:1 over `ISteamNetworkingMessages` (unreliable channel; enet
still does its own reliability). Each enet "peer" maps to a remote **SteamID identity**.

```
librg (unchanged)
  └─ enet (reliability/sequencing/fragmentation kept)
       └─ [NEW] socket shim: send/recv datagrams via ISteamNetworkingMessages
            └─ Steam Datagram Relay (NAT traversal, relay)
```

Alternative considered: rewrite librg's network layer onto `ISteamNetworkingSockets`
connections directly (cleaner, much more code). Deferred — the shim is the smaller,
reviewable first move.

---

## 4. Steamworks SDK integration

- Download the **Steamworks SDK** (free; needs a Steam account + SDK access agreement)
  and vendor it under `thirdparty/steamworks/` (headers + `lib/win64`). Add it to
  `.gitignore` if redistribution is a concern, or commit per its terms.
- `Fallout4.exe` already ships **`steam_api64.dll`** in the game root, so the client
  plugin has the runtime; we just link the import lib and include `steam/steam_api.h`.
- **Client (plugin):** the game already called `SteamAPI_Init`, so we can call
  `SteamNetworkingSockets()` / `SteamMatchmaking()` directly. Add a `steam_appid.txt`
  (377160) only for standalone test harnesses, not for the in-game plugin.
- **Server:** only relevant if we keep a standalone host; for the listen-server model
  the host is the game process and needs nothing extra.

---

## 5. Peer discovery / handshake (new code)

With IPs gone, replace "type host:port" with:

1. **Host** creates a Steam **lobby** (`ISteamMatchmaking::CreateLobby`), stores a
   "F4MP" tag + protocol version in lobby data, and opens an
   `ISteamNetworkingSockets` listen socket (or starts accepting
   `ISteamNetworkingMessages` from lobby members).
2. **Joiner** finds the lobby (friend invite / `RequestLobbyList` filtered by tag /
   join-from-friends-list), reads the host's `SteamID`, and connects by identity.
3. On connect, run the existing F4MP connect flow (appearance/worn-items handshake in
   `Player::OnConnectRequest`) over the Steam transport unchanged.

Papyrus impact: `F4MPQuest.Connect` gains a "host lobby" vs "join" entry point; the
F1 keybind can host, a new key (or a MCM/holotape later) joins/invites.

---

## 6. Versioning / compatibility

- Both peers must run the **same protocol** (the `MessageType` enum + struct layouts in
  `common.h`) — already true today. Add a small **protocol-version handshake** so a
  mismatched build refuses cleanly instead of desyncing.
- Both still need **Fallout 4 1.10.163** and **identical load orders** (shared-entity
  formIDs must match) — unchanged by transport.

---

## 7. Phased task list

| Phase | Work | Risk |
|------|------|------|
| **0. Spike** | Vendor Steamworks SDK; from the plugin call `SteamNetworkingSockets()`, create a lobby, and round-trip a "hello" between two clients via `ISteamNetworkingMessages`. No librg involvement. | Low — proves the SDK + App-ID context work in-game. |
| **1. Transport shim** | Implement the enet-datagram⇄Steam bridge; add a build flag / runtime switch `transport = enet | steam`. Keep enet path default until proven. | High — MTU/fragmentation, per-peer identity map, reliability semantics. |
| **2. Discovery** | Lobby create/find/invite; SteamID handshake; wire into `F4MPQuest.Connect`. | Medium. |
| **3. Listen-server** | Run the server logic inside the host's game process; collapse `f4mp_server` into an in-process host (keep standalone exe for the enet fallback). | Medium. |
| **4. Hardening** | Protocol-version handshake, disconnect/relay-drop handling, reconnect (ties into TODO A2). | Medium. |

---

## 8. Sequencing with stability (read this)

Steam relay fixes **reachability**, not the link **dropping on loading screens**
(`TODO.md` A3 — `librg_tick` driven by a Papyrus 0-second timer that stalls during
loads/menus; plus A1 disabled timeouts, A2 no reconnect). A relayed connection that
still half-opens on every load is no better. **Recommended order:** A1–A3 stability →
Phase 0 spike → transport shim. Both efforts live on this branch.

---

## 9. Open questions / risks

- **ToS gray area:** custom P2P/relay under Bethesda's App ID. Works in practice and has
  precedent in other Bethesda-game co-op mods, but isn't officially sanctioned.
- **SDR relay availability** under a third-party app context — expected to work for P2P;
  confirm in the Phase 0 spike.
- **Reliability mapping:** enet expects to own (un)reliable channels; carrying its
  datagrams over Steam *unreliable* messages should preserve semantics, but fragmentation
  and ordering need validation.
- **Two copies of the game** still required; **VAC** still N/A (FO4 isn't VAC-secured).

---

## 10. Status

- [x] Branch `steam-net` created.
- [x] This design doc.
- [x] `master` merged into `steam-net` (stability fixes A2/A5/A6/C1/C4 now underneath the Steam work — see §8 ordering).
- [~] **Phase 0 spike — code complete, compile+link verified; runtime round-trip pending.**
  - Steamworks SDK 1.64 wired into `f4mp/f4mp.vcxproj` behind `F4MPSteam` (default **OFF**;
    enable with `msbuild f4mp\f4mp.vcxproj /p:Configuration=Debug /p:Platform=x64 /p:SolutionDir=<repo>\ /p:F4MPSteam=true`).
    Vendored SDK path `steamworks_sdk_164\sdk` (override with `/p:SteamworksDir=...`).
  - `f4mp/SteamSpike.{h,cpp}` — singleton: `Host()` (CreateLobby, friends-only), `Join()`
    (RequestLobbyList tag filter → JoinLobby), `Poll()` (`SteamAPI_RunCallbacks` + drain
    `ISteamNetworkingMessages`). Greets lobby members with "hello", replies "ack" — proves a
    bidirectional round-trip. Accepts inbound sessions in `OnSessionRequest`. All `#ifdef F4MP_STEAM`.
  - Papyrus natives `F4MP.SteamHost()`, `F4MP.SteamJoin()`, `F4MP.SteamPoll()` registered (also
    `#ifdef`-guarded) AND declared in `f4mp/scripts/F4MP.psc` (verified compiles via the CK).
  - **Verified:** default `x64 Debug` build green (flag off, normal enet build unchanged); `/p:F4MPSteam=true`
    build compiles + links `steam_api64.lib` → `f4mp.dll`.
  - **Runtime test (needs two FO4 1.10.163 clients, the user's machine):** build with `/p:F4MPSteam=true`
    and deploy the resulting `f4mp.dll` + recompiled `F4MP.pex`. Call `SteamHost()` on one client +
    `SteamJoin()` on a Steam friend's client, and `SteamPoll()` on a repeating timer on both. Watch the
    plugin console for `RECV "hello"` / `RECV "ack"` to confirm the relay works under FO4's App-ID.
    (The `SteamHost`/`SteamJoin`/`SteamPoll` natives are already declared in `F4MP.psc`.)
- [ ] Phases 1–4.
