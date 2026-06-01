#pragma once

#include "Character.h"

namespace f4mp
{
	class NPC : public Character
	{
	public:
		NPC();

		void OnEntityCreate(librg_event* event) override;
		void OnEntityUpdate(librg_event* event) override;

		void OnClientUpdate(librg_event* event) override;

		// True on the one client that controls (owns) this NPC. librg only ever
		// fires OnClientUpdate for entities we control, so that's where it's set.
		// Used to decide who routes melee/ranged damage (the owner applies its
		// own hits locally; non-owners route theirs to the owner).
		bool IsMine() const;

	private:
		UInt32 formID, ownerEntityID;

		// Set once when this client mirrors the authority's lethal health, so we
		// only issue the kill a single time even though updates keep arriving.
		bool killed;

		bool mine;
	};
}