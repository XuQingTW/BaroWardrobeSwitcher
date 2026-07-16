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

`autoApply` represents activation intent, not merely the existence of a saved look. Save leaves it disabled, a successful render enables it, and clear/forget disable it. Character and scene cleanup may carry `preserveAutoApply` only when the outgoing look was active or already marked for reapplication, allowing the replacement character to render once after the initial-equipment gate without undoing a manual clear.

Server state is grouped per client session. Every accepted v2 command advances a server-owned revision. Commands include their base revision and operation ID, so retries are idempotent and stale apply requests cannot reactivate a look after clear or forget. A stable account keeps the current client-session dedupe cache across reconnects. Each cache retains at most 512 results; once full, unknown operations fail closed with a stable `operation_limit_reached` result until the client starts a new session. Revision exhaustion similarly rejects mutations with `revision_exhausted` instead of reusing `UInt32.MaxValue`.

Connection, round, and LuaCs `character.created` events rebind active sessions to new Character entity IDs. A bounded event-triggered retry handles the short assignment race during respawn; there is no per-frame client/equipment scan.

## Renderer safety boundary

The renderer targets only the exact Barotrauma signatures recorded in [COMPATIBILITY.md](COMPATIBILITY.md). Required draw hooks fail closed; optional animation and sound hooks degrade independently.

Fashion sprites are initialized for the target character before use and are owned by a render session. A draw transaction may temporarily expose validated sprites to Barotrauma's official renderer, but it must snapshot and restore every changed collection or masking value in its finalizer. Cleanup never suppresses an exception from Barotrauma or another mod.

Functional-fashion filtering is composed directly as policy. It does not Harmony-patch private methods of this mod.

Conditional or required-item `StatusEffect` sounds are classified as gameplay alarms. They are excluded from fashion capture and real-equipment suppression so Barotrauma retains ownership of their start/stop lifecycle; reflection failure defaults to allowing the original sound.

## Persistence boundary

Only stable identifiers and user intent are persisted. Runtime entity IDs and localized display names are never authoritative.

- Client: `ClientLook.json`, schema 2.
- Server: `ServerLooks.json`, schema 2, keyed by stable `Client.AccountId` representation.
- Anonymous clients: memory only for the current server session.

Writes use a same-directory temporary file and replacement/backup. Legacy files are migrated once and retained as `.v1.bak` for the v0.5.0 compatibility window. Corrupt files are quarantined instead of being applied.

## Packaging

LuaCs compiles client C# from source through `ModConfig.xml`. Release packages therefore contain source only. `bin`, `obj`, `artifacts`, disabled binaries, runtime persistence files, and game assemblies are never package inputs.
