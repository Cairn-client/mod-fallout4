#include "SteamSpike.h"

#ifdef F4MP_STEAM

#include <cstdio>

namespace f4mp
{
	const char* SteamSpike::kLobbyTagKey   = "f4mp";
	const char* SteamSpike::kLobbyTagValue = "spike";

	SteamSpike& SteamSpike::Get()
	{
		static SteamSpike instance;
		return instance;
	}

	SteamSpike::SteamSpike()
		: lobbyEnteredCb(this, &SteamSpike::OnLobbyEntered)
		, lobbyChatUpdateCb(this, &SteamSpike::OnLobbyChatUpdate)
		, sessionRequestCb(this, &SteamSpike::OnSessionRequest)
		, sessionFailedCb(this, &SteamSpike::OnSessionFailed)
		, isHost(false)
		, active(false)
	{
	}

	bool SteamSpike::Host()
	{
		if (!SteamMatchmaking())
		{
			printf("[steam-spike] SteamMatchmaking() unavailable — is Steam running?\n");
			return false;
		}

		printf("[steam-spike] creating friends-only lobby...\n");
		SteamAPICall_t call = SteamMatchmaking()->CreateLobby(k_ELobbyTypeFriendsOnly, 4);
		lobbyCreatedCall.Set(call, this, &SteamSpike::OnLobbyCreated);
		isHost = true;
		active = true;
		return true;
	}

	bool SteamSpike::Join()
	{
		if (!SteamMatchmaking())
		{
			printf("[steam-spike] SteamMatchmaking() unavailable — is Steam running?\n");
			return false;
		}

		printf("[steam-spike] searching for an F4MP lobby...\n");
		SteamMatchmaking()->AddRequestLobbyListStringFilter(kLobbyTagKey, kLobbyTagValue, k_ELobbyComparisonEqual);
		SteamAPICall_t call = SteamMatchmaking()->RequestLobbyList();
		lobbyMatchListCall.Set(call, this, &SteamSpike::OnLobbyMatchList);
		isHost = false;
		active = true;
		return true;
	}

	void SteamSpike::OnLobbyCreated(LobbyCreated_t* result, bool ioFailure)
	{
		if (ioFailure || !result || result->m_eResult != k_EResultOK)
		{
			printf("[steam-spike] lobby creation FAILED (io=%d res=%d)\n",
				ioFailure ? 1 : 0, result ? result->m_eResult : -1);
			active = false;
			return;
		}

		lobby = CSteamID(result->m_ulSteamIDLobby);
		SteamMatchmaking()->SetLobbyData(lobby, kLobbyTagKey, kLobbyTagValue);
		printf("[steam-spike] lobby created: %llu — invite a friend or have them Join().\n",
			lobby.ConvertToUint64());
	}

	void SteamSpike::OnLobbyMatchList(LobbyMatchList_t* result, bool ioFailure)
	{
		if (ioFailure || !result || result->m_nLobbiesMatching == 0)
		{
			printf("[steam-spike] no F4MP lobby found. Have a friend Host() first, then Join().\n");
			active = false;
			return;
		}

		CSteamID found = SteamMatchmaking()->GetLobbyByIndex(0);
		printf("[steam-spike] found %u lobby(ies); joining %llu...\n",
			result->m_nLobbiesMatching, found.ConvertToUint64());
		SteamMatchmaking()->JoinLobby(found); // -> OnLobbyEntered
	}

	void SteamSpike::OnLobbyEntered(LobbyEnter_t* p)
	{
		if (!p)
		{
			return;
		}

		lobby = CSteamID(p->m_ulSteamIDLobby);
		if (p->m_EChatRoomEnterResponse != k_EChatRoomEnterResponseSuccess)
		{
			printf("[steam-spike] failed to enter lobby (response=%u)\n", p->m_EChatRoomEnterResponse);
			return;
		}

		printf("[steam-spike] entered lobby %llu — greeting %d member(s).\n",
			lobby.ConvertToUint64(), SteamMatchmaking()->GetNumLobbyMembers(lobby));
		GreetLobbyMembers();
	}

	void SteamSpike::OnLobbyChatUpdate(LobbyChatUpdate_t* p)
	{
		if (!p || (p->m_rgfChatMemberStateChange & k_EChatMemberStateChangeEntered) == 0)
		{
			return;
		}

		CSteamID joiner(p->m_ulSteamIDUserChanged);
		if (joiner != SteamUser()->GetSteamID())
		{
			printf("[steam-spike] member %llu joined — saying hello.\n", joiner.ConvertToUint64());
			SendText(joiner, "hello from F4MP spike");
		}
	}

	void SteamSpike::GreetLobbyMembers()
	{
		const CSteamID me = SteamUser()->GetSteamID();
		const int count = SteamMatchmaking()->GetNumLobbyMembers(lobby);
		for (int i = 0; i < count; ++i)
		{
			CSteamID member = SteamMatchmaking()->GetLobbyMemberByIndex(lobby, i);
			if (member != me)
			{
				SendText(member, "hello from F4MP spike");
			}
		}
	}

	void SteamSpike::SendText(CSteamID peer, const char* text)
	{
		if (!SteamNetworkingMessages())
		{
			printf("[steam-spike] SteamNetworkingMessages() unavailable.\n");
			return;
		}

		SteamNetworkingIdentity id;
		id.SetSteamID(peer);

		const uint32 len = (uint32)(strlen(text) + 1); // include NUL for easy printing
		EResult r = SteamNetworkingMessages()->SendMessageToUser(
			id, text, len, k_nSteamNetworkingSend_Reliable, kChannel);
		printf("[steam-spike] sent \"%s\" to %llu (result=%d)\n", text, peer.ConvertToUint64(), r);
	}

	void SteamSpike::OnSessionRequest(SteamNetworkingMessagesSessionRequest_t* p)
	{
		if (!p)
		{
			return;
		}

		// Spike: accept any incoming session (real code would verify lobby membership).
		SteamNetworkingMessages()->AcceptSessionWithUser(p->m_identityRemote);
		printf("[steam-spike] accepted session from %llu\n", p->m_identityRemote.GetSteamID64());
	}

	void SteamSpike::OnSessionFailed(SteamNetworkingMessagesSessionFailed_t* p)
	{
		if (!p)
		{
			return;
		}
		printf("[steam-spike] session FAILED with %llu (endReason=%d)\n",
			p->m_info.m_identityRemote.GetSteamID64(), p->m_info.m_eEndReason);
	}

	void SteamSpike::Poll()
	{
		if (!active)
		{
			return;
		}

		SteamAPI_RunCallbacks();

		if (!SteamNetworkingMessages())
		{
			return;
		}

		SteamNetworkingMessage_t* msgs[16];
		int got = SteamNetworkingMessages()->ReceiveMessagesOnChannel(kChannel, msgs, 16);
		for (int i = 0; i < got; ++i)
		{
			SteamNetworkingMessage_t* m = msgs[i];
			const char* text = (const char*)m->m_pData;
			const uint64 from = m->m_identityPeer.GetSteamID64();
			printf("[steam-spike] RECV \"%.*s\" from %llu\n", (int)m->m_cbSize, text, from);

			// Prove the round-trip: reply to a "hello" once with an "ack" (acks are
			// not re-acked, so this terminates).
			if (m->m_cbSize >= 5 && strncmp(text, "hello", 5) == 0)
			{
				SendText(m->m_identityPeer.GetSteamID(), "ack from F4MP spike");
			}

			m->Release();
		}
	}
}

#endif // F4MP_STEAM
