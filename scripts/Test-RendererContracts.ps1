param()

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$rendererPath = Join-Path $root "CSharp/Client/WardrobeVisualOverridePlugin.cs"
$sessionPath = Join-Path $root "CSharp/Client/WardrobeRendering.cs"
$renderer = Get-Content -LiteralPath $rendererPath -Raw
$session = Get-Content -LiteralPath $sessionPath -Raw
$allClientSource = $renderer + "`n" + $session

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)][string] $Text,
        [Parameter(Mandatory = $true)][string] $Expected,
        [Parameter(Mandatory = $true)][string] $Failure
    )
    if (-not $Text.Contains($Expected)) { throw $Failure }
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory = $true)][string] $Text,
        [Parameter(Mandatory = $true)][string] $Forbidden,
        [Parameter(Mandatory = $true)][string] $Failure
    )
    if ($Text.Contains($Forbidden)) { throw $Failure }
}

function Assert-Before {
    param(
        [Parameter(Mandatory = $true)][string] $Text,
        [Parameter(Mandatory = $true)][string] $First,
        [Parameter(Mandatory = $true)][string] $Second,
        [Parameter(Mandatory = $true)][string] $Failure
    )
    $firstIndex = $Text.IndexOf($First, [StringComparison]::Ordinal)
    $secondIndex = $Text.IndexOf($Second, [StringComparison]::Ordinal)
    if ($firstIndex -lt 0 -or $secondIndex -lt 0 -or $firstIndex -ge $secondIndex) {
        throw $Failure
    }
}

# Crash 1: prefab fallback previously leaked an uninitialized/shallow-cloned
# WearableSprite into Limb.Draw. Lock the official constructor + Init lifecycle and
# every member Limb.Draw dereferences before a descriptor can be committed.
Assert-Contains $session "if (!source.IsInitialized)" `
    "The source wearable must be initialized before its resolved runtime sprite is copied."
Assert-Contains $session "source.Init(character);" `
    "Prefab fallback must initialize the source wearable for the target character."
Assert-Contains $session "new WearableSprite(source.SourceElement, source.WearableComponent, source.Variant);" `
    "Prefab fallback must construct an independently owned WearableSprite."
Assert-Contains $session "ownedSprite.Init(character);" `
    "Prefab fallback must initialize its sprite for the target character."
Assert-Contains $session "clone = new Sprite(source);" `
    "Renderer-owned visuals must use Sprite(Sprite) to retain the resolved Override texture."
Assert-Contains $session "clone.SourceRect = source.SourceRect;" `
    "The resolved sprite source rectangle must be copied explicitly."
Assert-Contains $session "clone.RelativeOrigin = source.RelativeOrigin;" `
    "The resolved sprite relative origin must be copied explicitly."
Assert-Contains $session "clone.Origin = source.Origin;" `
    "The resolved sprite origin must be copied explicitly."
Assert-Contains $session "clone.Depth = source.Depth;" `
    "The resolved sprite depth must be copied explicitly."
Assert-Contains $session "clone.size = source.size;" `
    "The resolved sprite size must be copied explicitly."
Assert-Contains $session "clone.effects = source.effects;" `
    "The resolved sprite effects must be copied explicitly."
Assert-Contains $session "RemoveSprite(initializedSprite);" `
    "The temporary Sprite created by WearableSprite.Init must be released after replacement."
Assert-Before $session "CopyRuntimeVisualState(source, ownedSprite, character);" "if (!preserveMasks)" `
    "Wardrobe mask sanitization must run only after the full runtime visual state is copied."
$copyStart = $session.IndexOf("private static void CopyRuntimeVisualState", [StringComparison]::Ordinal)
$copyEnd = $session.IndexOf("private static string GetResolvedSpritePath", [StringComparison]::Ordinal)
if ($copyStart -lt 0 -or $copyEnd -le $copyStart) { throw "Could not isolate runtime visual copy path." }
$copyPath = $session.Substring($copyStart, $copyEnd - $copyStart)
Assert-NotContains $copyPath "LightComponent" `
    "Cosmetic sprite capture must not copy source light components."
Assert-NotContains $copyPath ".Components" `
    "Cosmetic sprite capture must not copy functional item components."
Assert-Contains $session "if (!Sprite.IsInitialized)" `
    "Descriptors must reject uninitialized wearable sprites."
Assert-Contains $session "if (Sprite.SourceElement == null)" `
    "Descriptors must reject missing source elements."
Assert-Contains $session "if (Sprite.Sprite == null)" `
    "Descriptors must reject missing render sprites."
Assert-NotContains $allClientSource ".MemberwiseClone(" `
    "Renderer source must never shallow-clone engine wearable resources."
Write-Host "PASS prefab-fallback-initialization"

# Crash 2: Limb.Draw calls Enumerable.Any(CanBeHiddenByItem); a null collection caused
# ArgumentNullException('source'). Validation must fail closed before injection.
Assert-Contains $session "if (Sprite.CanBeHiddenByItem == null)" `
    "Descriptors must reject a null CanBeHiddenByItem collection."
Assert-Contains $renderer "session.MarkInvalid(failure);" `
    "Descriptor construction failures must invalidate the staged session."
Assert-Contains $renderer "if (!staged.Validate(out error) || !HasFashionPayload(staged))" `
    "Atomic commit must validate the complete staged session."
Assert-Contains $renderer "current.Dispose();" `
    "The previous session may be disposed only after the staged session is installed."
Write-Host "PASS null-source-fail-closed"

# Crash 3: exceptions thrown by the base renderer or fallback DrawWearable must cross
# the Harmony finalizer only after the exact WearingItems/mask snapshots are restored.
Assert-Contains $renderer "ExceptionDispatchInfo.Capture(ex.InnerException).Throw();" `
    "Reflection-wrapped DrawWearable exceptions must be rethrown with their original stack."
Assert-Contains $renderer "wearingItems.AddRange(originalOrder);" `
    "Cleanup must restore the exact WearingItems snapshot."
Assert-Contains $renderer 'cleanupErrors.Add(new InvalidOperationException("Failed to restore wearable mask snapshot.", ex));' `
    "Mask restore failures must be observable."
Assert-Contains $renderer "return exception ?? cleanupException;" `
    "The original draw exception must win; cleanup failure must surface when it is the only failure."

$drawStart = $renderer.IndexOf("internal static void DrawMissingFashionSprites", [StringComparison]::Ordinal)
$drawEnd = $renderer.IndexOf("internal static void KeepFashionEffectsAlive", [StringComparison]::Ordinal)
if ($drawStart -lt 0 -or $drawEnd -le $drawStart) { throw "Could not isolate fallback draw path." }
$drawPath = $renderer.Substring($drawStart, $drawEnd - $drawStart)
Assert-Contains $drawPath "throw;" "Fallback draw exceptions must be rethrown into the Harmony finalizer."
Write-Host "PASS exception-restore-rethrow"

$characterDictionaryCount = ([regex]::Matches($allClientSource, "static readonly Dictionary<Character")).Count
if ($characterDictionaryCount -ne 1) {
    throw "Per-character renderer state must have exactly one dictionary aggregate; found $characterDictionaryCount."
}
Write-Host "PASS render-session-aggregate"

# Reuse is allowed only for the exact atomically committed character session.
Assert-Contains $session "public bool IsCommitted { get; private set; }" `
    "Render sessions must distinguish staged/direct captures from committed captures."
Assert-Contains $renderer "staged.MarkCommitted();" `
    "Atomic commit must mark the staged renderer session as reusable."
Assert-Contains $renderer "public static bool CanReuseCapturedFashion(Character character)" `
    "Lua must have a safe renderer-session reuse query."
Assert-Contains $renderer "!session.IsCommitted" `
    "Uncommitted renderer sessions must never be reused."
Assert-Contains $renderer "session.HasPendingCapture" `
    "Renderer sessions with pending transactions must never be reused."
Assert-Contains $renderer "!HasFashionPayload(session)" `
    "Renderer sessions without a fashion payload must never be reused."
Assert-Contains $renderer "return session.Validate(out _);" `
    "Invalid renderer sessions must never be reused."
Write-Host "PASS committed-session-reuse"

# An explicitly empty saved equipment slot must hide the real item before a
# same-type fashion sprite from another slot can be mistaken for its replacement.
$drawWearableStart = $renderer.IndexOf(
    "internal static bool TryOverrideDrawWearable(",
    [StringComparison]::Ordinal)
$drawWearableEnd = $renderer.IndexOf(
    "internal static LimbRenderTransaction BeginLimbDraw(",
    [StringComparison]::Ordinal)
if ($drawWearableStart -lt 0 -or $drawWearableEnd -le $drawWearableStart) {
    throw "Could not isolate DrawWearable override path."
}
$drawWearableOverride = $renderer.Substring(
    $drawWearableStart,
    $drawWearableEnd - $drawWearableStart)
Assert-Before $drawWearableOverride `
    "if (hideOriginalForEmptySavedSlot)" `
    "if (!TryGetFashionSprite(" `
    "Empty saved slots must win before matching fashion sprites from other equipment slots."
Write-Host "PASS empty-slot-priority"

# Attachment visibility is an independent draw-time policy. Force-show must win
# over force-hide, which in turn wins over the appearance item's XML auto mask.
Assert-Contains $renderer "public static bool SetAttachmentVisibility(" `
    "LuaCs must expose the four-layer attachment visibility API."
Assert-Contains $renderer "(forceHideMask & ~AttachmentVisibilityMask) != 0" `
    "Attachment visibility must reject unknown hide-mask bits."
Assert-Contains $renderer "(forceShowMask & ~AttachmentVisibilityMask) != 0" `
    "Attachment visibility must reject unknown show-mask bits."
Assert-Contains $renderer "(forceHideMask & forceShowMask) != 0" `
    "Attachment visibility must reject overlapping force-hide/show masks."
Assert-Contains $renderer "public static bool SetHideHair(Character character, bool hideHair)" `
    "The legacy SetHideHair LuaCs wrapper must remain available."

$visibilitySetterStart = $renderer.IndexOf(
    "public static bool SetAttachmentVisibility(",
    [StringComparison]::Ordinal)
$visibilitySetterEnd = $renderer.IndexOf(
    "public static bool ApplyFashionItemVisual(",
    [StringComparison]::Ordinal)
if ($visibilitySetterStart -lt 0 -or $visibilitySetterEnd -le $visibilitySetterStart) {
    throw "Could not isolate attachment visibility setter."
}
$visibilitySetter = $renderer.Substring(
    $visibilitySetterStart,
    $visibilitySetterEnd - $visibilitySetterStart)
Assert-NotContains $visibilitySetter "RefreshWearables(" `
    "Changing attachment visibility must not call Character.OnWearablesChanged()."
Assert-NotContains $visibilitySetter "OnWearablesChanged" `
    "Changing attachment visibility must not invoke the wearable rebuild path."

$hideAttachmentStart = $renderer.IndexOf(
    "private static bool ShouldHideAttachmentForFashion(",
    [StringComparison]::Ordinal)
$hideAttachmentEnd = $renderer.IndexOf(
    "private static string DescribeFashionHiddenTypes(",
    [StringComparison]::Ordinal)
if ($hideAttachmentStart -lt 0 -or $hideAttachmentEnd -le $hideAttachmentStart) {
    throw "Could not isolate attachment visibility draw policy."
}
$hideAttachmentPolicy = $renderer.Substring(
    $hideAttachmentStart,
    $hideAttachmentEnd - $hideAttachmentStart)
Assert-Before $hideAttachmentPolicy "session.ForceShowAttachmentMask" "session.ForceHideAttachmentMask" `
    "Force-show must be evaluated before force-hide."
Assert-Before $hideAttachmentPolicy "session.ForceHideAttachmentMask" "session.HiddenWearableTypes.Contains" `
    "Force-hide must be evaluated before the appearance item's XML auto mask."
foreach ($layer in @("WearableType.Hair", "WearableType.Beard", "WearableType.Moustache", "WearableType.FaceAttachment")) {
    Assert-Contains $renderer $layer "Attachment visibility mapping is missing $layer."
}
Write-Host "PASS attachment-visibility-priority"

# Functional alarms (oxygen low/empty, required-item failures, other conditional
# equipment warnings) must remain attached to the real item. Replaying them from a
# cosmetic session caused alarms to outlive unequip; suppressing them hid the alarm.
Assert-Contains $allClientSource "IsFunctionalEquipmentAlarm(statusEffect)" `
    "Status-effect sound capture and suppression must classify functional equipment alarms."
Assert-Contains $renderer "session.SuppressedEquipmentSounds.Remove(statusEffect);" `
    "A functional alarm encountered in suppression state must fail open to the original game sound."
Assert-Contains $renderer "if (!session.EffectPolicy.ShouldCaptureStatusSound(item, statusEffect)) { continue; }" `
    "Conditional equipment alarms must not be captured as cosmetic sounds."
Write-Host "PASS functional-equipment-alarm-lifecycle"
