#pragma once

// ───────────────────────────────────────────────────────────────────────────
// Privately-named Steam API loader  (steam-net branch)
//
// Fallout 4 1.10.163 ships an ANCIENT steam_api64.dll whose old exports the game
// hard-depends on (SteamUser, etc.). The modern Steam Networking API we need
// (SteamInternal_ContextInit + ISteamNetworkingMessages/relay) lives only in a
// NEWER steam_api64.dll. They are the same filename in one process, so we cannot
// replace the game's copy without breaking its boot (that bug bricked installs).
//
// Instead, the Steam build links NOTHING against steam_api64.lib. We compile the
// SDK headers with STEAM_API_NODLL (so their S_API symbols become plain extern "C"
// that WE define), and at runtime we LoadLibrary a privately-named copy of the SDK
// 1.64 redistributable — `steam_api64_f4mp.dll`, shipped beside f4mp.dll — and
// forward the handful of flat Steamworks functions to it. The game's own
// steam_api64.dll is never touched.
//
// All of this is compiled only when F4MP_STEAM is defined (build with
// /p:F4MPSteam=true). With the flag off, this file expands to nothing.
// ───────────────────────────────────────────────────────────────────────────

#ifdef F4MP_STEAM

namespace f4mp
{
	namespace steamapi
	{
		// Load steam_api64_f4mp.dll from the plugin's own folder and initialise our
		// private Steam API context (SteamAPI_InitFlat). Idempotent; returns true
		// once Steam is initialised and the interface accessors are usable.
		bool EnsureInit();

		// Shut our private context down (does NOT affect the game's Steam context).
		void Shutdown();
	}
}

#endif // F4MP_STEAM
