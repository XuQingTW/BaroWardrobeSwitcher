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
- `Hide Hair` / `Show Hair` toggles whether the character's own hair, beard, and moustache are hidden while a saved look is active. Use it when a helmet or hat that does not declare its own hair mask leaves hair poking through. The toggle defaults to showing hair, takes effect immediately while a look is active, is remembered with the saved look across scenes and restarts, and applies client-side to your own character.

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
  - `[Baro Wardrobe Switcher] C# visual override v0.3.21 initializing.`
  - `[Baro Wardrobe Switcher] C# visual override loaded: ready.`
- If the panel says `C#: unavailable` or `C#: missing required hooks`, enable C# scripting in LuaCs, accept this mod's C# prompt, and reload before saving or applying a look.
- Client saved looks are stored outside the mod folder under the user's Barotrauma local app data, then migrated from the old `PersistentClientLook.txt` file when present. Saved looks are restored across campaigns: a look saved in one campaign session is reloaded and reapplied when another campaign or a reloaded save starts.
- This version is intentionally conservative: it avoids a permanent extra UI column.
- The visual override is draw-only. It explicitly patches `Limb.DrawWearable` and `Limb.Draw` when those targets are available, and does not mutate `Wearable.wearableSprites`, because changing those arrays can break unequip/swap logic.
- Real combat equipment masking flags are cleared while the look is active. Saved fashion sprites hide only the hair/beard/moustache/face attachment types they declare in their wearable definition, and only while the look is active, so saved helmets cover hair correctly without leaving the character bald after the look is cleared.
- Saved bag and health-interface/exosuit sprites are drawn on a recessed wardrobe layer so they do not float over arm movement or hair after the look is applied.
- Only `WearableType.Item` sprites are replaced. Character hair, beard, moustache, and face attachments are still drawn by the original character renderer, except when the active saved look declares that it hides them or the `Hide Hair` toggle is enabled. The toggle force-hides hair, beard, and moustache (face attachments are left visible) while the look is active.
- Masking flags on the real equipped item sprites are temporarily cleared for the active character while the override is active, then restored on clear/reload. This keeps gloves, shoes, sleeves, and similar partial gear from hiding the original body parts underneath the visual override.
- Fashion item `<TriggerAnimation>` effects from `OnWearing` status effects are replayed after the real outfit updates while the look is active, so decorative movement takes priority over the real combat outfit.
- Fashion item sounds replace matching real-equipment sounds while the look is active. The C# hook covers both `OnWearing <Sound>` status effects and item component `<sound type="...">` playback, can replace across those two sound sources when mods define the fashion and real gear differently, and keeps looping saved-fashion sounds alive even when the real equipment has no matching sound. Looping real-equipment sounds (diving suits, exosuits, beeping headsets) are silenced rather than re-triggered through one-shot fashion sounds, which previously caused continuous beeping while the look was active.
- Multiplayer uses a small server-side Lua sync helper. The server persists saved wardrobe item identifiers by client key, performs the server-authoritative removal, and broadcasts apply/clear events so other clients with LuaCs and C# scripting enabled can see the active look.
- Apply requests carry the client's own saved visual identifiers. This lets a look be rebuilt and broadcast after a scene/campaign change even when the server no longer holds (or never held) that client's saved state — for example after joining a different campaign or server, or when the server's `ServerLooks.txt` was reset. The server still falls back to its stored state for older clients that send no payload.
- Server persistence only uses stable SteamID or account identifiers. Clients without a stable nonzero identifier can still sync the current character during the current round, but their server-side wardrobe state is not persisted or restored across reconnect/session boundaries.
- In multiplayer, `Clear Look` only deactivates the current visual look while keeping the saved look. `Forget Saved Look` also asks the server to delete the saved look for that client, so it will not be restored by later round-start or reconnect sync.
- Saving a new outfit while an old multiplayer look is active clears the old server-side active look before storing the new saved identifiers, preventing other clients from keeping stale visuals.
- Server sync retries active looks during scene startup and sends a low-frequency heartbeat, while clients keep early apply/clear messages briefly if the target character entity has not spawned yet.
