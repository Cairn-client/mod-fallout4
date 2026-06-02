#pragma once

// ───────────────────────────────────────────────────────────────────────────
// Phase 0 Steam Networking spike  (steam-net branch — docs/STEAM_NETWORKING.md §7)
//
// Self-contained proof that, from inside the Fallout 4 F4SE plugin (Steam is
// already initialised by the game), we can:
//   1. create / find a Steam lobby via ISteamMatchmaking, and
//   2. round-trip a "hello" datagram between two clients over
//      ISteamNetworkingMessages (NAT-punched / Steam-Datagram-Relayed).
//
// There is deliberately NO librg / enet involvement here — this only validates
// that the Steamworks SDK links and that the relay works under Fallout 4's Steam
// App-ID context, before the real transport shim (Phase 1) is attempted.
//
// The whole module compiles only when F4MP_STEAM is defined (enable the build
// with `msbuild f4mp\f4mp.vcxproj /p:F4MPSteam=true ...`). With the flag off,
// this header and SteamSpike.cpp expand to nothing, so the normal enet/UDP build
// is completely unaffected.
// ───────────────────────────────────────────────────────────────────────────

#ifdef F4MP_STEAM

#include "steam/steam_api.h"
#include "steam/isteammatchmaking.h"
#include "steam/isteamnetworkingmessages.h"

namespace f4mp
{
	// Process-lifetime singleton so its Steam callbacks stay registered.
	class SteamSpike
	{
	public:
		static SteamSpike& Get();

		// Create a friends-only lobby and wait for joiners (host side).
		bool Host();

		// Find the first F4MP-tagged lobby and join it (joiner side, spike-grade
		// discovery via RequestLobbyList + string filter).
		bool Join();

		// Pump Steam callbacks and drain inbound hello/ack messages. Call this
		// regularly while the spike is active (e.g. from a Papyrus timer).
		void Poll();

		bool IsActive() const { return active; }

	private:
		SteamSpike();
		SteamSpike(const SteamSpike&) = delete;
		SteamSpike& operator=(const SteamSpike&) = delete;

		void GreetLobbyMembers();        // hello to every other current member
		void SendText(CSteamID peer, const char* text);

		// --- async API-call results ---
		void OnLobbyCreated(LobbyCreated_t* result, bool ioFailure);
		CCallResult<SteamSpike, LobbyCreated_t> lobbyCreatedCall;

		void OnLobbyMatchList(LobbyMatchList_t* result, bool ioFailure);
		CCallResult<SteamSpike, LobbyMatchList_t> lobbyMatchListCall;

		// --- registered callbacks ---
		void OnLobbyEntered(LobbyEnter_t* p);
		CCallback<SteamSpike, LobbyEnter_t> lobbyEnteredCb;

		void OnLobbyChatUpdate(LobbyChatUpdate_t* p);
		CCallback<SteamSpike, LobbyChatUpdate_t> lobbyChatUpdateCb;

		void OnSessionRequest(SteamNetworkingMessagesSessionRequest_t* p);
		CCallback<SteamSpike, SteamNetworkingMessagesSessionRequest_t> sessionRequestCb;

		void OnSessionFailed(SteamNetworkingMessagesSessionFailed_t* p);
		CCallback<SteamSpike, SteamNetworkingMessagesSessionFailed_t> sessionFailedCb;

		static const char* kLobbyTagKey;     // lobby-data key used to tag/find F4MP lobbies
		static const char* kLobbyTagValue;
		static const int   kChannel = 0;     // ISteamNetworkingMessages channel for the spike

		CSteamID lobby;   // current lobby (created or joined)
		bool isHost;
		bool active;
	};
}

#endif // F4MP_STEAM
