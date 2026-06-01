# Steamworks SDK drop-in (required for the `steam-net` transport)

The Steamworks SDK is **not committed** to this repo (it's gated behind a Steam
login and has its own redistribution terms — like the F4SE source tree, you
supply it per machine). Everything under this folder except this README is
gitignored.

## How to get it
1. Sign in at <https://partner.steamgames.com/downloads/list> with a Steam account
   and accept the **Steamworks SDK Access Agreement** (free).
2. Download **`steamworks_sdk_<version>.zip`** (any recent version is fine; the
   networking APIs we use have been stable for years).
3. Unzip it and copy the contents of its `sdk/` folder so that this layout exists:

```
thirdparty/steamworks/
├─ README.md                  (this file — the only committed file)
├─ public/
│  └─ steam/                  (headers: steam_api.h, isteamnetworkingsockets.h,
│                               isteamnetworkingmessages.h, steam_gameserver.h, ...)
└─ redistributable_bin/
   └─ win64/
      ├─ steam_api64.dll      (already shipped with Fallout 4; here for tools/tests)
      └─ steam_api64.lib      (import lib we link against)
```

That mirrors the SDK's own `sdk/public/` and `sdk/redistributable_bin/` folders —
just copy those two trees in.

## How the build uses it
- The client plugin (`f4mp/`) links `redistributable_bin/win64/steam_api64.lib` and
  includes from `public/`. Fallout 4 already ships `steam_api64.dll` in the game
  root, so the runtime is present in-game — no extra DLL to deploy for the client.
- Steam code is compiled behind a build flag (planned: `F4MP_STEAM`) so the default
  enet/UDP build is unaffected until the Steam transport is switched on.

## Verifying
Once dropped in, `public/steam/isteamnetworkingmessages.h` should exist. The Phase 0
spike (see `docs/STEAM_NETWORKING.md` §7) is the first thing that will consume it.
