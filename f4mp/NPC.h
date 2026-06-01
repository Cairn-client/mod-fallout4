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

	private:
		UInt32 formID, ownerEntityID;

		// Set once when this client mirrors the authority's lethal health, so we
		// only issue the kill a single time even though updates keep arriving.
		bool killed;
	};
}