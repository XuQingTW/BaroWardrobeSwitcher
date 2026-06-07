# Baro Wardrobe Switcher

LuaCsForBarotrauma client-side wardrobe switcher for real equipment plus stored fashion visuals.

## Design

- The currently worn equipment is the real set and keeps the real item effects.
- A saved look is captured from the current equipped clothes as visual-only item identifiers/names and wearable sprites, then removed from active equipment.
- Wardrobe/fashion data never applies extra stats, buffs, resistances, oxygen, armor, or skill effects.
- No panel is shown by default. Press `F8` to open or close the wardrobe panel.
- The panel stores one saved look: visual-only data plus C# wearable sprite overrides.
- `Save Current Outfit` verifies whether each fashion item left every managed worn slot. If an item is still equipped, the slot table lists where it remains.
- `Apply Saved Look` activates the stored visuals even when no real equipment is currently worn. It does not equip gear for you.
- Empty outfits are valid saved looks. Saving while no managed gear is worn creates an empty visual look that can be applied over real equipment.
- `Clear Look` restores real equipment visuals without deleting the saved look.
- `Forget Saved Look` deletes the saved look. Scene transitions and round ends do not delete saved looks.

## Current flow

1. Wear the fashion/look set A, or wear nothing to save an empty visual look.
2. Press `Save Current Outfit`; the worn A items are removed from active equipment.
3. Equip any real set B normally.
4. Press `Apply Saved Look`; the character keeps B's real effects while C# draws the stored fashion sprites client-side. If no B gear is worn, the stored fashion is still drawn.
5. When the next scene starts, the saved look is rebuilt for the new character instance from saved item identifiers and reapplied after Barotrauma's initial equipment burst settles.

## Notes

- Enable `LuaCsForBarotrauma` together with this mod.
- Enable CSharp scripting in the LuaCs Settings menu and accept/enable this mod's C# run prompt; the visual override patch is client-side C#.
- The C# plugin is loaded by LuaCs from `CSharp/Client/WardrobeVisualOverridePlugin.cs`.
- At the start of each round, the mod posts an English in-game notice that the wardrobe control panel opens with `F8`.
- A successful C# load prints:
  - `[Baro Wardrobe Switcher] C# visual override v0.3.15 initializing.`
  - `[Baro Wardrobe Switcher] C# visual override loaded: ready.`
- If the panel says `C#: unavailable` or `C#: missing required hooks`, enable C# scripting in LuaCs, accept this mod's C# prompt, and reload before saving or applying a look.
- Client saved looks are stored outside the mod folder under the user's Barotrauma local app data, then migrated from the old `PersistentClientLook.txt` file when present.
- This version is intentionally conservative: it avoids a permanent extra UI column.
- The visual override is draw-only. It explicitly patches `Limb.DrawWearable` and `Limb.Draw` when those targets are available, and does not mutate `Wearable.wearableSprites`, because changing those arrays can break unequip/swap logic.
- Real combat equipment masking flags are cleared while the look is active, and captured fashion sprites no longer hide hair/face attachments. Hats that normally suppress hair will not leave the character bald when used as a saved look.
- Only `WearableType.Item` sprites are replaced. Character hair, beard, moustache, and face attachments are left to the original character renderer.
- Masking flags on the real equipped item sprites are temporarily cleared for the active character while the override is active, then restored on clear/reload. This keeps gloves, shoes, sleeves, and similar partial gear from hiding the original body parts underneath the visual override.
- Fashion item `<TriggerAnimation>` effects from `OnWearing` status effects are replayed after the real outfit updates while the look is active, so decorative movement takes priority over the real combat outfit.
- Fashion item sounds replace matching real-equipment sounds while the look is active. The C# hook covers both `OnWearing <Sound>` status effects and item component `<sound type="...">` playback, can replace across those two sound sources when mods define the fashion and real gear differently, and keeps looping saved-fashion sounds alive even when the real equipment has no matching sound.
- Multiplayer uses a small server-side Lua sync helper. The server persists saved wardrobe item identifiers by client key, performs the server-authoritative removal, and broadcasts apply/clear events so other clients with LuaCs and C# scripting enabled can see the active look.
