# Baro Wardrobe Switcher

LuaCsForBarotrauma client-side wardrobe switcher for real equipment plus stored fashion visuals.

Version 0.5.3 targets the verified Barotrauma 1.13.4.0 and LuaCs contracts. It preserves per-item custom clothing colors across save, apply, scene changes, reconnects, and restarts using protocol/look schema 3. See [ARCHITECTURE.md](ARCHITECTURE.md) for component boundaries and [COMPATIBILITY.md](COMPATIBILITY.md) for the pinned game/LuaCs contracts and release gates.

## Design

- The currently worn equipment is the real set and keeps the real item effects.
- A saved look persists stable item identifiers, optional per-item `SpriteColor.PackedValue` values, and user intent; initialized renderer-owned sprite descriptors are rebuilt for each target character, then the captured real items are removed from active equipment.
- Wardrobe/fashion data never applies extra stats, buffs, resistances, oxygen, armor, or skill effects.
- No panel is shown by default. Press `F8` to open or close the wardrobe panel.
- In single-player, each human player-team crew member has an independent saved look. Multiplayer keeps the existing per-client saved-look behavior.
- `Transfer to unconfigured characters` is a global single-player toggle. It defaults to off, is remembered across restarts, and only copies an active source look into a character that has no profile of their own.
- `Save Current Outfit` verifies whether each fashion item left every managed worn slot. If an item is still equipped, the slot table lists where it remains.
- `Apply Saved Look` activates the stored visuals even when no real equipment is currently worn. It does not equip gear for you.
- Saving only stores the look; it does not mark the look for automatic activation. A look is automatically rebuilt after a scene or character change only if it was successfully applied beforehand.
- Active NPC crew profiles are restored after their replacement Character instances finish initial equipment setup, even if the player never switches control to those NPCs.
- Empty outfits are valid saved looks. Saving while no managed gear is worn creates an empty visual look that can be applied over real equipment.
- `Clear Look` restores real equipment visuals without deleting the saved look, and also disables automatic reapplication until `Apply Saved Look` succeeds again.
- `Forget Saved Look` deletes the saved look and disables automatic reapplication. Scene transitions and round ends do not delete saved looks.
- `Appearance Layers...` controls `Hair`, `Beard`, `Moustache`, and `Face Attachment` independently. Each layer cycles through `Auto`, `Hide`, and `Show`. `Auto` follows the appearance item's XML mask, `Hide` force-hides the layer, and `Show` force-preserves it even when equipped fashion declares that type hidden. All four layers default to `Auto`.
- Character mods may reuse these wearable slots as pieces of a composite head. Use `Show` for the reused layer instead of broadly hiding all hair-related slots. The `Hide Standard Hair` preset reproduces the old coarse behavior for Hair/Beard/Moustache while leaving Face Attachment automatic.

## Current flow

1. Wear the fashion/look set A, or wear nothing to save an empty visual look.
2. Press `Save Current Outfit`; the worn A items are removed from active equipment.
3. Equip any real set B normally.
4. Press `Apply Saved Look`; the character keeps B's real effects while C# draws the stored fashion sprites client-side. If no B gear is worn, the stored fashion is still drawn.
5. If that crew member's look was active before a scene change, it is rebuilt for the replacement character instance after Barotrauma's initial equipment burst settles. Every active NPC profile restores independently; saved-but-inactive and manually cleared profiles stay inactive.

## Notes

- Enable `LuaCsForBarotrauma` together with this mod.
- Enable CSharp scripting in the LuaCs Settings menu and accept/enable this mod's C# run prompt; the visual override patch is client-side C#.
- The C# compatibility adapter is compiled from the source-only `CSharp/Client` folder by LuaCs.
- At the start of each round, the mod posts a localized in-game notice that the wardrobe control panel opens with `F8`.
- A successful C# load prints:
  - `[Baro Wardrobe Switcher] C# visual override v0.5.3 initializing.`
  - `[Baro Wardrobe Switcher] C# visual override loaded: ready.`
- If the panel says `C#: unavailable` or `C#: missing required hooks`, enable C# scripting in LuaCs, accept this mod's C# prompt, and reload before saving or applying a look.
- Multiplayer client looks use persistence schema-v4 `ClientLook.json`. Single-player crew profiles use schema-v3 `SinglePlayerProfiles.json`, scoped by a SHA-256 hash of the campaign save path and a SHA-256 hash of the character fingerprint. Both formats store the complete four-layer visibility object and a parallel optional color map. Valid older files migrate automatically with versioned backups; colors that were never stored remain absent and use the prefab base color. Writes are atomic, corrupt files are quarantined, and raw campaign paths are never written to disk.
- A legacy `ClientLook.json` is imported at most once per campaign into the first controlled non-bot character, without overwriting an existing crew profile. The imported look is saved but inactive, even if the legacy file recorded active/auto-apply intent, so starting equipment remains visible until `Apply Saved Look` is pressed. The original file remains available for multiplayer. Single-player scenes without a campaign save path use memory-only profiles.
- If two current crew members have the same stable fingerprint, automatic disk restoration is disabled for both rather than risking the wrong appearance.
- This version is intentionally conservative: it avoids a permanent extra UI column.
- The visual override is draw-only. It explicitly patches `Limb.DrawWearable` and `Limb.Draw` when those targets are available, and does not mutate `Wearable.wearableSprites`, because changing those arrays can break unequip/swap logic.
- Real combat equipment masking flags are cleared while the look is active. Original attachment visibility is decided at draw time using `Force Show > Force Hide > appearance-item XML mask`; clearing the look resets both force masks.
- Saved bag and health-interface/exosuit sprites are drawn on a recessed wardrobe layer so they do not float over arm movement or hair after the look is applied.
- Only `WearableType.Item` sprites are replaced. Character hair, beard, moustache, and face attachments remain owned by the original character renderer and are filtered only by the active four-layer policy.
- Masking flags on the real equipped item sprites are temporarily cleared for the active character while the override is active, then restored on clear/reload. This keeps gloves, shoes, sleeves, and similar partial gear from hiding the original body parts underneath the visual override.
- Fashion item `<TriggerAnimation>` effects from `OnWearing` status effects are replayed after the real outfit updates while the look is active, so decorative movement takes priority over the real combat outfit.
- Fashion item sounds replace matching cosmetic real-equipment sounds while the look is active. The C# hook covers both `OnWearing <Sound>` status effects and item component `<sound type="...">` playback, can replace across those two sound sources when mods define the fashion and real gear differently, and keeps looping saved-fashion sounds alive even when the real equipment has no matching sound. Unconditional equipment ambience such as diving-suit loops can still be suppressed or replaced. Conditional and required-item status sounds are treated as gameplay alarms instead: they are never captured as fashion audio or added to the suppression set, so a real suit's low/empty-oxygen alarm starts and stops under Barotrauma's native oxygen, tank, and unequip rules. If alarm classification cannot be inspected on a future game build, the safe fallback is to allow the original sound.
- Multiplayer uses a small server-side Lua sync helper. The server persists saved wardrobe item identifiers by client key, performs the server-authoritative removal, and broadcasts apply/clear events so other clients with LuaCs and C# scripting enabled can see the active look.
- Apply requests carry stable visual identifiers so a look can be imported across campaigns and servers. The server resolves every identifier against its own `ItemPrefab` data, verifies the wearable/slot relationship, discards client item IDs and names, and broadcasts only canonical state.
- Server persistence uses schema-v4 `ServerLooks.json` and stable `Client.AccountId` representations. Valid v2/v3 files migrate with versioned backups; authoritative JSON no longer stores `hideHair`. Anonymous clients can sync during the current server session but are never persisted by display name.
- In multiplayer, `Clear Look` only deactivates the current visual look while keeping the saved look. `Forget Saved Look` also asks the server to delete the saved look for that client, so it will not be restored by later round-start or reconnect sync.
- Saving a new outfit while an old multiplayer look is active clears the old server-side active look before storing the new saved identifiers, preventing other clients from keeping stale visuals.
- Protocol 3 retains hello negotiation, operation IDs, revisions, acknowledgements, idempotent retry, and stale-command rejection, and adds an optional `UInt32` color after each wire slot. The original six message names remain as a v1 bridge; mixed protocol versions fall back to v1 and therefore use prefab base colors.
- Protocol-3 peers advertise attachment-visibility capability `0x01`. A complete four-byte optional look tail carries force-hide/show masks. When the server does not advertise support, the client keeps the detailed policy locally and sends only the safe legacy `hideHair` projection.
- The renderer continues through Barotrauma's native `Item.GetSpriteColor()` path. Colored prefab fallbacks set `Item.SpriteColor` before capture; the mod does not recompute or double-multiply tint, limb alpha, or death color.
- Server synchronization is event-driven: connect sends a targeted snapshot and accepted state changes broadcast once. There is no steady-state heartbeat or per-frame full-client scan; clients still hold early apply/clear messages briefly while a target character entity is spawning.

## Build and verification

Release builds require explicit paths and write only to the ignored `artifacts` directory:

```powershell
./scripts/Build.ps1 `
  -BarotraumaInstallDir "C:\Program Files (x86)\Steam\steamapps\common\Barotrauma" `
  -LuaCsPublicizedDir "C:\Program Files (x86)\Steam\steamapps\common\Barotrauma\Publicized"
```

Run `scripts/Test-Compatibility.ps1` against the same installation, execute the pure Lua tests under MoonSharp, and run `scripts/verify_package.py` before packaging. After the manual matrix is complete and compatibility metadata is promoted, `scripts/verify_package.py --release` is the final manifest gate. Game assemblies and generated binaries must never be committed or included in the Workshop source package.
