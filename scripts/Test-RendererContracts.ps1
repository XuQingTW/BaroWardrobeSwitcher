$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$renderer = Get-Content -LiteralPath (Join-Path $root "CSharp/Client/WardrobeVisualOverridePlugin.cs") -Raw
$session = Get-Content -LiteralPath (Join-Path $root "CSharp/Client/WardrobeRendering.cs") -Raw
$all = $renderer + "`n" + $session

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
            "ClearMask(equipmentSprite);",
            "pair.Value.Restore(pair.Key);"
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
            "if (!FashionEffectPolicy.ShouldCaptureStatusSound(statusEffect)) { continue; }"
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
            "!session.UseFashionMovementAnimations ||",
            "session.FashionAnimations.Count == 0"
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

$visibility = Get-Section $renderer `
    "private static bool ShouldHideAttachmentForFashion(" `
    "private static string DescribeFashionHiddenTypes("
Assert-Order "visibility-precedence" $visibility @(
    "session.ForceShowAttachmentMask",
    "session.ForceHideAttachmentMask",
    "session.HiddenWearableTypes.Contains"
)

$fallback = Get-Section $renderer `
    "tempItem = new Item(prefab" `
    "if (!succeeded)"
Assert-Order "temporary-item-id-and-color" $fallback @(
    "tempItem.FreeID();",
    "tempItem.SpriteColor = new Color(packedColor.Value);",
    "CaptureFashionItemCore(character, tempItem"
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
