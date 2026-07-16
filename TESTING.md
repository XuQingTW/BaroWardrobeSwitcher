# Release test matrix

This checklist is the release gate for v0.5.0. Automated checks must pass before `filelist.xml` is marked compatible with a new Barotrauma version. The automated and manual sections were completed before promoting the 1.13.4.0 metadata to `verified`; future compatibility changes must repeat this gate.

## Automated checks

1. Run `scripts/Build.ps1` with explicit Barotrauma and LuaCs Publicized paths. Expected: zero warnings and errors; output only under `artifacts`.
2. Run `scripts/Test-Compatibility.ps1 -RequireOptional`. Expected: every exact 1.13.4.0 target reports `PASS`.
3. Run `scripts/Test-RendererContracts.ps1`. Expected: the crash characterizations, `RenderSession` aggregate, and functional-equipment-alarm lifecycle contract report `PASS`.
4. Run `scripts/Test-Persistence.ps1` with the same explicit paths. Expected: canonical v2, UTF-8 limit, migration/quarantine, and atomic-failure cases report `PASS`.
5. Run `scripts/Test-Lua.ps1`. Expected: every Lua source parses in Barotrauma's MoonSharp and every pure/authority test reports `PASS`.
6. Run `scripts/verify_package.py`. Expected: metadata agrees, every runtime source is listed, and no generated file is present in the source package.
7. Run `git diff --check` and confirm a build does not add working-tree changes outside ignored `artifacts`.

## P0 renderer regression

Use vanilla Barotrauma 1.13.4.0 plus LuaCs and this mod only. Repeat each scenario ten times while checking the LuaCs log and crash report directory.

- Save and apply a look while the original fashion item still exists as a live equipped entity.
- Apply the same persisted look after changing scene/campaign so the renderer must use prefab fallback.
- Apply after reconnect/late join when the target Character entity arrives after the network state.
- Repeat prefab fallback with gender/tag-substituted textures, `[VARIANT]`, and filename-relative item textures.
- Save/apply/clear/forget an empty look and a six-slot look.

Expected:

- No `ArgumentNullException (Parameter 'source')` from `Limb.Draw`.
- Every injected sprite reports initialized, owned resources and a non-null `CanBeHiddenByItem`.
- Clearing, scene change, character removal, plugin dispose, and a forced draw exception leave no session sprites or masking mutations behind.
- A synthetic exception thrown by another `Limb.Draw` patch still reaches its caller after wardrobe cleanup.

## Multiplayer and protocol

Run single-player, Windows host, and Linux dedicated server with at least two clients.

- v0.5.0 client ↔ v0.5.0 server negotiates v2.
- v0.5.0 client ↔ v1 server falls back after five seconds.
- v1 client ↔ v0.5.0 server continues through the six old message names.
- Duplicate operation IDs return the original result without applying twice.
- Out-of-order state is ignored; clear/forget followed by a late stale apply stays cleared.
- Join, reconnect, round start/end, death/respawn, character replacement, and campaign/server changes preserve the documented intent.
- An active look survives each character/scene replacement and renders exactly once after the initial-equipment gate. A saved-but-never-applied look stays inactive.
- `Clear Look` and `Forget Saved Look` remain inactive across round start, reconnect, death/respawn, and character replacement in single-player, v1 bridge, and v2 flows.
- Invalid version/slot, duplicate slot, truncated payload, identifier over 256 bytes, payload over 4 KiB, forged item ID/name, unknown prefab, and non-wearable slot are rejected atomically.
- Anonymous clients synchronize only for the live server session; stable accounts migrate and reload `ServerLooks.json`.

Expected steady state: no Wardrobe network traffic, persistence writes, or full-client scans until a relevant event occurs.

## Gameplay behavior

- Full inventory and partial unequip failure do not duplicate or destroy items.
- Hide Hair toggles immediately and survives persistence.
- Real equipment keeps stats, protection, oxygen, buffs, inventory, and health-interface behavior.
- Fashion animation and looping/one-shot/silent sound replacement matches v0.4 behavior when optional capabilities are available.
- With a visual look active over a real diving suit, low and empty oxygen alarms remain audible. Replacing/refilling the oxygen tank or removing the real suit stops the alarm through the game's native lifecycle.
- A saved diving-suit appearance without a real diving suit never creates a low/empty-oxygen alarm, and clearing/removing the appearance leaves no alarm behind.
- Unconditional diving-suit ambience remains suppressible under the existing cosmetic sound rules.
- Disabling C# scripting makes renderer readiness fail closed without changing real equipment.

## Conflict set

After isolated tests pass, repeat the renderer regression with:

1. A synthetic Harmony patch on the exact `Limb.Draw` overload.
2. Performance Fix.
3. ItemOptimizer.
4. Performance Fix and ItemOptimizer together.

Record exact mod versions with the result. A failure must be reproducible in isolation before changing the compatibility adapter.
