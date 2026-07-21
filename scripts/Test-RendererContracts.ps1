param()

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
            "public static bool CanReuseCapturedFashion(Character character)",
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
    }
)

foreach ($contract in $contracts) {
    Assert-Contract $contract.Name $contract.Source $contract.Required
}

if ($all.Contains(".MemberwiseClone(")) { throw "Renderer resources must not be shallow-cloned." }

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
Assert-Order "temporary-item-id-release" $fallback @("tempItem.FreeID();", "CaptureFashionItemCore(character, tempItem")
