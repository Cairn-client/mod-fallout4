Scriptname F4MPQuest extends Quest

int tickTimerID = 10
int updateTimerID = 20
int npcSyncTimerID = 30

Actor Property playerRef Auto

ActorBase Property f4mpPlayerBase Auto

ActorValue Property healthAV Auto

Spell Property entitySyncSpell Auto

VoiceType Property malePlayerVoiceType Auto
VoiceType Property femalePlayerVoiceType Auto

int[] playerIDs
F4MPPlayer[] players

bool topicInfosRegistered = false

Event OnInit()
	RegisterForKey(112)
EndEvent

Function OnEntityCreate(int entityID, Form[] itemsToWear)
	Debug.Notification(entityID + " has entered the world.")

	If entityID != F4MP.GetPlayerEntityID()
		Actor player = Game.GetPlayer()
		F4MPPlayer entity = player.PlaceActorAtMe(f4mpPlayerBase) as F4MPPlayer
		F4MP.SetEntityRef(entityID, entity)
		entity.entityID = entityID

		If f4mpPlayerBase.GetSex() == 0
			entity.SetOverrideVoiceType(malePlayerVoiceType)
		Else
			entity.SetOverrideVoiceType(femalePlayerVoiceType)
		EndIf
		
		entity.itemsToWear = itemsToWear
		; SetWornItems(entity, itemsToWear)
	
		playerIDs.Add(entityID)
		players.Add(entity)
	EndIf
EndFunction

Function OnEntityRemove(int entityID)
	int index = playerIDs.Find(entityID)
	If index < 0
		return
	EndIf
	
	players[index].Delete()
	playerIDs.Remove(index)
	players.Remove(index)
EndFunction

Function OnPlayerHit(float damage)
	Game.GetPlayer().DamageValue(healthAV, damage)
EndFunction

Function RegisterTopicInfos(Form[] targets)
	int i = 0
	While i < targets.length
		RegisterForRemoteEvent(targets[i] as TopicInfo, "OnBegin")
		i += 1
	EndWhile
EndFunction

Function OnTopicInfoRegister(Form[] targets)
	If topicInfosRegistered
		return
	EndIf

	topicInfosRegistered = true
	
	RegisterTopicInfos(targets)
	
	Debug.Trace(targets.length + " topic infos have registered.")
	Debug.Notification(targets.length + " topic infos have registered.")
EndFunction

Event TopicInfo.OnBegin(TopicInfo akSender, ObjectReference akSpeakerRef, bool abHasBeenSaid)
	;Debug.Trace("Topic info " + akSender + " is being said by " + akSpeakerRef.GetDisplayName())
	;Debug.Notification("Topic info " + akSender + " is being said by " + akSpeakerRef)
	F4MP.TopicInfoBegin(akSender, akSpeakerRef)
EndEvent

;Function OnFireWeapon(int entityID)
;	int index = playerIDs.Find(entityID)
;	If index < 0
;		return
;	EndIf
;	
;	players[index].FireWeapon()
;EndFunction

;Function OnSpawnEntity(int formID)
;	ObjectReference ref = Game.GetForm(formID) as ObjectReference
;	If ref == None
;		return
;	EndIf
;
;	Actor actorRef = ref as Actor
;	If actorRef != None
;		actorRef.AddSpell(entitySyncSpell)
;	EndIf
;EndFunction

Function SetWornItems(Actor dest, Form[] wornItems)
	int i = 0
	While i < wornItems.length
		Debug.Trace(i + ": " + wornItems[i])
		dest.EquipItem(wornItems[i])
		i += 1
	EndWhile
EndFunction

; TODO: mutiple timers
bool Function Connect(string address, int port)
	Actor client = Game.GetPlayer()
	ActorBase clientActorBase = client.GetActorBase()
	
	StartTimer(0, tickTimerID)
	StartTimer(0, updateTimerID)
	StartTimer(0, npcSyncTimerID)

	return F4MP.Connect(client, clientActorBase, address, port)
EndFunction

Sound Property mySound Auto
Topic Property myTopic Auto

Event OnKeyDown(int keyCode)
	If keyCode == 112
		RegisterForExternalEvent("OnTopicInfoRegister", "OnTopicInfoRegister")
		RegisterForExternalEvent("OnAdditionalTopicInfoRegister", "RegisterTopicInfos")
		
		Connect("", 7779)

		playerIDs = new int[0]
		players = new F4MPPlayer[0]		

		;Actor player = Game.GetPlayer()
		;F4MPPlayer entity = player.PlaceActorAtMe(f4mpPlayerBase) as F4MPPlayer
		
		Actor client = Game.GetPlayer()
		RegisterForAnimationEvent(client, "JumpUp")
		RegisterForAnimationEvent(client, "weaponFire")
		; RegisterForAnimationEvent(client, "JumpFall")
		; RegisterForAnimationEvent(client, "JumpDown")

		; RegisterForExternalEvent("OnCopyWornItems", "OnCopyWornItems")

		RegisterForExternalEvent("OnEntityCreate", "OnEntityCreate")
		RegisterForExternalEvent("OnEntityRemove", "OnEntityRemove")

		RegisterForExternalEvent("OnPlayerHit", "OnPlayerHit")
		RegisterForExternalEvent("OnNPCHit", "OnNPCHit")

		RegisterForKey(113)
		RegisterForKey(114)
	ElseIf keyCode == 113
		F4MP.SetClient(1 - F4MP.GetClientInstanceID())
	ElseIf keyCode == 114
		mySound.Play(Game.GetPlayer())
		;Debug.Notification(myTopic)
		;Game.GetPlayer().Say(myTopic)
	EndIf
EndEvent

Form Property targetForm Auto
Actor Property chosenActor Auto
ObjectReference Property targetRef Auto

Event OnAnimationEvent(ObjectReference akSource, string asEventName)
	If !F4MP.IsConnected()
		return
	EndIf

	int playerEntityID = F4MP.GetPlayerEntityID()
	If F4MP.IsEntityValid(playerEntityID)
		If asEventName == "JumpUp"
			F4MP.SetEntVarAnim(playerEntityID, "JumpUp")
		; ElseIf asEventName == "JumpFall"
		; 	F4MP.SetEntVarAnim(playerEntityID, "JumpFall")
		; ElseIf asEventName == "JumpDown"
		; 	F4MP.SetEntVarAnim(playerEntityID, "JumpLand")
		ElseIf asEventName == "weaponFire"
			; F4MP.SetEntVarAnim(playerEntityID, "FireWeapon")
			F4MP.PlayerFireWeapon()
		EndIf
	EndIf
EndEvent

Event OnTimer(int aiTimerID)
	If aiTimerID == tickTimerID
		F4MP.Tick()
		StartTimer(0, tickTimerID)
	ElseIf aiTimerID == updateTimerID
		;; ***************************************
		;If chosenActor != None
		;	chosenActor.PathToReference(targetRef, 1.0)
		;EndIf
		;
		;; ***************************************

		int playerEntityID = F4MP.GetPlayerEntityID()
		If F4MP.IsEntityValid(playerEntityID)
			F4MP.SetEntVarNum(playerEntityID, "health", playerRef.GetValuePercentage(healthAV))
		EndIf
		StartTimer(0, updateTimerID)
	ElseIf aiTimerID == npcSyncTimerID
		; Feed every shared enemy's current health fraction into its F4MP entity.
		; Only the client that owns (controls) a given NPC actually streams this
		; value out; on everyone else SetEntVarNum is a harmless local write, and
		; the receiving side kills its copy once the owner's value reaches 0.
		SyncSharedNPCHealth()
		StartTimer(0, npcSyncTimerID)
	EndIf
EndEvent

Function SyncSharedNPCHealth()
	If !F4MP.IsConnected()
		return
	EndIf

	Cell currentCell = playerRef.GetParentCell()
	If currentCell == None
		return
	EndIf

	ObjectReference[] refs = F4MP.GetRefsInCell(currentCell)
	int i = 0
	While i < refs.length
		Actor enemy = refs[i] as Actor
		If enemy != None && enemy != playerRef
			int entityID = F4MP.GetEntityID(refs[i])
			If F4MP.IsEntityValid(entityID)
				F4MP.SetEntVarNum(entityID, "health", enemy.GetValuePercentage(healthAV))

				; Listen for hits on this shared enemy so we can route our local
				; player's damage to whoever owns it (filtered in Event OnHit).
				RegisterForHitEvent(enemy)
			EndIf
		EndIf
		i += 1
	EndWhile
EndFunction

; Fires when an actor we registered (a shared enemy) is hit by the local player.
; If we don't own that enemy, send the damage to its owner; the owner applies it
; to the authoritative actor and the resulting health streams back to everyone.
; (If we DO own it, our local hit already counts -- routing would double it.)
Event OnHit(ObjectReference akTarget, ObjectReference akAggressor, Form akSource, Projectile akProjectile, bool abPowerAttack, bool abSneakAttack, bool abBashAttack, bool abHitBlocked, string apMaterial)
	If akAggressor != playerRef
		return
	EndIf

	int entityID = F4MP.GetEntityID(akTarget)
	If !F4MP.IsEntityValid(entityID) || F4MP.IsEntityMine(entityID)
		return
	EndIf

	Weapon sourceWeapon = akSource as Weapon
	If sourceWeapon
		InstanceData:Owner owner = sourceWeapon.GetInstanceOwner()
		float damage = InstanceData.GetAttackDamage(owner)
		F4MP.PlayerHit(F4MP.GetPlayerEntityID(), entityID, damage)
	EndIf
EndEvent

; Owner-side: apply networked damage from a remote player's hit to the real
; shared enemy. DamageValue on Health to 0 kills it; the death then propagates
; through the NPC health sync.
Function OnNPCHit(int formID, float damage)
	Actor enemy = Game.GetForm(formID) as Actor
	If enemy != None
		enemy.DamageValue(healthAV, damage)
	EndIf
EndFunction
