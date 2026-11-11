using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Barotrauma;
using Barotrauma.Items.Components;
using Barotrauma.LuaCs;
using Barotrauma.LuaCs.Data;
using HarmonyLib;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using LuaCsLogger = BaroWardrobeSwitcher.WardrobeFileLogger;

namespace BaroWardrobeSwitcher
{
    public static partial class VisualOverride
    {

        private static IEnumerable<FashionSpriteDescriptor> EnumerateFashionSpritesForLimb(
            RenderSession session,
            LimbType limbType)
        {
            return session.SpritesBySlot
                .Where(pair =>
                    pair.Value != null &&
                    (pair.Key.Item2 == limbType || pair.Key.Item2 == LimbType.None))
                .SelectMany(pair => pair.Value
                    .Where(descriptor => descriptor?.Sprite != null && SpriteBelongsToLimb(session, descriptor.Sprite, limbType)))
                .OrderBy(GetFashionLayerSortKey)
                .ThenByDescending(descriptor => descriptor.Sprite?.Sprite?.Depth ?? 0.0f);
        }

        private static void SortWearablesForDraw(List<WearableSprite> wearingItems)
        {
            if (wearingItems == null) { return; }
            // ponytail: wearable lists are small; keep this stable in-place sort until
            // profiling shows a pooled O(n log n) sorter would beat its zero allocations.
            for (int index = 1; index < wearingItems.Count; index++)
            {
                WearableSprite current = wearingItems[index];
                int insertionIndex = index - 1;
                while (insertionIndex >= 0 && CompareWearablesForDraw(wearingItems[insertionIndex], current) > 0)
                {
                    wearingItems[insertionIndex + 1] = wearingItems[insertionIndex];
                    insertionIndex--;
                }
                wearingItems[insertionIndex + 1] = current;
            }
        }

        private static int CompareWearablesForDraw(WearableSprite left, WearableSprite right)
        {
            int layerComparison = GetFashionLayerSortKey(left).CompareTo(GetFashionLayerSortKey(right));
            if (layerComparison != 0) { return layerComparison; }
            float leftDepth = left?.Sprite?.Depth ?? 0.0f;
            float rightDepth = right?.Sprite?.Depth ?? 0.0f;
            return rightDepth.CompareTo(leftDepth);
        }

        private static int GetFashionLayerSortKey(WearableSprite sprite)
        {
            if (sprite == null) { return 0; }
            if (sprite.WearableComponent?.AllowedSlots == null) { return 1; }
            if (SlotContains(sprite, InvSlotType.Bag)) { return 2; }
            if (SlotContains(sprite, InvSlotType.HealthInterface)) { return 3; }
            if (SlotContains(sprite, InvSlotType.InnerClothes)) { return 4; }
            if (IsHeadSlotSprite(sprite)) { return 5; }
            if (SlotContains(sprite, InvSlotType.OuterClothes)) { return 6; }
            return 5;
        }

        private static int GetFashionLayerSortKey(FashionSpriteDescriptor descriptor)
        {
            if (descriptor == null) { return 0; }
            if (descriptor.AllowedSlots.Contains(InvSlotType.Bag)) { return 2; }
            if (descriptor.AllowedSlots.Contains(InvSlotType.HealthInterface)) { return 3; }
            if (descriptor.AllowedSlots.Contains(InvSlotType.InnerClothes)) { return 4; }
            if (descriptor.AllowedSlots.Contains(InvSlotType.Head) || descriptor.AllowedSlots.Contains(InvSlotType.Headset)) { return 5; }
            if (descriptor.AllowedSlots.Contains(InvSlotType.OuterClothes)) { return 6; }
            return 5;
        }

        private static bool UsesRecessedFashionLayer(FashionSpriteDescriptor descriptor)
        {
            return descriptor != null &&
                   (descriptor.AllowedSlots.Contains(InvSlotType.Bag) ||
                    descriptor.AllowedSlots.Contains(InvSlotType.HealthInterface));
        }

        private static string GetFashionLayerName(WearableSprite sprite)
        {
            if (sprite == null) { return "nil"; }
            if (SlotContains(sprite, InvSlotType.Bag)) { return "bag-recessed"; }
            if (SlotContains(sprite, InvSlotType.HealthInterface)) { return "health-recessed"; }
            if (SlotContains(sprite, InvSlotType.InnerClothes)) { return "inner"; }
            if (IsHeadSlotSprite(sprite)) { return "head"; }
            if (SlotContains(sprite, InvSlotType.OuterClothes)) { return "outer"; }
            return "default";
        }

        private static bool IsHeadSlotSprite(WearableSprite sprite)
        {
            return SlotContains(sprite, InvSlotType.Head) ||
                   SlotContains(sprite, InvSlotType.Headset);
        }

        private static bool SlotContains(WearableSprite sprite, InvSlotType slot)
        {
            return sprite?.WearableComponent?.AllowedSlots != null &&
                   sprite.WearableComponent.AllowedSlots.Contains(slot);
        }

        private static bool SpriteBelongsToLimb(RenderSession session, WearableSprite sprite, LimbType limbType)
        {
            if (sprite == null) { return false; }
            // The initialized sprite limb is authoritative. An explicit None is a
            // real custom-ragdoll binding; only a legacy unbound None uses a slot anchor.
            bool hasExplicitLimbBinding = session != null && session.TryGetDescriptor(sprite, out FashionSpriteDescriptor descriptor)
                ? descriptor.HasExplicitLimbBinding
                : sprite.SourceElement?.GetAttribute("limb") != null;
            if (sprite.Limb != LimbType.None || hasExplicitLimbBinding)
            {
                return sprite.Limb == limbType;
            }
            return GetFallbackAnchorLimb(sprite) == limbType;
        }

        private static bool IsFashionSpriteCompatibleWithLimb(
            RenderSession session,
            WearableSprite sprite,
            Limb limb)
        {
            if (session == null || sprite == null || limb == null || sprite.Limb != LimbType.None ||
                !session.TryGetDescriptor(sprite, out FashionSpriteDescriptor descriptor))
            {
                return true;
            }

            if (!descriptor.UsesLeftBreastNoneLimbCompatibility)
            {
                return true;
            }

            return limb.type == LimbType.None && limb.Params?.ID == 17;
        }

        private static LimbType GetFallbackAnchorLimb(WearableSprite sprite)
        {
            Wearable wearable = sprite?.WearableComponent;
            if (wearable?.AllowedSlots == null) { return LimbType.None; }
            if (wearable.AllowedSlots.Contains(InvSlotType.Head) ||
                wearable.AllowedSlots.Contains(InvSlotType.Headset))
            {
                return LimbType.Head;
            }
            if (wearable.AllowedSlots.Contains(InvSlotType.InnerClothes) ||
                wearable.AllowedSlots.Contains(InvSlotType.OuterClothes) ||
                wearable.AllowedSlots.Contains(InvSlotType.Bag) ||
                wearable.AllowedSlots.Contains(InvSlotType.HealthInterface))
            {
                return LimbType.Torso;
            }
            return LimbType.None;
        }

        private static object BoostFashionAnimationPriority(object animationInfo)
        {
            if (animationInfo == null) { return null; }
            Type animationInfoType = animationInfo.GetType();
            try
            {
                PropertyInfo typeProperty = animationInfoType.GetProperty("Type");
                PropertyInfo fileProperty = animationInfoType.GetProperty("File");
                PropertyInfo priorityProperty = animationInfoType.GetProperty("Priority");
                PropertyInfo expectedSpeciesProperty = animationInfoType.GetProperty("ExpectedSpeciesNames");
                ConstructorInfo constructor = animationInfoType.GetConstructors()
                    .FirstOrDefault(ctor => ctor.GetParameters().Length == 4);
                if (typeProperty == null || fileProperty == null || priorityProperty == null || expectedSpeciesProperty == null || constructor == null)
                {
                    return animationInfo;
                }

                float priority = Convert.ToSingle(priorityProperty.GetValue(animationInfo));
                return constructor.Invoke(new[]
                {
                    typeProperty.GetValue(animationInfo),
                    fileProperty.GetValue(animationInfo),
                    priority + FashionAnimationPriorityBoost,
                    expectedSpeciesProperty.GetValue(animationInfo)
                });
            }
            catch (Exception ex)
            {
                LogAnimationError($"Failed to boost fashion animation priority: {ex.GetType().Name}: {ex.Message}");
                return animationInfo;
            }
        }

        private static void LogVirtualDrawError(string message)
        {
            if (virtualDrawErrorLogCount >= 6) { return; }
            virtualDrawErrorLogCount++;
            LuaCsLogger.Log($"[Baro Wardrobe Switcher] {message}");
        }

        private static void LogAnimationError(string message)
        {
            if (animationOverrideErrorLogCount >= 6) { return; }
            animationOverrideErrorLogCount++;
            LuaCsLogger.Log($"[Baro Wardrobe Switcher] {message}");
        }

        private static void LogSoundError(string message)
        {
            if (soundOverrideErrorLogCount >= 6) { return; }
            soundOverrideErrorLogCount++;
            LuaCsLogger.Log($"[Baro Wardrobe Switcher] {message}");
        }

        private static bool IsEquipmentSprite(WearableSprite sprite)
        {
            return sprite != null && sprite.Type == WearableType.Item;
        }

        private static HashSet<InvSlotType> ParseSlotCsv(string slotsCsv)
        {
            HashSet<InvSlotType> slots = new HashSet<InvSlotType>();
            if (string.IsNullOrWhiteSpace(slotsCsv)) { return slots; }

            foreach (string part in slotsCsv.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries))
            {
                string slotName = part.Trim();
                if (Enum.TryParse(slotName, true, out InvSlotType slotType))
                {
                    slots.Add(slotType);
                }
            }
            return slots;
        }

        private static bool ShouldHideOriginalForEmptySavedSlot(Character character, WearableSprite original)
        {
            if (character == null || original?.WearableComponent?.AllowedSlots == null) { return false; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session) || session.EmptySlots.Count == 0)
            {
                return false;
            }

            foreach (InvSlotType slot in original.WearableComponent.AllowedSlots)
            {
                if (session.EmptySlots.Contains(slot)) { return true; }
            }
            return false;
        }

        private static bool ShouldDrawOriginalForEmptySavedSlot(Character character, WearableSprite original)
        {
            if (character == null || GetHideEmptySlotEquipment() ||
                !RenderSessions.TryGetValue(character, out RenderSession session) || session.ForceHideEmptySlots)
            {
                return false;
            }
            return ShouldHideOriginalForEmptySavedSlot(character, original) &&
                   !ShouldHideOriginalForSavedSlot(character, original);
        }

        private static bool ShouldHideFashionBehindVisibleEquipment(Limb limb)
        {
            if (limb?.WearingItems == null) { return false; }
            foreach (WearableSprite equipmentSprite in limb.WearingItems)
            {
                if (!IsEquipmentSprite(equipmentSprite) ||
                    !equipmentSprite.HideLimb ||
                    !equipmentSprite.HideOtherWearables ||
                    !ShouldDrawOriginalForEmptySavedSlot(limb.character, equipmentSprite))
                {
                    continue;
                }
                return true;
            }
            return false;
        }

        private static void CaptureFashionHiddenWearableTypes(RenderSession session, WearableSprite sprite)
        {
            if (session == null || sprite?.HideWearablesOfType == null || sprite.HideWearablesOfType.Count == 0) { return; }
            foreach (WearableType hiddenType in sprite.HideWearablesOfType)
            {
                if (!FashionHideableAttachmentTypes.Contains(hiddenType)) { continue; }
                session.HiddenWearableTypes.Add(hiddenType);
            }
        }

        private static bool ShouldHideAttachmentForFashion(Character character, WearableSprite original)
        {
            if (character == null || original == null) { return false; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session) ||
                !AttachmentBits.TryGetValue(original.Type, out int attachmentBit))
            {
                return false;
            }
            if ((session.ForceShowAttachmentMask & attachmentBit) != 0)
            {
                return false;
            }
            if ((session.ForceHideAttachmentMask & attachmentBit) != 0)
            {
                return true;
            }
            return session.HiddenWearableTypes.Contains(original.Type);
        }

        private static string DescribeFashionHiddenTypes(Character character)
        {
            if (character == null ||
                !RenderSessions.TryGetValue(character, out RenderSession session) ||
                session.HiddenWearableTypes.Count == 0)
            {
                return "none";
            }
            return string.Join(",", session.HiddenWearableTypes.Select(type => type.ToString()).OrderBy(name => name));
        }

        private static bool ShouldHideOriginalForSavedSlot(Character character, WearableSprite original)
        {
            if (character == null || original?.WearableComponent?.AllowedSlots == null) { return false; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session) || session.SavedSlots.Count == 0)
            {
                return false;
            }

            foreach (InvSlotType slot in original.WearableComponent.AllowedSlots)
            {
                if (session.SavedSlots.Contains(slot)) { return true; }
            }
            return false;
        }

        private static string DescribeSavedSlots(Character character)
        {
            return RenderSessions.TryGetValue(character, out RenderSession session)
                ? DescribeSlotSet(session.SavedSlots)
                : "none";
        }

        private static string DescribeEmptySlots(Character character)
        {
            return RenderSessions.TryGetValue(character, out RenderSession session)
                ? DescribeSlotSet(session.EmptySlots)
                : "none";
        }

        private static string DescribeSlotSet(HashSet<InvSlotType> slots)
        {
            if (slots == null || slots.Count == 0)
            {
                return "none";
            }
            return string.Join(",", slots.Select(slot => slot.ToString()).OrderBy(slot => slot));
        }

        private static bool NeedsMaskClear(WearableSprite sprite)
        {
            return sprite != null &&
                   (sprite.HideLimb ||
                    sprite.HideWearablesOfType?.Count > 0 ||
                    sprite.ObscureOtherWearables != WearableSprite.ObscuringMode.None ||
                    sprite.CanBeHiddenByOtherWearables);
        }

        private static void ClearMask(WearableSprite sprite, List<WearableType> emptyHideWearablesOfType)
        {
            if (sprite == null) { return; }
            if (sprite.HideLimb) { sprite.HideLimb = false; }
            if (sprite.HideWearablesOfType?.Count > 0)
            {
                sprite.HideWearablesOfType = emptyHideWearablesOfType;
            }
            if (sprite.ObscureOtherWearables != WearableSprite.ObscuringMode.None)
            {
                sprite.ObscureOtherWearables = WearableSprite.ObscuringMode.None;
            }
            if (sprite.CanBeHiddenByOtherWearables) { sprite.CanBeHiddenByOtherWearables = false; }
        }


        private static bool IsCharacterStale(Character character)
        {
            if (character == null) { return true; }
            if (CharacterRemovedProperty == null) { return false; }
            try
            {
                object removed = CharacterRemovedProperty.GetValue(character);
                return removed is bool removedValue && removedValue;
            }
            catch
            {
                return false;
            }
        }

        private static void RefreshWearables(Character character)
        {
            if (character == null) { return; }
            try
            {
                OnWearablesChangedMethod?.Invoke(character, null);
            }
            catch (Exception ex)
            {
                LuaCsLogger.Log($"[Baro Wardrobe Switcher] Failed to refresh wearables: {ex.GetType().Name}: {ex.Message}");
            }
        }

        internal static bool TryGetFashionSprite(
            Character character,
            WearableType type,
            LimbType limbType,
            HashSet<WearableSprite> drawnSprites,
            out WearableSprite sprite,
            out bool alreadyDrawn)
        {
            sprite = null;
            alreadyDrawn = false;
            if (character == null) { return false; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session))
            {
                return false;
            }
            if (TryGetFashionSpriteFromList(
                    session,
                    session.SpritesBySlot.TryGetValue((type, limbType), out List<FashionSpriteDescriptor> exactSprites)
                        ? exactSprites
                        : null,
                    limbType,
                    drawnSprites,
                    ref alreadyDrawn,
                    out sprite))
            {
                return true;
            }
            return limbType != LimbType.None &&
                   TryGetFashionSpriteFromList(
                       session,
                       session.SpritesBySlot.TryGetValue((type, LimbType.None), out List<FashionSpriteDescriptor> wildcardSprites)
                           ? wildcardSprites
                           : null,
                       limbType,
                       drawnSprites,
                       ref alreadyDrawn,
                       out sprite);
        }

        private static bool TryGetFashionSpriteFromList(
            RenderSession session,
            List<FashionSpriteDescriptor> descriptors,
            LimbType limbType,
            HashSet<WearableSprite> drawnSprites,
            ref bool alreadyDrawn,
            out WearableSprite sprite)
        {
            sprite = null;
            if (descriptors == null) { return false; }
            for (int index = 0; index < descriptors.Count; index++)
            {
                WearableSprite candidate = descriptors[index]?.Sprite;
                if (candidate == null || !SpriteBelongsToLimb(session, candidate, limbType)) { continue; }
                if (drawnSprites != null && drawnSprites.Contains(candidate))
                {
                    alreadyDrawn = true;
                    continue;
                }
                sprite = candidate;
                return true;
            }
            return false;
        }

        private static string DescribeFashionSprites(Character character)
        {
            if (character == null) { return "character=nil"; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session) ||
                session.SpritesBySlot.Count == 0)
            {
                return "none";
            }
            return string.Join(";",
                session.SpritesBySlot
                    .OrderBy(pair => pair.Key.Item2.ToString())
                    .ThenBy(pair => pair.Key.Item1.ToString())
                    .Select(pair => pair.Key.Item2 + "/" + pair.Key.Item1 + "=" + (pair.Value?.Count ?? 0)));
        }

        private static string DescribeFashionSpriteLayers(Character character)
        {
            if (character == null) { return "character=nil"; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session) ||
                session.SpritesBySlot.Count == 0)
            {
                return "none";
            }
            return string.Join(";",
                session.SpritesBySlot.Values
                    .Where(spriteList => spriteList != null)
                    .SelectMany(spriteList => spriteList.Where(descriptor => descriptor?.Sprite != null).Select(descriptor => GetFashionLayerName(descriptor.Sprite)))
                    .GroupBy(layer => layer)
                    .OrderBy(group => group.Key)
                    .Select(group => group.Key + "=" + group.Count()));
        }

        private static string DescribeFashionSpriteSources(Character character)
        {
            if (character == null ||
                !RenderSessions.TryGetValue(character, out RenderSession session) ||
                session.SpriteCount == 0)
            {
                return "none";
            }
            return string.Join(";",
                session.Descriptors
                    .Where(descriptor => descriptor != null)
                    .OrderBy(descriptor => descriptor.SourceIdentifier)
                    .ThenBy(descriptor => descriptor.ResolvedSpritePath)
                    .Select(descriptor =>
                        descriptor.SourceIdentifier +
                        "@" +
                        descriptor.SourceContentPackage +
                        "=" +
                        descriptor.ResolvedSpritePath));
        }

    }

}
