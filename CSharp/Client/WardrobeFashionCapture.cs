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

        public static void ClearCharacter(Character character)
        {
            if (character == null) { return; }
            if (RenderSessions.TryGetValue(character, out RenderSession session))
            {
                session.Dispose();
                RenderSessions.Remove(character);
            }
            RefreshWearables(character);
        }

        public static void PruneStaleCharacters()
        {
            List<Character> characters = RenderSessions.Keys.Where(IsCharacterStale).ToList();

            foreach (Character character in characters)
            {
                if (RenderSessions.TryGetValue(character, out RenderSession session))
                {
                    session.Dispose();
                    RenderSessions.Remove(character);
                }
            }
        }

        private static RenderSession GetOrCreateSession(Character character)
        {
            if (character == null) { return null; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session))
            {
                session = new RenderSession(character);
                RenderSessions[character] = session;
            }
            return session;
        }

        private static RenderSession GetCaptureSession(Character character)
        {
            return GetOrCreateSession(character)?.CaptureTarget;
        }

        public static bool BeginFashionTransaction(Character character)
        {
            if (character == null || !HasCapability("renderer")) { return false; }
            try
            {
                GetOrCreateSession(character).BeginPendingCapture();
                return true;
            }
            catch (Exception ex)
            {
                LuaCsLogger.Log(
                    "[Baro Wardrobe Switcher] Failed to begin fashion capture transaction: " +
                    ex.GetType().Name + ": " + ex.Message);
                return false;
            }
        }

        public static bool CommitFashionTransaction(Character character)
        {
            if (character == null || !RenderSessions.TryGetValue(character, out RenderSession current)) { return false; }
            RenderSession staged = current.DetachPendingCapture();
            if (staged == null) { return false; }

            string error = null;
            if (!staged.Validate(out error) || !HasFashionPayload(staged))
            {
                staged.Dispose();
                LuaCsLogger.Log(
                    "[Baro Wardrobe Switcher] Fashion capture transaction rejected; previous session preserved: " +
                    (error ?? "staged session contains no fashion payload") + ".");
                return false;
            }

            staged.MarkCommitted();
            RenderSessions[character] = staged;
            current.Dispose();
            LuaCsLogger.Log("[Baro Wardrobe Switcher] Fashion capture transaction committed atomically.");
            return true;
        }

        public static bool CanReuseCapturedFashion(Character character)
        {
            if (character == null || !HasCapability("renderer")) { return false; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session) ||
                !session.IsCommitted ||
                session.HasPendingCapture ||
                session.HasLiveItemSources ||
                !HasFashionPayload(session))
            {
                return false;
            }
            return session.Validate(out _);
        }

        public static bool AbortFashionTransaction(Character character)
        {
            if (character == null || !RenderSessions.TryGetValue(character, out RenderSession current)) { return false; }
            bool aborted = current.AbortPendingCapture();
            if (aborted)
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] Fashion capture transaction aborted; previous session preserved.");
            }
            return aborted;
        }

        public static int CaptureFashionItem(Character character, Item item)
        {
            return CaptureFashionItemCore(character, item, takeOwnership: false, out _);
        }

        private static int CaptureFashionItemCore(
            Character character,
            Item item,
            bool takeOwnership,
            out bool capturedSuccessfully)
        {
            capturedSuccessfully = false;
            if (character == null || item == null || !HasCapability("renderer")) { return 0; }

            RenderSession session = GetCaptureSession(character);
            session.EmptyLook = false;
            session.IsActive = false;
            Wearable wearable = item.GetComponent<Wearable>();
            if (wearable == null)
            {
                string failure = "Fashion item has no Wearable component: " +
                                 (item.Prefab?.Identifier.ToString() ?? item.Name.ToString());
                session.MarkInvalid(failure);
                LuaCsLogger.Log("[Baro Wardrobe Switcher] " + failure + ". Activation refused.");
                return 0;
            }
            List<FashionSpriteDescriptor> stagedDescriptors = new List<FashionSpriteDescriptor>();
            if (wearable.wearableSprites != null)
            {
                bool preserveMasks = FashionEffectPolicy.IsSealedSuit(item);
                foreach (WearableSprite source in wearable.wearableSprites.Where(IsEquipmentSprite))
                {
                    if (!FashionSpriteDescriptor.TryCreate(
                            character,
                            item,
                            source,
                            preserveMasks,
                            out FashionSpriteDescriptor descriptor,
                            out string error))
                    {
                        foreach (FashionSpriteDescriptor staged in stagedDescriptors) { staged.Dispose(); }
                        string failure = "Failed to create initialized fashion sprite for " +
                                         (item.Prefab?.Identifier.ToString() ?? item.Name.ToString()) + ": " + error;
                        session.MarkInvalid(failure);
                        LuaCsLogger.Log("[Baro Wardrobe Switcher] " + failure + ". Activation refused.");
                        return 0;
                    }
                    stagedDescriptors.Add(descriptor);
                }
            }

            int animationCount;
            int soundCount;
            int itemSoundCount;
            try
            {
                animationCount = CaptureFashionAnimations(session, item);
                soundCount = CaptureFashionSounds(session, item);
                itemSoundCount = CaptureFashionComponentSounds(session, item);

                foreach (FashionSpriteDescriptor descriptor in stagedDescriptors)
                {
                    session.Add(descriptor);
                }
                foreach (WearableSprite source in wearable.wearableSprites?.Where(IsEquipmentSprite) ?? Enumerable.Empty<WearableSprite>())
                {
                    // Capture attachment hiding intent from the source before descriptor
                    // mask sanitization removes it.
                    CaptureFashionHiddenWearableTypes(session, source);
                }
                if (takeOwnership)
                {
                    session.AddOwnedTemporaryItem(item);
                }
                else
                {
                    session.MarkLiveItemSource();
                }
            }
            catch (Exception ex)
            {
                foreach (FashionSpriteDescriptor staged in stagedDescriptors) { staged.Dispose(); }
                string failure = "Fashion capture transaction failed: " + ex.GetType().Name + ": " + ex.Message;
                session.MarkInvalid(failure);
                LuaCsLogger.Log("[Baro Wardrobe Switcher] " + failure + ". Activation refused.");
                return 0;
            }
            int count = stagedDescriptors.Count;
            LuaCsLogger.Log($"[Baro Wardrobe Switcher] Captured {count} wearable sprites, {animationCount} animation triggers, {soundCount} status sound triggers, and {itemSoundCount} item sound components from fashion item: {item.Name}.");
            capturedSuccessfully = true;
            return count;
        }

        public static int CaptureFashionPrefab(Character character, string identifier)
        {
            return CaptureFashionPrefabCore(character, identifier, null);
        }

        public static int CaptureFashionPrefab(Character character, string identifier, uint packedColor)
        {
            return CaptureFashionPrefabCore(character, identifier, packedColor);
        }

        private static int CaptureFashionPrefabCore(
            Character character,
            string identifier,
            uint? packedColor)
        {
            if (character == null || string.IsNullOrWhiteSpace(identifier)) { return 0; }

            try
            {
                Identifier prefabIdentifier = new Identifier(identifier);
                if (!ItemPrefab.Prefabs.TryGet(prefabIdentifier, out ItemPrefab prefab) || prefab == null)
                {
                    string failure = "Could not find fashion prefab by identifier: " + identifier;
                    GetCaptureSession(character).MarkInvalid(failure);
                    LuaCsLogger.Log("[Baro Wardrobe Switcher] " + failure + ". Activation refused.");
                    return 0;
                }

                Item tempItem = null;
                try
                {
                    tempItem = new Item(prefab, Vector2.Zero, null, 0, false);
                    // The fallback item must keep its components alive for captured
                    // animations and sounds, but it must never reserve a client-side
                    // entity ID. A server spawn can legitimately reuse that ID.
                    tempItem.FreeID();
                    if (packedColor.HasValue)
                    {
                        tempItem.SpriteColor = new Color(packedColor.Value);
                    }
                    int captured = CaptureFashionItemCore(character, tempItem, takeOwnership: true, out bool succeeded);
                    if (!succeeded) { return 0; }
                    // Ownership was transferred to the render session. It must outlive
                    // descriptors and captured effects and is removed by session.Dispose.
                    tempItem = null;
                    LuaCsLogger.Log($"[Baro Wardrobe Switcher] Captured {captured} wearable sprite(s) from fashion prefab fallback: {identifier}.");
                    return captured;
                }
                finally
                {
                    try
                    {
                        tempItem?.Remove();
                    }
                    catch (Exception ex)
                    {
                        LuaCsLogger.Log($"[Baro Wardrobe Switcher] Failed to remove temporary fashion prefab item {identifier}: {ex.GetType().Name}: {ex.Message}");
                    }
                }
            }
            catch (Exception ex)
            {
                string failure = $"Fashion prefab fallback failed for {identifier}: {ex.GetType().Name}: {ex.Message}";
                GetCaptureSession(character).MarkInvalid(failure);
                LuaCsLogger.Log("[Baro Wardrobe Switcher] " + failure + ". Activation refused.");
                return 0;
            }
        }

        public static bool CaptureEmptyFashion(Character character)
        {
            if (character == null || !HasCapability("renderer")) { return false; }
            RenderSession session = GetCaptureSession(character);
            session.EmptyLook = true;
            session.IsActive = false;
            LuaCsLogger.Log("[Baro Wardrobe Switcher] Captured empty fashion look.");
            return true;
        }

        public static bool SetFashionSlots(
            Character character, string savedSlotsCsv, string emptySlotsCsv, bool forceHideEmptySlots = false)
        {
            if (character == null) { return false; }
            RenderSession session = GetCaptureSession(character);
            HashSet<InvSlotType> savedSlots = ParseSlotCsv(savedSlotsCsv);
            HashSet<InvSlotType> emptySlots = ParseSlotCsv(emptySlotsCsv);
            bool changed =
                !session.SavedSlots.SetEquals(savedSlots) ||
                !session.EmptySlots.SetEquals(emptySlots);
            session.SuppressedEquipmentAnimations.Clear();
            session.EquipmentMovementAnimations.Clear();
            session.SuppressedEquipmentSounds.Clear();
            session.SuppressedEquipmentComponentSounds.Clear();
            session.SavedSlots = savedSlots;
            session.EmptySlots = emptySlots;
            session.ForceHideEmptySlots = forceHideEmptySlots;
            if (changed)
            {
                LuaCsLogger.Log(
                    "[Baro Wardrobe Switcher] Fashion slot mask: saved=" +
                    DescribeSavedSlots(character) +
                    ", empty=" +
                    DescribeEmptySlots(character) +
                    ".");
            }
            return true;
        }

        public static bool IsDivingSuitItem(Item item)
        {
            return FashionEffectPolicy.IsSealedSuit(item);
        }

        public static bool SetAttachmentVisibility(
            Character character,
            int forceHideMask,
            int forceShowMask)
        {
            if (character == null) { return false; }
            if ((forceHideMask & ~AttachmentVisibilityMask) != 0 ||
                (forceShowMask & ~AttachmentVisibilityMask) != 0 ||
                (forceHideMask & forceShowMask) != 0)
            {
                LuaCsLogger.Log(
                    "[Baro Wardrobe Switcher] Rejected invalid attachment visibility masks: hide=0x" +
                    forceHideMask.ToString("X2") +
                    ", show=0x" +
                    forceShowMask.ToString("X2") +
                    ".");
                return false;
            }

            RenderSession session = GetCaptureSession(character);
            bool changed =
                session.ForceHideAttachmentMask != forceHideMask ||
                session.ForceShowAttachmentMask != forceShowMask;
            session.ForceHideAttachmentMask = forceHideMask;
            session.ForceShowAttachmentMask = forceShowMask;
            if (changed)
            {
                LuaCsLogger.Log(
                    "[Baro Wardrobe Switcher] Fashion attachment visibility set: hide=0x" +
                    forceHideMask.ToString("X2") +
                    ", show=0x" +
                    forceShowMask.ToString("X2") +
                    ".");
            }
            return true;
        }

        public static bool SetUseFashionMovementAnimations(Character character, bool enabled)
        {
            if (character == null ||
                !RenderSessions.TryGetValue(character, out RenderSession session))
            {
                return false;
            }

            session.UseFashionMovementAnimations = enabled;
            if (!enabled) { session.EquipmentMovementAnimations.Clear(); }
            return true;
        }

        public static bool SetUseFashionFootstepSounds(Character character, bool enabled)
        {
            if (character == null ||
                !RenderSessions.TryGetValue(character, out RenderSession session) ||
                (enabled && !HasCapability("footstepSound")))
            {
                return false;
            }

            session.UseFashionFootstepSounds = enabled;
            return true;
        }

        // Compatibility wrapper for v0.5.1 Lua and third-party integrations.
        public static bool SetHideHair(Character character, bool hideHair)
        {
            return SetAttachmentVisibility(
                character,
                hideHair
                    ? AttachmentHairBit | AttachmentBeardBit | AttachmentMoustacheBit
                    : 0,
                0);
        }

        public static bool ApplyFashionItemVisual(Character character, Item item, bool carrier)
        {
            if (character == null || item == null || !HasCapability("renderer")) { return false; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session) ||
                !HasFashionPayload(session))
            {
                return false;
            }

            if (HasCapability("animation")) { RegisterSuppressedEquipmentAnimations(character, item); }
            if (HasCapability("statusSound")) { RegisterSuppressedEquipmentSounds(character, item); }
            if (HasCapability("itemSound")) { RegisterSuppressedEquipmentComponentSounds(character, item); }

            if (carrier && !session.IsActive)
            {
                LuaCsLogger.Log($"[Baro Wardrobe Switcher] Registered draw-only fashion carrier: {item.Name}, capturedSprites={session.SpriteCount}.");
            }
            return true;
        }

        public static bool RemoveFashionItemVisual(Character character, Item item)
        {
            if (character == null || item == null ||
                !RenderSessions.TryGetValue(character, out RenderSession session))
            {
                return false;
            }
            if (item.Components == null) { return true; }

            foreach (ItemComponent component in item.Components)
            {
                if (component == null) { continue; }
                session.SuppressedEquipmentComponentSounds.Remove(component);
                session.LoopingEquipmentComponentSounds.RemoveWhere(sound => ReferenceEquals(sound.Component, component));
                if (component.statusEffectLists == null ||
                    !component.statusEffectLists.TryGetValue(
                        ActionType.OnWearing,
                        out List<StatusEffect> statusEffects))
                {
                    continue;
                }

                foreach (StatusEffect statusEffect in statusEffects)
                {
                    session.SuppressedEquipmentSounds.Remove(statusEffect);
                    session.LoopingEquipmentSounds.Remove(statusEffect);
                    IEnumerable animations =
                        AnimationsToTriggerField?.GetValue(statusEffect) as IEnumerable;
                    if (animations == null) { continue; }
                    foreach (object animationInfo in animations)
                    {
                        session.SuppressedEquipmentAnimations.Remove(animationInfo);
                        session.EquipmentMovementAnimations.Remove(animationInfo);
                    }
                }
            }
            return true;
        }

        public static bool ActivateFashionVisual(Character character)
        {
            if (character == null || !HasCapability("renderer") || !HasFashionPayload(character)) { return false; }
            string error = "render session missing";
            if (!RenderSessions.TryGetValue(character, out RenderSession session))
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] Fashion activation refused: " + error + ".");
                return false;
            }
            if (session.IsActive) { return true; }
            if (!session.Validate(out error))
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] Fashion activation refused: " + (error ?? "render session missing") + ".");
                return false;
            }
            if (!EnsureXdsFashionAppendage(character, session))
            {
                session.IsActive = false;
                return false;
            }
            session.IsActive = true;
            virtualDrawErrorLogCount = 0;
            animationOverrideErrorLogCount = 0;
            soundOverrideErrorLogCount = 0;
            lastInjectedSpriteCount = 0;
            drawOverrideHitCount = 0;
            drawOverrideMissCount = 0;
            drawOverrideHiddenAfterDrawCount = 0;
            drawOverrideHiddenEmptySlotCount = 0;
            drawOverrideHiddenSavedSlotCount = 0;
            drawOverrideHiddenAttachmentCount = 0;
            return true;
        }

        private static bool EnsureXdsFashionAppendage(Character character, RenderSession session)
        {
            bool needsXdsAppendage =
                session.SavedSlots.Contains(InvSlotType.Bag) &&
                session.Descriptors.Any(descriptor =>
                    descriptor.AllowedSlots.Contains(InvSlotType.Bag) &&
                    string.Equals(
                        descriptor.SourceIdentifier,
                        Xds01EngineIdentifier,
                        StringComparison.OrdinalIgnoreCase));
            if (!needsXdsAppendage)
            {
                session.RemoveOwnedAppendages();
                return true;
            }
            if (session.HasOwnedAppendages) { return true; }
            if (character.Params == null || character.AnimController == null) { return false; }

            HashSet<Limb> limbsBeforeAttach =
                new HashSet<Limb>(character.AnimController.Limbs.Where(limb => limb != null));
            try
            {
                Identifier identifier = new Identifier(Xds01EngineAfflictionIdentifier);
                if (!AfflictionPrefab.Prefabs.TryGet(identifier, out AfflictionPrefab prefab) ||
                    !(prefab is AfflictionPrefabHusk huskPrefab))
                {
                    LuaCsLogger.Log(
                        "[Baro Wardrobe Switcher] XDS-01 appendage prefab was not found; fashion activation refused.");
                    return false;
                }

                Identifier huskedSpeciesName =
                    AfflictionHusk.GetHuskedSpeciesName(character.Params, huskPrefab);
                List<Limb> appendages =
                    AfflictionHusk.AttachHuskAppendage(character, huskPrefab, huskedSpeciesName);
                if (appendages == null ||
                    appendages.Count != Xds01ExpectedAppendageLimbCount)
                {
                    session.SetOwnedAppendages(appendages);
                    session.RemoveOwnedAppendages();
                    LuaCsLogger.Log(
                        "[Baro Wardrobe Switcher] XDS-01 appendage creation returned " +
                        (appendages?.Count ?? 0) +
                        " of " +
                        Xds01ExpectedAppendageLimbCount +
                        " limbs; fashion activation refused.");
                    return false;
                }

                // Experimental exact-appearance path: use the content mod's native
                // limbs and joints without applying its afflictions or item effects.
                session.SetOwnedAppendages(appendages);
                LuaCsLogger.Log(
                    "[Baro Wardrobe Switcher] XDS-01 fashion appendage created with " +
                    appendages.Count +
                    " render limbs.");
                return true;
            }
            catch (Exception ex)
            {
                session.RemoveOwnedAppendages();
                foreach (Limb addedLimb in character.AnimController.Limbs
                             .Where(limb => limb != null && !limbsBeforeAttach.Contains(limb))
                             .ToList())
                {
                    try { character.AnimController.RemoveLimb(addedLimb); } catch { }
                }
                LuaCsLogger.Log(
                    "[Baro Wardrobe Switcher] XDS-01 appendage creation failed: " +
                    ex.GetType().Name +
                    ": " +
                    ex.Message);
                return false;
            }
        }

    }

}
