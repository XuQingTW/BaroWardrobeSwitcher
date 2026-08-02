# Release test matrix

This checklist is the release gate for v0.5.10. Automated checks must pass before packaging, and the custom-color matrix below must be completed in game before release. The pinned 1.13.4.0 compatibility target retains its previously verified renderer and multiplayer matrix.

## Automated checks

1. Run `scripts/Build.ps1` with explicit Barotrauma and LuaCs Publicized paths. Expected: zero warnings and errors; output only under `artifacts`.
2. Run `scripts/Test-Compatibility.ps1 -RequireOptional`. Expected: every exact 1.13.4.0 target reports `PASS`.
3. Run `scripts/Test-RendererContracts.ps1`. Expected: the crash characterizations, live-equipment mask/cache transaction, fashion-footstep transaction/finalizer, inactive-render allocation guard, batched equipment refresh, `RenderSession` aggregate, attachment-visibility priority/no-wearable-refresh contract, and functional-equipment-alarm lifecycle report `PASS`.
4. Run `scripts/Test-Persistence.ps1` with the same explicit paths. Expected: canonical client v5 color/footstep round-trip, client v1/v2/v3/v4 migration, single-player profile v3 and v1/v2 migration, transfer round-trip, profile/campaign isolation, one-time inactive legacy import, quarantine, and atomic-failure cases report `PASS`.
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

- v0.5.10 client ↔ v0.5.10 server negotiates protocol version 5.
- v0.5.10 client ↔ older server falls back to v1 after five seconds and displays prefab base colors.
- Older client ↔ v0.5.10 server continues through the six v1 message names and displays prefab base colors.
- Duplicate operation IDs return the original result without applying twice.
- Out-of-order state is ignored; clear/forget followed by a late stale apply stays cleared.
- Join, reconnect, round start/end, death/respawn, character replacement, and campaign/server changes preserve the documented intent.
- In `Settings -> Mod Gameplay Settings`, change `Wardrobe Panel Key` from `F8` to `F7`, apply the settings, and begin a round. The notice and tutorial show `F7`; `F7` opens and closes the panel while `F8` no longer does. An invalid key name falls back to `F8` in both input and text.
- Open the wardrobe panel at minimum supported UI scale. The scrollable main page contains Save/Apply/Clear, appearance layers, transfer, Forget, and `Next Page`; movement animation, footstep source, and diagnostics appear only on the scrollable second page, whose Back button returns to the main page without leaving an old overlay active. Next/Back/Close must remain reachable after expanding the guide or diagnostics.
- On a current multiplayer server, confirm `Wardrobe target` cycles from the local player through friendly living human bots only. Save/Apply target the selected bot, the selector is disabled while a command is pending, and another client cannot steal the same active bot. On an older server without the capability, the selector remains self-only.
- Apply a look to a multiplayer bot, then reconnect and start the next round. The saved look remains available to its owner but is not automatically rebound to the owner's player character or any replacement bot.
- Apply a look to the local multiplayer player, then end the round after `Character.Controlled` has cleared. The next round restores the look to the replacement player entity even when the same session key becomes available shortly after `roundStart`; a genuinely different campaign key must not restore it.
- After the first successful local-player Apply, confirm `ServerLooks.json` and `WardrobeServer.log` exist under `Barotrauma/ModData/BaroWardrobeSwitcher`; the server console must not report `storage_unavailable` or `Path: nil`. Repeat on a P2P host whose `Client.AccountId` is unavailable and confirm the record uses the stable `steam:<SteamID>` fallback.
- Fully close the P2P or dedicated server, restart it into the lobby, load the same campaign save, and reconnect. The active local-player look restores after the durable campaign key becomes available; loading a different campaign does not restore that look.
- On a P2P host, change session or scene while retaining the same controlled Character and while a command is awaiting acknowledgement. Reopening F8 must leave Save, Apply, and Clear usable after the new session binds.
- An active look survives each character/scene replacement and renders exactly once after the initial-equipment gate. A saved-but-never-applied look stays inactive.
- `Clear Look` and `Forget Saved Look` remain inactive across round start, reconnect, death/respawn, and character replacement in single-player, v1 bridge, and v2 flows.
- Invalid version/slot/color, orphan color, duplicate slot, truncated color/payload, identifier over 256 bytes, payload over 4 KiB, forged item ID/name/color, unknown prefab, and non-wearable slot are rejected atomically.
- Optional look/hello tails accept only absent or complete supported extensions. Partial tails, unknown marker/version, unknown mask bits, and overlapping force-hide/show bits are rejected atomically.
- A `visibility` command changes only the authoritative saved look's four-layer policy; client-supplied equipment slots cannot replace the server capture. Verify active broadcast, inactive state response, reject/timeout rollback, missing-capability behavior, and mixed-version v1 fallback.
- Anonymous clients synchronize only for the live server session; stable accounts migrate and reload `ServerLooks.json`.

Expected steady state: no Wardrobe network traffic, persistence writes, or full-client scans until a relevant event occurs.

## Single-player crew profiles

Use a campaign with at least the player and two controllable human NPC crew members.

- Leave appearance transfer disabled, apply a player look, and switch to an unconfigured NPC. The NPC keeps its original appearance.
- Without changing `Character.Controlled`, cycle `Wardrobe target` through two friendly living bots. Save, apply, clear, forget, change appearance layers, movement animation, and footstep source for each target; each operation and profile must affect only the selected NPC. Other real players, enemies, nonhumans, dead crew, and removed crew never appear in the cycle.
- Remove or kill the selected NPC while the panel is open. The target safely returns to the controlled character and no NPC state is written into the player's profile.
- Enable appearance transfer and switch from an active source to an unconfigured NPC. The look is copied only after a successful render and then belongs to that NPC.
- Give two NPCs different looks, apply both, and enter the next scene without controlling either NPC. Both restore after initial equipment settles.
- Restart the game and reload the same campaign. Active profiles restore to the matching crew members; a saved-but-inactive profile remains inactive.
- Start a new campaign while a legacy `ClientLook.json` records an active/auto-applied look and no profile exists for the new campaign. The first controlled character receives the saved look without activating it, and their real starting equipment remains visible until `Apply Saved Look` is pressed.
- With transfer enabled, switch to a crew member who already has a profile. Their profile is neither overwritten nor activated unless its own auto-apply intent is enabled.
- Clear and forget one NPC. Other active NPC appearances and persisted profiles remain unchanged.
- Load two current crew members with the same stable fingerprint. Neither receives an automatic disk-restored look, and the F8 panel reports ambiguous identity.
- Test a non-campaign single-player scene. Profiles work for the current process but are not promised after restart.

## Gameplay behavior

- Save and apply opaque and semi-transparent custom clothing colors in single-player, then clear/reapply, change scene, and restart. The exact packed color must return without being multiplied twice.
- Repeat custom-color save/apply as multiplayer owner, observer, late joiner, and reconnecting player. Server Save must use the equipped entity color rather than a client-supplied value.
- Apply two slots that use the same prefab identifier with different colors. Both visual entries must remain distinct.
- Keep another inventory item with the same prefab but a different color. Applying the saved look must use the exact entity only when entity ID, identifier, and color all match; otherwise it must use the saved colored prefab fallback.
- Load migrated client/server/profile documents from before color persistence. They must use prefab base colors, not opaque white.
- Full inventory and partial unequip failure do not duplicate or destroy items.
- Each appearance layer cycles `Auto -> Hide -> Show`, previews immediately, and survives scene changes, restart, single-player profile transfer, and multiplayer synchronization.
- With [EuropaWaifu 2](https://steamcommunity.com/sharedfiles/filedetails/?id=2948283083), apply a look whose XML does not hide Hair, then equip `cultistrobes` (Cultist Robes) and `zealotrobes` (Zealot Robes). Hair remains visible in `Auto` and `Show`; `Hide` still hides it. Clear the look and confirm both robes return to their native hair-hiding behavior.
- With [[R18+]异种♥木卫二](https://steamcommunity.com/sharedfiles/filedetails/?id=3156077899), save and apply `divingsuit`, `abyssdivingsuit`, `combatdivingsuit`, and `respawndivingsuit`. Each `Hide LeftBreast` sprite must affect only the custom `LeftBoobs` limb (ID 17), with no duplicate or misplaced suit piece and no hidden appendage on another `LimbType.None` limb; clearing the look restores native rendering.
- With a saved look active, raise CPU load and repeatedly equip, swap, and remove one-slot and multi-slot real clothing in single-player, as the multiplayer owner, and as an observer. Equipment changes should not produce a wardrobe capture, profile/server persistence write, or extra wardrobe Apply command; the look and cosmetic sound/animation suppression should update without a visible hitch.
- EA-HI/manual composite-head check: apply the appearance, set `Hair=Show`, then hide only the Beard/Moustache layers actually required. The modded head and decorations must remain present and must not revert to the Vanilla head.
- Confirm appearance-layer buttons never trigger `Character.OnWearablesChanged()` and that local persistence failure restores the complete prior policy and active render state.
- Real equipment keeps stats, protection, oxygen, buffs, inventory, and health-interface behavior.
- With a visual look active, equip and remove a real diving suit before and after wardrobe synchronization on both the owning client and an observer. Body limbs remain visible and the suit appearance remains stable.
- Fashion animation and looping/one-shot/silent sound replacement matches v0.4 behavior when optional capabilities are available.
- On page two, `Footstep Sounds: Follow Equipment` keeps the game's native ground-impact sounds from real equipped wearables. Switching it to `Follow Fashion` uses only matching-limb sounds from the applied fashion descriptors; switching back restores equipment sounds immediately. Verify the local player and selected bots in single-player, multiplayer owner/observer, late join, and reconnect. The option must persist independently per look and must not send a separate sound/network event for each step.
- Force another `Ragdoll.PlayImpactSound` patch to throw after the wardrobe prefix. The wardrobe finalizer must restore the exact original `Limb.WearingItems` order and preserve the original exception.
- With a visual look active over a real diving suit, low and empty oxygen alarms remain audible. Replacing/refilling the oxygen tank or removing the real suit stops the alarm through the game's native lifecycle.
- A saved diving-suit appearance without a real diving suit never creates a low/empty-oxygen alarm, and clearing/removing the appearance leaves no alarm behind.
- Unconditional diving-suit ambience remains suppressible under the existing cosmetic sound rules.
- Disabling C# scripting makes renderer readiness fail closed without changing real equipment.

## Conflict set

After isolated tests pass, repeat the renderer regression with:

1. A synthetic Harmony patch on the exact `Limb.Draw` overload.
2. A synthetic Harmony patch on `Ragdoll.PlayImpactSound(Limb)`.
3. Performance Fix.
4. ItemOptimizer.
5. Performance Fix and ItemOptimizer together.

Record exact mod versions with the result. A failure must be reproducible in isolation before changing the compatibility adapter.
