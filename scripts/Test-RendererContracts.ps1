$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$renderer = Get-Content -LiteralPath (Join-Path $root "CSharp/Client/WardrobeVisualOverridePlugin.cs") -Raw
$session = Get-Content -LiteralPath (Join-Path $root "CSharp/Client/WardrobeRendering.cs") -Raw
$policy = Get-Content -LiteralPath (Join-Path $root "CSharp/Client/WardrobeFunctionalFashionFilters.cs") -Raw
$compatibilityProbe = Get-Content -LiteralPath (Join-Path $root "tools/CompatibilityProbe/Program.cs") -Raw
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
    "session.SuppressedEquipmentAnimations.Clear();",
    "session.SavedSlots = ParseSlotCsv(savedSlotsCsv);"
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
