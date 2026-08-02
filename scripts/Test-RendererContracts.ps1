$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$renderer = Get-Content -LiteralPath (Join-Path $root "CSharp/Client/WardrobeVisualOverridePlugin.cs") -Raw
$session = Get-Content -LiteralPath (Join-Path $root "CSharp/Client/WardrobeRendering.cs") -Raw
$policy = Get-Content -LiteralPath (Join-Path $root "CSharp/Client/WardrobeFunctionalFashionFilters.cs") -Raw
$compatibilityProbe = Get-Content -LiteralPath (Join-Path $root "tools/CompatibilityProbe/Program.cs") -Raw
$client = Get-Content -LiteralPath (Join-Path $root "Lua/WardrobeSwitcher.lua") -Raw
$all = $renderer + "`n" + $session + "`n" + $policy

function Assert-Contract([string] $name, [string] $source, [string[]] $required) {
    foreach ($pattern in $required) {
        if (-not $source.Contains($pattern)) { throw "$name is missing: $pattern" }
    }
    Write-Host "PASS $name"
}

function Get-Section([string] $source, [string] $start, [string] $end) {
    $startIndex = $source.IndexOf($start, [StringComparison]::Ordinal)
    $endIndex = $source.IndexOf($end, $startIndex + [Math]::Max(1, $start.Length), [StringComparison]::Ordinal)
    if ($startIndex -lt 0 -or $endIndex -le $startIndex) { throw "Could not isolate $start" }
    return $source.Substring($startIndex, $endIndex - $startIndex)
}

function Assert-Order([string] $name, [string] $source, [string[]] $patterns) {
    $previous = -1
    foreach ($pattern in $patterns) {
        $index = $source.IndexOf($pattern, $previous + 1, [StringComparison]::Ordinal)
        if ($index -le $previous) { throw "$name has missing or out-of-order token: $pattern" }
        $previous = $index
    }
    Write-Host "PASS $name"
}

$contracts = @(
    @{
        Name = "prefab-initialization"
        Source = $session
        Required = @(
            "source.Init(character);",
            "new WearableSprite(source.SourceElement, source.WearableComponent, source.Variant);",
            "ownedSprite.Init(character);",
            "clone = new Sprite(source);",
            "if (Sprite.CanBeHiddenByItem == null)"
        )
    },
    @{
        Name = "atomic-transaction"
        Source = $renderer
        Required = @(
            "if (!staged.Validate(out error) || !HasFashionPayload(staged))",
            "staged.MarkCommitted();",
            "current.Dispose();",
            "session.HasPendingCapture",
            "session.HasLiveItemSources",
            "return session.Validate(out _);"
        )
    },
    @{
        Name = "cleanup-and-exception-propagation"
        Source = $renderer
        Required = @(
            "wearingItems.AddRange(originalOrder);",
            "ExceptionDispatchInfo.Capture(ex.InnerException).Throw();",
            "return exception ?? cleanupException;"
        )
    },
    @{
        Name = "live-equipment-mask-transaction"
        Source = $renderer
        Required = @(
            ".Where(sprite => IsEquipmentSprite(sprite) && !session.TryGetDescriptor(sprite, out _))",
            "originalMasks[equipmentSprite] = new SpriteMaskState(equipmentSprite);",
            "if (equipmentSprite.HideWearablesOfType?.Count > 0)",
            "wearableTypesCacheChanged = true;",
            "ClearMask(equipmentSprite);",
            "limb.UpdateWearableTypesToHide();",
            "pair.Value.Restore(pair.Key);"
        )
    },
    @{
        Name = "live-equipment-hide-cache-compatibility"
        Source = $compatibilityProbe
        Required = @(
            'RequireMethod("Limb.UpdateWearableTypesToHide()", limb, "UpdateWearableTypesToHide",'
        )
    },
    @{
        Name = "fashion-footstep-transaction"
        Source = $renderer
        Required = @(
            'AccessTools.Method(typeof(Ragdoll), "PlayImpactSound", new[] { typeof(Limb) })',
            'PatchStates["Ragdoll.PlayImpactSound"] = new PatchState(required: false);',
            'public static bool SetUseFashionFootstepSounds(Character character, bool enabled)',
            '!session.UseFashionFootstepSounds',
            'originalOrder = new List<WearableSprite>(wearingItems);',
            'if (IsEquipmentSprite(wearingItems[index]))',
            'if (sprite.Limb == limb.type && !wearingItems.Contains(sprite))',
            'limb.WearingItems.AddRange(originalOrder);',
            'return exception ?? cleanupException;'
        )
    },
    @{
        Name = "fashion-footstep-compatibility-probe"
        Source = $compatibilityProbe
        Required = @(
            '"Limb.WearingItems",',
            'RequireMethod("Ragdoll.PlayImpactSound(Limb)", ragdoll, "PlayImpactSound",'
        )
    },
    @{
        Name = "physical-limb-guard"
        Source = $renderer
        Required = @(
            "private static bool SpriteBelongsToLimb(WearableSprite sprite, LimbType limbType)",
            "if (!SpriteBelongsToLimb(original, limb.type))",
            "if (!SpriteBelongsToLimb(wearable, limb.type)) { return; }"
        )
    },
    @{
        Name = "temporary-item-and-reuse"
        Source = $all
        Required = @(
            "tempItem.FreeID();",
            "tempItem.SpriteColor = new Color(packedColor.Value);",
            "public static bool CanReuseCapturedFashion(Character character)",
            "session.MarkLiveItemSource();",
            "if (item == null || item.Removed) { continue; }"
        )
    },
    @{
        Name = "visibility-validation"
        Source = $renderer
        Required = @(
            "public static bool SetAttachmentVisibility(",
            "(forceHideMask & ~AttachmentVisibilityMask) != 0",
            "(forceShowMask & ~AttachmentVisibilityMask) != 0",
            "(forceHideMask & forceShowMask) != 0",
            "public static bool SetHideHair(Character character, bool hideHair)"
        )
    },
    @{
        Name = "functional-alarm-lifecycle"
        Source = $all
        Required = @(
            "FashionEffectPolicy.IsFunctionalEquipmentAlarm(statusEffect)",
            "session.SuppressedEquipmentSounds.Remove(statusEffect);",
            "if (!FashionEffectPolicy.ShouldCaptureStatusSound(statusEffect)) { continue; }",
            "if (!FashionEffectPolicy.ShouldCaptureStatusEffect(statusEffect)) { continue; }",
            "internal static bool IsStateDependentStatusEffect(StatusEffect statusEffect)",
            "OnlyInsideField",
            "OnlyOutsideField",
            "TargetIdentifiersField",
            "TargetItemComponentField"
        )
    },
    @{
        Name = "functional-alarm-compatibility-probe"
        Source = $compatibilityProbe
        Required = @(
            'RequireField("StatusEffect.OnlyInside", statusEffect, "OnlyInside", optional: true);',
            'RequireField("StatusEffect.OnlyOutside", statusEffect, "OnlyOutside", optional: true);',
            'RequireField("StatusEffect.TargetIdentifiers", statusEffect, "TargetIdentifiers", optional: true);',
            'RequireField("StatusEffect.TargetItemComponent", statusEffect, "TargetItemComponent", optional: true);'
        )
    },
    @{
        Name = "component-sound-action-lifecycle"
        Source = $all
        Required = @(
            "return actionType == ActionType.Always || actionType == ActionType.OnWearing;",
            "FashionEffectPolicy.ShouldKeepComponentLoopAlive(fashionSound.ActionType)",
            "fashionSound.Component == null || fashionSound.ActionType != actionType"
        )
    },
    @{
        Name = "xds-appendage-compatibility"
        Source = $renderer
        Required = @(
            "internal static bool ShouldSuppressEquipmentAppendage(Limb limb)",
            "session.SavedSlots.Contains(InvSlotType.Bag)",
            "session.EmptySlots.Contains(InvSlotType.Bag)",
            "GetItemInLimbSlot(InvSlotType.Bag)",
            'private const string Xds01EngineIdentifier = "Wf_New_XDS01_Engine";',
            'private const string Xds01EngineAfflictionIdentifier = "XDS01engine";',
            "private static bool EnsureXdsFashionAppendage(Character character, RenderSession session)",
            "AfflictionHusk.AttachHuskAppendage(character, huskPrefab, huskedSpeciesName)",
            "session.SetOwnedAppendages(appendages);",
            "session.OwnsAppendage(limb)",
            "session.RemoveOwnedAppendages();",
            "limb.type != LimbType.None",
            'private const string Xds01AppendageTexture = "Wf_New_XDS01_Engine_limb.png";'
        )
    },
    @{
        Name = "movement-animation-source"
        Source = $all
        Required = @(
            "public bool UseFashionMovementAnimations { get; set; } = true;",
            "public static bool SetUseFashionMovementAnimations(Character character, bool enabled)",
            "session.UseFashionMovementAnimations = enabled;",
            "if (!session.UseFashionMovementAnimations) { return true; }",
            "if (!session.UseFashionMovementAnimations &&",
            "FashionEffectPolicy.IsMovementAnimation(animationInfo)",
            "public HashSet<object> SuppressedEquipmentAnimations { get; }",
            "RegisterSuppressedEquipmentAnimations(character, item);",
            "session.SuppressedEquipmentAnimations.Contains(animationInfo)",
            "FashionEffectPolicy.ShouldSuppressEquipmentAnimation(item, animationInfo)"
        )
    }
)

foreach ($contract in $contracts) {
    Assert-Contract $contract.Name $contract.Source $contract.Required
}

if ($all.Contains(".MemberwiseClone(")) { throw "Renderer resources must not be shallow-cloned." }
if ($renderer.Contains("CharacterHealth.ApplyAffliction")) {
    throw "Experimental XDS rendering must not apply gameplay afflictions."
}
if ($renderer.Contains("for (int pass = 0; pass < 2; pass++)")) {
    throw "Fashion component sound replacement must not fall back across ActionType values."
}
foreach ($identifier in @("cultistrobes", "zealotrobes")) {
    if ($renderer.Contains($identifier)) {
        throw "Renderer compatibility must not hard-code Workshop item identifier: $identifier"
    }
}

$customNoneLimb = Get-Section $renderer `
    "private static bool IsFashionSpriteCompatibleWithLimb(" `
    "private static LimbType GetFallbackAnchorLimb("
Assert-Contract "workshop-left-breast-none-limb-binding" $customNoneLimb @(
    'sprite.Limb != LimbType.None',
    '"/3156077899/"',
    'name.EndsWith("LeftBreast", StringComparison.OrdinalIgnoreCase)',
    'limb.type == LimbType.None && limb.Params?.ID == 17'
)
if ($customNoneLimb.Contains("descriptor.SourceIdentifier") -or
    $customNoneLimb.Contains("exo_milker2.png")) {
    throw "Workshop left-breast routing must not be limited to the original clothing item or texture."
}

$drawWearableCompatibility = Get-Section $renderer `
    "internal static bool TryOverrideDrawWearable(" `
    "internal static LimbRenderTransaction BeginLimbDraw("
Assert-Order "workshop-left-breast-draw-guard" $drawWearableCompatibility @(
    "IsFashionSpriteCompatibleWithLimb(session, original, limb)",
    "transaction.DrawnSprites.Add(original);",
    "skipOriginal = true;",
    "if (transaction.IsDrawingStoredFashion)"
)

$missingFashionSprites = Get-Section $renderer `
    "internal static void DrawMissingFashionSprites(" `
    "private static void DrawFashionWearable("
Assert-Order "workshop-left-breast-fallback-guard" $missingFashionSprites @(
    "WearableSprite sprite = descriptor.Sprite;",
    "IsFashionSpriteCompatibleWithLimb(session, sprite, limb)",
    "drawnSprites.Add(sprite);",
    "DrawFashionWearable(limb, transaction, sprite"
)

$fashionInjection = Get-Section $renderer `
    "public void Begin(RenderSession renderSession)" `
    "public void Cleanup()"
Assert-Order "workshop-left-breast-injection-guard" $fashionInjection @(
    "EnumerateFashionSpritesForLimb(session.SpritesBySlot, limb.type)",
    "IsFashionSpriteCompatibleWithLimb(session, descriptor.Sprite, limb)",
    "wearingItems.Add(descriptor.Sprite);",
    "SortWearablesForDraw(wearingItems);"
)

$visibility = Get-Section $renderer `
    "private static bool ShouldHideAttachmentForFashion(" `
    "private static string DescribeFashionHiddenTypes("
Assert-Order "visibility-precedence" $visibility @(
    "session.ForceShowAttachmentMask",
    "session.ForceHideAttachmentMask",
    "session.HiddenWearableTypes.Contains"
)

$maskBegin = Get-Section $renderer `
    "public void Begin(RenderSession renderSession)" `
    "public void Cleanup()"
Assert-Order "live-equipment-hide-cache-begin" $maskBegin @(
    "originalMasks[equipmentSprite] = new SpriteMaskState(equipmentSprite);",
    "ClearMask(equipmentSprite);",
    "limb.UpdateWearableTypesToHide();",
    "List<FashionSpriteDescriptor> descriptors"
)

$maskCleanup = Get-Section $renderer `
    "public void Cleanup()" `
    "private sealed class PatchState"
Assert-Order "live-equipment-hide-cache-cleanup" $maskCleanup @(
    "wearingItems.AddRange(originalOrder);",
    "pair.Value.Restore(pair.Key);",
    "limb.UpdateWearableTypesToHide();",
    "session?.ExitDraw(limb);"
)

$equipmentRegistration = Get-Section $renderer `
    "public static bool ApplyFashionItemVisual(" `
    "public static bool RemoveFashionItemVisual("
if ($equipmentRegistration.Contains("ActivateFashionVisual(character)")) {
    throw "Equipment registration must not activate the renderer once per equipped item."
}
Assert-Contract "equipment-registration-batch" $equipmentRegistration @(
    "RegisterSuppressedEquipmentAnimations(character, item);",
    "RegisterSuppressedEquipmentSounds(character, item);",
    "RegisterSuppressedEquipmentComponentSounds(character, item);",
    "return true;"
)

$equipmentUnregistration = Get-Section $renderer `
    "public static bool RemoveFashionItemVisual(" `
    "public static bool ActivateFashionVisual("
Assert-Contract "equipment-unregistration" $equipmentUnregistration @(
    "session.SuppressedEquipmentComponentSounds.Remove(component);",
    "session.SuppressedEquipmentSounds.Remove(statusEffect);",
    "session.SuppressedEquipmentAnimations.Remove(animationInfo);",
    "return true;"
)

$activation = Get-Section $renderer `
    "public static bool ActivateFashionVisual(" `
    "private static bool EnsureXdsFashionAppendage("
Assert-Order "active-renderer-fast-path" $activation @(
    "RenderSessions.TryGetValue(character, out RenderSession session)",
    "if (session.IsActive) { return true; }",
    "session.Validate(out error)"
)
if ($activation.Contains("RefreshWearables(character)")) {
    throw "Draw-only activation must not rescan Character wearable stats."
}

$drawBegin = Get-Section $renderer `
    "internal static LimbRenderTransaction BeginLimbDraw(" `
    "internal static bool ShouldSuppressEquipmentAppendage("
Assert-Order "inactive-render-allocation-guard" $drawBegin @(
    "RenderSessions.TryGetValue(limb.character, out RenderSession session)",
    "!session.IsActive",
    "!session.IsValid",
    "!HasCapability(""renderer"")",
    "new LimbRenderTransaction(limb)"
)
if ($drawBegin.Contains("session.Validate(")) {
    throw "Every Limb.Draw must not revalidate the complete renderer session."
}

$equipmentRefresh = Get-Section $client `
    "function Helpers.refreshActiveLookIfNeeded(" `
    "function Helpers.autoApplySavedLookIfNeeded("
Assert-Order "local-equipment-refresh" $equipmentRefresh @(
    "Helpers.equipmentSignature(character)",
    "Helpers.applyCapturedFashionToCharacterEquipment(",
    "currentLegacyLook()",
    "false,",
    "lastEquipmentSignature = signature"
)
if ($equipmentRefresh.Contains("applyFashionToCurrentEquipment") -or
    $equipmentRefresh.Contains("dispatchReducer")) {
    throw "Equipment-only refresh must not persist or send a wardrobe Apply command."
}

$equipmentBatch = Get-Section $client `
    "function Helpers.applyCapturedFashionToCharacterEquipment(" `
    "function Helpers.applyNetworkLook("
Assert-Order "multi-slot-equipment-dedupe" $equipmentBatch @(
    "local seenEquippedItems = {}",
    "local seenEquippedItemIds = {}",
    "seenEquippedItemIds[equippedId]",
    "seenEquippedItems[equipped] = true",
    "Helpers.applyVisualOverrideToItem(",
    "Helpers.activateFashionVisual(character)"
)

$equipmentHooks = Get-Section $client `
    'Hook.Add("item.equip"' `
    'Hook.Add("character.created"'
Assert-Order "observer-equipment-effect-lifecycle" $equipmentHooks @(
    "Helpers.isManagedEquippedItem(character, item)",
    "Helpers.applyVisualOverrideToItem(character, item, false)",
    'Hook.Add("item.unequip"',
    "Helpers.removeVisualOverrideFromItem(character, item)"
)

$fallback = Get-Section $renderer `
    "tempItem = new Item(prefab" `
    "if (!succeeded)"
Assert-Order "temporary-item-id-and-color" $fallback @(
    "tempItem.FreeID();",
    "tempItem.SpriteColor = new Color(packedColor.Value);",
    "CaptureFashionItemCore(character, tempItem"
)

$temporaryAnimation = Get-Section $renderer `
    "internal static bool ShouldLoadTemporaryAnimation(" `
    "private static void KeepFashionAnimationsAlive("
Assert-Order "exact-equipment-animation-suppression" $temporaryAnimation @(
    "if (!session.UseFashionMovementAnimations) { return true; }",
    "session.SuppressedEquipmentAnimations.Contains(animationInfo)",
    "session.FashionAnimations.Count > 0",
    "FashionEffectPolicy.IsLargeEquipmentMovementAnimation(animationInfo)"
)

$fashionAnimations = Get-Section $renderer `
    "private static void KeepFashionAnimationsAlive(" `
    "private static void KeepFashionSoundsAlive("
Assert-Order "movement-toggle-scope" $fashionAnimations @(
    "foreach (object animationInfo in session.FashionAnimations)",
    "if (!session.UseFashionMovementAnimations &&",
    "FashionEffectPolicy.IsMovementAnimation(animationInfo)",
    "TryLoadTemporaryAnimationMethod.Invoke"
)

$restoreLifecycle = Get-Section $renderer `
    "public static void RestoreItemVisuals()" `
    "public static void ClearCharacter("
Assert-Order "equipment-animation-restore-lifecycle" $restoreLifecycle @(
    "public static void RestoreItemVisuals()",
    "session.SuppressedEquipmentAnimations.Clear();",
    "public static void RestoreCharacterItemVisuals(",
    "session.SuppressedEquipmentAnimations.Clear();"
)

$slotRefresh = Get-Section $renderer `
    "public static bool SetFashionSlots(" `
    "public static bool SetAttachmentVisibility("
Assert-Order "equipment-animation-rescan-lifecycle" $slotRefresh @(
    "RenderSession session = GetCaptureSession(character);",
    "HashSet<InvSlotType> savedSlots = ParseSlotCsv(savedSlotsCsv);",
    "session.SuppressedEquipmentAnimations.Clear();",
    "session.SuppressedEquipmentSounds.Clear();",
    "session.SuppressedEquipmentComponentSounds.Clear();",
    "session.SavedSlots = savedSlots;"
)

$xdsAppendage = Get-Section $renderer `
    "private static bool EnsureXdsFashionAppendage(Character character, RenderSession session)" `
    "internal static bool TryOverrideDrawWearable("
Assert-Order "xds-experimental-appendage-lifecycle" $xdsAppendage @(
    "AfflictionHusk.AttachHuskAppendage(character, huskPrefab, huskedSpeciesName);",
    "appendages.Count != Xds01ExpectedAppendageLimbCount",
    "session.SetOwnedAppendages(appendages);",
    "return true;"
)

$limbDrawPrefix = Get-Section $renderer `
    "private static bool Prefix(Limb __instance, out VisualOverride.LimbRenderTransaction __state)" `
    "private static void Postfix("
Assert-Order "appendage-check-before-render-transaction" $limbDrawPrefix @(
    "ShouldSuppressEquipmentAppendage(__instance)",
    "return false;",
    "BeginLimbDraw(__instance)"
)
