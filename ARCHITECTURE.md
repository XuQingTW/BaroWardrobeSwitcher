# Architecture

Baro Wardrobe Switcher is a hybrid modular monolith. It is one Barotrauma content package, but game-facing adapters are kept separate from deterministic state and protocol code.

## Runtime boundaries

- `Lua/WardrobeCore.lua` owns the versioned look schema, slot keys, network codecs, limits, and client reducer. It has no Barotrauma or LuaCs dependency and is loaded in both realms.
- `Lua/WardrobeSwitcher.lua` is the client adapter. It owns the F8 UI, character/inventory hooks, persistence calls, renderer calls, and v1/v2 network negotiation.
- `Lua/WardrobeSwitcherServer.lua` is the authoritative server adapter. It validates commands against server content, owns revisions and idempotency, persists stable accounts, and sends canonical state.
- `CSharp/Client` is a client-only compatibility adapter for Barotrauma rendering, animation, and sound. It must not own multiplayer truth.

The server does not load C#. Linux dedicated servers therefore use the same Lua server implementation as Windows hosts.

## State and effects

The pure client reducer uses these phases:

`NoCharacter -> Idle -> Saving -> SavedInactive -> ApplyPending -> Active`

Clear operations pass through `ClearPending`; rejected commands, invalid render assets, and unavailable required hooks enter `Faulted`. The reducer returns effects such as capture, persistence, network send, render, and clear. The client adapter performs those effects and feeds success or failure events back to the reducer.

Attachment visibility is a canonical four-key value object (`Hair`, `Beard`, `Moustache`, `FaceAttachment`) with `auto`, `hide`, and `show` states. The reducer updates it atomically. Active changes preview through `ApplyAttachmentVisibility`; persistence, network rejection, timeout, or renderer failure use explicit compensation effects to restore the previous whole policy.

`autoApply` represents activation intent, not merely the existence of a saved look. Save leaves it disabled, a successful render enables it, and clear/forget disable it. Character and scene cleanup may carry `preserveAutoApply` only when the outgoing look was active or already marked for reapplication, allowing the replacement character to render once after the initial-equipment gate without undoing a manual clear.

Server state is grouped per client session. Every accepted v2 command advances a server-owned revision. Commands include their base revision and operation ID, so retries are idempotent and stale apply requests cannot reactivate a look after clear or forget. A stable account keeps the current client-session dedupe cache across reconnects. Each cache retains at most 512 results; once full, unknown operations fail closed with a stable `operation_limit_reached` result until the client starts a new session. Revision exhaustion similarly rejects mutations with `revision_exhausted` instead of reusing `UInt32.MaxValue`.

In single-player, runtime state is keyed by `Character.Info.ID`, so changing the controlled Character does not replace another crew member's state. The disk key is a stable fingerprint built from `OriginalName`, `SpeciesName`, and `HumanPrefabIds`; runtime entity IDs are never persisted. Fingerprint collisions fail closed for automatic restoration.

At round start the client scans `Character.CharacterList` once, then follows `character.created`, `item.equip`, and `item.unequip` events. Each queued NPC waits for 12 stable equipment ticks, with a 120-tick fallback, before rebuilding its renderer session. The per-frame hook only processes this bounded queue; it does not scan the full crew list.

Multiplayer connection, round, and LuaCs `character.created` events continue to rebind active sessions to new Character entity IDs. A bounded event-triggered retry handles the short assignment race during respawn; there is no per-frame client/equipment scan.

## Renderer safety boundary

The renderer targets only the exact Barotrauma signatures recorded in [COMPATIBILITY.md](COMPATIBILITY.md). Required draw hooks fail closed; optional animation and sound hooks degrade independently.

Fashion sprites are initialized for the target character before use and are owned by a render session. A draw transaction may temporarily expose validated sprites to Barotrauma's official renderer, but it must snapshot and restore every changed collection or masking value in its finalizer. Cleanup never suppresses an exception from Barotrauma or another mod.

Functional-fashion filtering is composed directly as policy. It does not Harmony-patch private methods of this mod.

Conditional or required-item `StatusEffect` sounds are classified as gameplay alarms. They are excluded from fashion capture and real-equipment suppression so Barotrauma retains ownership of their start/stop lifecycle; reflection failure defaults to allowing the original sound.

## Persistence boundary

Only stable identifiers, optional packed sprite colors, and user intent are persisted. Runtime entity IDs and localized display names are never authoritative.

- Client: `ClientLook.json`, persistence schema 4.
- Single-player: `SinglePlayerProfiles.json`, schema 3. It stores the global transfer toggle, imported campaign hashes, campaign/character-scoped profiles, complete attachment visibility, and optional colors.
- Server: `ServerLooks.json`, persistence schema 4, keyed by stable `Client.AccountId` representation.
- Anonymous clients: memory only for the current server session.

Campaign save paths and stable character fingerprints are SHA-256 hashed before persistence. Character display names are diagnostic only. A campaign-less single-player scene uses memory-only profiles. Legacy `ClientLook.json` data is imported once per campaign into the first controlled non-bot character and never overwrites an existing profile. Import preserves the captured look but deliberately clears auto-apply intent, because a legacy saved look is not consent to override a new campaign's starting equipment.

Wire look schema 3 and persistence schema 4 are separate constants. Each network slot carries its identifier, a color-presence bit, and an optional packed color; the optional marker/version/mask tail remains independent of persistence.

Writes use a same-directory temporary file and replacement/backup. Valid older client/server/profile files migrate with versioned backups. Missing legacy colors remain absent so Barotrauma uses each prefab's base color. Corrupt files are quarantined instead of being applied.

## Packaging

LuaCs compiles client C# from source through `ModConfig.xml`. Release packages therefore contain source only. `bin`, `obj`, `artifacts`, disabled binaries, runtime persistence files, and game assemblies are never package inputs.
