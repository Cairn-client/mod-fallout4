#include "NPC.h"
#include "f4mp.h"

f4mp::NPC::NPC() : formID(0), ownerEntityID((UInt32)-1), killed(false), mine(false)
{
	// Health is streamed as a [0, 1] fraction, just like Player. Until the
	// authority feeds a real value (F4MPQuest health poll) it stays "full".
	SetNumber("health", 1.f);
}

void f4mp::NPC::OnEntityCreate(librg_event* event)
{
	Character::OnEntityCreate(event);

	UInt32 entityID = GetNetworkEntity()->id;

	formID = librg_data_ri32(event->data);
	ownerEntityID = librg_data_ri32(event->data);

	F4MP& f4mp = F4MP::GetInstance();

	f4mp.entityIDs[formID] = entityID;

	_MESSAGE("OnSpawnEntity: %u(%x)", entityID, formID);

	TESObjectREFR* gameEntity = DYNAMIC_CAST(LookupFormByID(formID), TESForm, TESObjectREFR);
	if (!gameEntity)
	{
		return;
	}

	SetRef(gameEntity);

	printf("%u %x\n", entityID, formID);
}

void f4mp::NPC::OnEntityUpdate(librg_event* event)
{
	Character::OnEntityUpdate(event);

	// Read the authority's health fraction. Character::OnEntityUpdate always
	// consumes exactly the transforms + syncTime that OnClientUpdate wrote
	// (including on its early-return paths), so this stays byte-aligned.
	Float32 health = librg_data_rf32(event->data);
	SetNumber("health", health);

	// Mirror the authority's kill: when the shared enemy dies on their machine,
	// drop our local copy too so we "fight the same enemy" to the same end.
	if (!killed && health <= 0.f)
	{
		killed = true;

		TESObjectREFR* ref = GetRef();
		if (ref)
		{
			VMArray<VMVariable> args;
			CallFunctionNoWait(ref, "Kill", args);
		}
	}
}

void f4mp::NPC::OnClientUpdate(librg_event* event)
{
	Character::OnClientUpdate(event);

	// Only the controlling (authority) client gets OnClientUpdate for this NPC,
	// so reaching here proves we own it, and this is where the enemy's
	// authoritative health leaves the machine. The value is fed in by
	// F4MPQuest's health poll via SetEntVarNum.
	mine = true;

	librg_data_wf32(event->data, GetNumber("health"));
}

bool f4mp::NPC::IsMine() const
{
	return mine;
}
