# Compatibility contract

## Compatibility target (verified)

- Barotrauma stable: `1.13.4.0`
- Official source reference: [`a589d2cee3ff2214c99a7ea30c46f16a5406a01d`](https://github.com/FakeFishGames/Barotrauma/tree/a589d2cee3ff2214c99a7ea30c46f16a5406a01d)
- LuaCsForBarotrauma upstream reference: [`0d380afcd1feeb842c0c86290d46bcaf198cd5e4`](https://github.com/evilfactory/LuaCsForBarotrauma/tree/0d380afcd1feeb842c0c86290d46bcaf198cd5e4)
- C# target framework used by LuaCs: `.NET 8`

LuaCs is an upstream dependency, not an official Barotrauma API. Barotrauma's public modding guide does not document the private renderer seams needed by this mod, so the pinned official source and a runtime reflection probe are both release inputs.

The executable/API checks and in-game matrix target 1.13.4.0. After every applicable item in [TESTING.md](TESTING.md) was recorded as passing, `version.json` was promoted to `verified` and `filelist.xml` was updated to declare 1.13.4.0. Content-package metadata records that result; it is not a substitute for the underlying tests.

Pinned contracts used by the adapter:

- [Official 1.13.4.0 changelog](https://github.com/FakeFishGames/Barotrauma/blob/a589d2cee3ff2214c99a7ea30c46f16a5406a01d/Barotrauma/BarotraumaShared/changelog.txt#L1-L13)
- [Official `WearableSprite` construction and `Init(Character)` lifecycle](https://github.com/FakeFishGames/Barotrauma/blob/a589d2cee3ff2214c99a7ea30c46f16a5406a01d/Barotrauma/BarotraumaShared/SharedSource/Items/Components/Wearable.cs#L152-L210)
- [Official exact `Limb.Draw` signature](https://github.com/FakeFishGames/Barotrauma/blob/a589d2cee3ff2214c99a7ea30c46f16a5406a01d/Barotrauma/BarotraumaClient/ClientSource/Characters/Limb.cs#L729-L730)
- [Official content-package metadata guide](https://regalis11.github.io/BaroModDoc/Intro/ContentPackages.html)
- [LuaCs in-memory C# source loading](https://evilfactory.github.io/LuaCsForBarotrauma/cs-docs/html/md_manual_inmemorymod.html) and [LuaCs networking](https://evilfactory.github.io/LuaCsForBarotrauma/lua-docs/manual/networking/) (upstream LuaCs contracts, not official game APIs)

## Exact C# capability targets

Required renderer capabilities:

- `Limb.Draw(SpriteBatch, Camera, Color?, bool)`
- `Limb.DrawWearable(WearableSprite, float, SpriteBatch, Color, float, SpriteEffects)`
- `WearableSprite.Init(Character)` and readable initialization/resource properties

Optional capabilities:

- `AnimController.UpdateAnimations(float)`
- `AnimController.TryLoadTemporaryAnimation(StatusEffect.AnimLoadInfo, bool)`
- `StatusEffect.PlaySound(Entity, Hull, Vector2)`
- `StatusEffect.propertyConditionals`, `requiredItems`, and `playSoundOnRequiredItemFailure` for fail-open functional alarm classification
- `ItemComponent.PlaySound(ActionType, Character)`

Missing required targets disable the visual override without mutating character render state. Missing optional targets disable only their advertised capability and are visible through the readiness report.

Run the contract probe on a machine with the game installed:

```powershell
./scripts/Test-Compatibility.ps1 `
  -BarotraumaInstallDir "C:\Program Files (x86)\Steam\steamapps\common\Barotrauma" `
  -LuaCsPublicizedDir "C:\Program Files (x86)\Steam\steamapps\common\Barotrauma\Publicized" `
  -RequireOptional
```

## Network compatibility

Protocol 2 is used when both peers complete the v2 hello handshake. The six original v1 message names remain available in v0.5.0:

- Old client with v0.5.0 server: v1.
- v0.5.0 client with old server: v1 after the five-second hello timeout.
- v0.5.0 client with v0.5.0 server: v2.

The v1 bridge is scheduled for removal in v0.6.0. V2 state is revisioned; v1 remains best-effort compatibility and does not gain new positional fields.

## Release gates

1. Build the C# source against the installed 1.13.4.0 LuaCs Publicized assemblies with zero warnings and errors.
2. Run the exact API probe with optional capabilities required.
3. Run the renderer crash characterization contracts and executable client persistence probe.
4. Parse every Lua file using the MoonSharp assembly shipped with Barotrauma and run all pure/authority tests.
5. Run `python scripts/verify_package.py` and confirm the source-package/Git diff contains no generated outputs (ignored `artifacts/` build output may exist locally).
6. Complete isolated single-player/host/dedicated testing, then the representative `Limb.Draw` conflict set described in the release checklist.
7. Only after step 6 passes, set `declaredGameVersion` and `filelist.xml gameversion` to `1.13.4.0`, change `compatibilityStatus` to `verified`, and run `python scripts/verify_package.py --release`.

The `filelist.xml` `gameversion` value records the version actually verified; it is metadata, not proof of runtime compatibility.
