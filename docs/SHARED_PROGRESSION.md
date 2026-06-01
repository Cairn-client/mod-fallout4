# Can F4MP have shared multiplayer / campaign progression?

**Short answer: partially yes, fully no — not without building a large new system.**

You asked whether F4MP could do what some games do, where players share campaign progress.
Here's the honest picture, in plain terms.

---

## What "shared progression" actually means

In games built for co-op campaigns (Borderlands, Divinity: Original Sin 2, Halo), the studio
designed *from day one* for two players to share the same story. There's usually a **host** whose
save file is "the world," and joiners attach to it. Quest steps, dead enemies, opened doors,
looted containers, and world changes all live on that host and get streamed to everyone.

Fallout 4 was **never** built for this. It's a single-player engine. Everything about the world —
every quest flag, every NPC's state, your inventory, the map — lives inside *one* save file on
*one* machine. The engine has no concept of "another player's world."

## What F4MP does today (and doesn't)

F4MP uses a **"clone the player"** model. Read the code this way:
- When you connect, your game tells the server: here's my appearance, my worn gear, my position.
  (`f4mp/Player.cpp` → `OnConnectRequest`)
- The server relays that to everyone else, and each player's game spawns a **puppet actor** that
  looks like you and copies your movement/animation. (`F4MPQuest.psc` → `OnEntityCreate`)
- A few live values are streamed: position, facing angles, health %, and a basic animation state.
  (`Player.cpp` → `OnClientUpdate` / `OnEntityUpdate`)

That's it. **Each player is still playing their own separate single-player game.** You see a moving
mannequin of your friend, but their quests, their dialogue choices, the enemies they kill, the
loot they grab — none of that exists in your world, and vice-versa. There is no shared save.

So today F4MP shares: **appearance, position, animation, health.**
It does **not** share: quests, world state, inventory, containers, dead/alive NPCs, time of day,
settlement building (partially attempted — see TODO B2), or saves.

## Is shared progression *possible*? Yes — but it's a major project

It's technically possible to push much further, in increasing order of difficulty:

| Level | What players share | Difficulty | Notes |
|-------|--------------------|-----------|-------|
| 0 (today) | Appearance, position, health | — | Done |
| 1 | Combat that affects each other (real damage, shared enemies) | Medium | NPC sync (TODO B1) is the gate |
| 2 | Shared loot / containers / world objects in the same cell | Hard | Needs authoritative world state |
| 3 | Shared quest progression (quest stages advance for everyone) | Very hard | Quest flags are deeply engine-internal |
| 4 | Fully shared save (host's world is THE world) | Extremely hard | Essentially a new game architecture |

The reason it gets so hard so fast: Fallout 4's quest, dialogue, and world systems are baked into
the engine and the game's data, **not** exposed cleanly to mods. Replicating a quest stage isn't
"send a number" — it's reproducing every script, package, and world edit that the engine does
locally when that stage advances, and getting two engines to agree. The big multiplayer projects
that attempt this (e.g. the long-running Skyrim/Fallout co-op mods) take **years** and large teams,
and still wrestle with desync and crashes.

## Recommended realistic path for this project

Given the "clone the player" foundation, the achievable and worthwhile next steps are **Level 1**:

1. **Make NPC/enemy sync real (TODO B1).** One player's game becomes the authority for a given
   enemy; its position/health/death streams to others. This is the single biggest gameplay upgrade
   and is consistent with the existing architecture.
2. **Shared damage** (already partly present via `PlayerHit`/`HitData`) — make sure hits between
   players and on shared NPCs register on the right machine.
3. **Settlement/building sync (TODO B2)** — finish what's started so co-op base-building works.

These give a real "we're fighting through the wasteland together" experience.

**Level 3–4 (shared quests / shared save) are out of scope** for this codebase as it stands — they
would require redesigning around a host-authoritative world, which is a different and much larger
project. Worth keeping as a long-term north star, not a near-term task.

## Bottom line for you
- You can keep and improve what's there: people **stay connected and see each other** — that's the
  TODO's "A. Connection stability" section, and it's the right first priority.
- "Playing the same campaign together with shared quest progress" is a **much** bigger lift than
  fixing connection stability, and realistically a separate, long-term effort.
