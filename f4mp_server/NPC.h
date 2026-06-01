#pragma once

#include "Character.h"

namespace f4mp
{
	class NPC : public Character
	{
	public:
		NPC(u32 formID = 0, u32 ownerEntityID = (u32)-1);

		void OnEntityCreate(librg_event* event) override;

		void OnEntityUpdate(librg_event* event) override;
		void OnClientUpdate(librg_event* event) override;

	private:
		u32 formID;

		u32 ownerEntityID;

		// Relayed from the owning client to everyone else (mirrors Player::health),
		// so a shared enemy's damage/death propagates. [0, 1] fraction.
		float health;
	};
}