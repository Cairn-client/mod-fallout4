#include "NPC.h"

f4mp::NPC::NPC(u32 formID, u32 ownerEntityID) : formID(formID), ownerEntityID(ownerEntityID), health(1.f)
{
}

void f4mp::NPC::OnEntityCreate(librg_event* event)
{
	Character::OnEntityCreate(event);

	librg_data_wi32(event->data, formID);
	librg_data_wi32(event->data, ownerEntityID);
}

void f4mp::NPC::OnEntityUpdate(librg_event* event)
{
	Character::OnEntityUpdate(event);

	librg_data_wf32(event->data, health);
}

void f4mp::NPC::OnClientUpdate(librg_event* event)
{
	Character::OnClientUpdate(event);

	health = librg_data_rf32(event->data);
}
