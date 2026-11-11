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

        internal static bool TryOverrideDrawWearable(Limb limb, WearableSprite original, out WearableSprite replacement, out bool skipOriginal)
        {
            replacement = null;
            skipOriginal = false;
            if (limb == null || original == null) { return false; }
            if (limb.character == null ||
                !RenderSessions.TryGetValue(limb.character, out RenderSession session) ||
                !session.IsActive ||
                !HasCapability("renderer") ||
                !session.TryGetDrawContext(limb, out object context) ||
                !(context is LimbRenderTransaction transaction) ||
                !transaction.IsOwner)
            {
                return false;
            }
            // This content family's left-breast sprites use LimbType.None, which is
            // also used by other limbs in the same ragdoll. Keep them on LeftBoobs.
            if (!IsFashionSpriteCompatibleWithLimb(session, original, limb))
            {
                transaction.DrawnSprites.Add(original);
                skipOriginal = true;
                return true;
            }
            if (transaction.IsDrawingStoredFashion) { return false; }
            if (!IsEquipmentSprite(original))
            {
                if (ShouldHideAttachmentForFashion(limb.character, original))
                {
                    skipOriginal = true;
                    drawOverrideHiddenAttachmentCount++;
                    return true;
                }
                return false;
            }
            HashSet<WearableSprite> drawnSprites = transaction.DrawnSprites;
            if (transaction.InjectedSprites.Contains(original))
            {
                if (ShouldHideFashionBehindVisibleEquipment(limb))
                {
                    skipOriginal = true;
                    drawOverrideHiddenAfterDrawCount++;
                    return true;
                }
                // Fail closed at the actual draw boundary. A stale dictionary key or
                // interrupted render transaction must never draw one limb's sprite on
                // another physical limb.
                if (!SpriteBelongsToLimb(session, original, limb.type))
                {
                    skipOriginal = true;
                    return true;
                }
                drawnSprites.Add(original);
                drawOverrideHitCount++;
                return false;
            }
            // Let empty-slot gear reach the native draw before same-limb fashion
            // deduplication can mistake a backpack for already-drawn clothing.
            if (ShouldDrawOriginalForEmptySavedSlot(limb.character, original)) { return false; }
            bool hideOriginalForEmptySavedSlot = ShouldHideOriginalForEmptySavedSlot(limb.character, original);
            // Empty is an explicit appearance choice. Resolve it before looking for
            // a same-type fashion sprite that may belong to a different saved slot.
            if (hideOriginalForEmptySavedSlot)
            {
                skipOriginal = true;
                drawOverrideHiddenEmptySlotCount++;
                return true;
            }
            bool hideOriginalForSavedSlot = ShouldHideOriginalForSavedSlot(limb.character, original);
            if (!TryGetFashionSprite(
                    limb.character,
                    original.Type,
                    limb.type,
                    drawnSprites,
                    out WearableSprite fashionSprite,
                    out bool fashionSpriteAlreadyDrawn))
            {
                if (hideOriginalForSavedSlot)
                {
                    skipOriginal = true;
                    drawOverrideHiddenSavedSlotCount++;
                    return true;
                }
                if (fashionSpriteAlreadyDrawn)
                {
                    skipOriginal = true;
                    drawOverrideHiddenAfterDrawCount++;
                    return true;
                }
                drawOverrideMissCount++;
                return false;
            }

            if (hideOriginalForSavedSlot)
            {
                skipOriginal = true;
                drawOverrideHiddenSavedSlotCount++;
                return true;
            }
            drawOverrideMissCount++;
            return false;
        }

        internal static LimbRenderTransaction BeginLimbDraw(Limb limb)
        {
            if (limb?.character == null ||
                !RenderSessions.TryGetValue(limb.character, out RenderSession session) ||
                !session.IsActive ||
                !session.IsValid ||
                !HasCapability("renderer"))
            {
                return null;
            }

            LimbRenderTransaction transaction = RentLimbRenderTransaction(limb);
            try
            {
                if (!session.TryEnterDraw(limb, transaction))
                {
                    return transaction;
                }
                transaction.Begin(session);
                return transaction;
            }
            catch (Exception ex)
            {
                LogVirtualDrawError($"Failed to begin fashion limb draw: {ex.GetType().Name}: {ex.Message}");
                try
                {
                    transaction.Cleanup();
                }
                catch (Exception cleanupException)
                {
                    LogVirtualDrawError(
                        "Fashion limb draw begin failed and cleanup also failed: " +
                        cleanupException.GetType().Name + ": " + cleanupException.Message);
                }
                if (limb?.character != null &&
                    RenderSessions.TryGetValue(limb.character, out RenderSession failedSession))
                {
                    failedSession.MarkInvalid("render transaction failed: " + ex.GetType().Name + ": " + ex.Message);
                }
                return transaction;
            }
        }

        private static LimbRenderTransaction RentLimbRenderTransaction(Limb limb)
        {
            Stack<LimbRenderTransaction> pool = limbRenderTransactionPool;
            if (pool != null && pool.Count > 0)
            {
                LimbRenderTransaction transaction = pool.Pop();
                transaction.Reset(limb);
                return transaction;
            }
            return new LimbRenderTransaction(limb);
        }

        private static void ReturnLimbRenderTransaction(LimbRenderTransaction transaction)
        {
            if (transaction == null) { return; }
            transaction.ResetForPool();
            Stack<LimbRenderTransaction> pool = limbRenderTransactionPool ??=
                new Stack<LimbRenderTransaction>();
            if (pool.Count < LimbRenderTransactionPoolLimit)
            {
                pool.Push(transaction);
            }
        }

        internal static bool ShouldSuppressEquipmentAppendage(Limb limb)
        {
            if (limb?.character == null ||
                limb.type != LimbType.None ||
                limb.Params == null ||
                !RenderSessions.TryGetValue(limb.character, out RenderSession session) ||
                !session.IsActive ||
                (!session.SavedSlots.Contains(InvSlotType.Bag) &&
                 !((session.ForceHideEmptySlots || GetHideEmptySlotEquipment()) &&
                   session.EmptySlots.Contains(InvSlotType.Bag))))
            {
                return false;
            }

            // Never suppress the appendage created for the saved XDS fashion itself.
            // The checks below are only for an actually equipped XDS engine.
            if (session.OwnsAppendage(limb)) { return false; }

            // XDS-01 draws its visible engine as six AfflictionHusk appendage limbs;
            // the Bag Wearable itself contains only transparent placeholder sprites.
            // Keep this compatibility rule tightly scoped because the public API does
            // not expose which affliction created a runtime limb.
            Item bagItem = limb.character.Inventory?.GetItemInLimbSlot(InvSlotType.Bag);
            if (!string.Equals(
                    bagItem?.Prefab?.Identifier.ToString(),
                    Xds01EngineIdentifier,
                    StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            string name = limb.Params.Name ?? string.Empty;
            bool matchesAppendage =
                name == "Engine" ||
                 name == "Wing1" ||
                 name == "Wing2" ||
                 name == "Helmet" ||
                 name == "RightLegRing" ||
                 name == "LeftLegRing";
            if (!matchesAppendage) { return false; }

            string spritePath;
            try
            {
                spritePath = limb.Sprite?.FullPath ?? limb.Sprite?.FilePath?.Value ?? string.Empty;
            }
            catch
            {
                return false;
            }
            return string.Equals(
                Path.GetFileName(spritePath),
                Xds01AppendageTexture,
                StringComparison.OrdinalIgnoreCase);
        }

        internal static bool ShouldSuppressAfflictionAppendage(Limb limb)
        {
            if (limb?.character?.CharacterHealth == null || HuskAppendageField == null)
            {
                return false;
            }
            bool hideHuskAppearance = GetHideHuskVisuals();
            bool hideTouhouWings =
                RenderSessions.TryGetValue(limb.character, out RenderSession session) &&
                session.IsActive &&
                session.IsValid;
            if (!hideHuskAppearance && !hideTouhouWings) { return false; }

            foreach (Affliction affliction in limb.character.CharacterHealth.GetAllAfflictions())
            {
                if (!(affliction is AfflictionHusk)) { continue; }
                bool suppressAppendage =
                    (hideHuskAppearance && IsHuskAppearanceAffliction(affliction)) ||
                    (hideTouhouWings && TouhouWingAfflictionIdentifiers.Contains(affliction.Identifier));
                if (!suppressAppendage ||
                    !(HuskAppendageField.GetValue(affliction) is IEnumerable appendages))
                {
                    continue;
                }
                foreach (object appendage in appendages)
                {
                    if (ReferenceEquals(appendage, limb)) { return true; }
                }
            }
            return false;
        }

        internal static WearableSprite BeginHuskSpriteSuppression(Limb limb)
        {
            if (!GetHideHuskVisuals() || limb == null || HuskSpriteField == null ||
                !HasHuskAppearanceAffliction(limb.character))
            {
                return null;
            }
            try
            {
                WearableSprite huskSprite = HuskSpriteField.GetValue(limb) as WearableSprite;
                if (huskSprite != null) { HuskSpriteField.SetValue(limb, null); }
                return huskSprite;
            }
            catch (Exception ex)
            {
                LogVirtualDrawError("Failed to hide husk sprite: " + ex.GetType().Name + ": " + ex.Message);
                return null;
            }
        }

        internal static Exception EndHuskSpriteSuppression(
            Limb limb,
            WearableSprite huskSprite,
            Exception exception)
        {
            if (limb == null || huskSprite == null || HuskSpriteField == null) { return exception; }
            try
            {
                HuskSpriteField.SetValue(limb, huskSprite);
            }
            catch (Exception ex)
            {
                LogVirtualDrawError("Failed to restore husk sprite: " + ex.GetType().Name + ": " + ex.Message);
                return exception ?? ex;
            }
            return exception;
        }

        internal static void SuppressHuskTint(Affliction affliction, ref Color result)
        {
            if (GetHideHuskVisuals() && IsHuskAppearanceAffliction(affliction))
            {
                result = Color.TransparentBlack;
            }
        }

        private static bool HasHuskAppearanceAffliction(Character character)
        {
            if (character?.CharacterHealth == null) { return false; }
            foreach (Affliction affliction in character.CharacterHealth.GetAllAfflictions())
            {
                if (IsHuskAppearanceAffliction(affliction)) { return true; }
            }
            return false;
        }

        private static bool IsHuskAppearanceAffliction(Affliction affliction)
        {
            return affliction is AfflictionHusk &&
                   HuskAppearanceAfflictionIdentifiers.Contains(affliction.Identifier);
        }

        internal static Exception EndLimbDraw(Limb limb, LimbRenderTransaction transaction, Exception exception = null)
        {
            Exception cleanupException = null;
            try
            {
                transaction?.Cleanup();
            }
            catch (Exception ex)
            {
                cleanupException = ex;
                LogVirtualDrawError($"Failed to end fashion limb draw: {ex.GetType().Name}: {ex.Message}");
            }
            finally
            {
                ReturnLimbRenderTransaction(transaction);
            }
            // Harmony finalizers suppress an exception only when they return null. The
            // original draw exception always wins and is returned by reference unchanged;
            // a cleanup failure is propagated only when there was no draw failure.
            return exception ?? cleanupException;
        }

        internal static FootstepSoundTransaction BeginFootstepSound(Limb limb)
        {
            if (limb?.character == null ||
                !RenderSessions.TryGetValue(limb.character, out RenderSession session))
            {
                return null;
            }
            session.FootstepSoundCalls++;
            if (!session.IsActive ||
                !session.IsValid ||
                !session.UseFashionFootstepSounds ||
                !HasCapability("footstepSound"))
            {
                return null;
            }

            Stack<FootstepSoundTransaction> pool = footstepSoundTransactionPool;
            FootstepSoundTransaction transaction = pool != null && pool.Count > 0
                ? pool.Pop()
                : new FootstepSoundTransaction();
            transaction.Reset(limb);
            try
            {
                transaction.Begin(session);
                session.FashionFootstepSoundCalls++;
                return transaction;
            }
            catch (Exception ex)
            {
                LogSoundError($"Failed to select fashion footstep sounds: {ex.GetType().Name}: {ex.Message}");
                try { transaction.Cleanup(); }
                catch (Exception cleanupException)
                {
                    LogSoundError(
                        "Fashion footstep selection failed and cleanup also failed: " +
                        cleanupException.GetType().Name + ": " + cleanupException.Message);
                }
                ReturnFootstepSoundTransaction(transaction);
                return null;
            }
        }

        private static string DescribeFashionFootstepSounds(RenderSession session)
        {
            if (session == null) { return "none"; }
            string[] tags = session.Descriptors
                .Where(descriptor => !string.IsNullOrWhiteSpace(descriptor?.Sprite?.Sound))
                .Select(descriptor => descriptor.Sprite.Limb + ":" + descriptor.Sprite.Sound)
                .Distinct()
                .ToArray();
            return tags.Length == 0 ? "none" : string.Join(",", tags);
        }

        internal static Exception EndFootstepSound(
            FootstepSoundTransaction transaction,
            Exception exception = null)
        {
            Exception cleanupException = null;
            try { transaction?.Cleanup(); }
            catch (Exception ex)
            {
                cleanupException = ex;
                LogSoundError($"Failed to restore equipment footstep sounds: {ex.GetType().Name}: {ex.Message}");
            }
            finally
            {
                ReturnFootstepSoundTransaction(transaction);
            }
            return exception ?? cleanupException;
        }

        private static void ReturnFootstepSoundTransaction(FootstepSoundTransaction transaction)
        {
            if (transaction == null) { return; }
            transaction.ResetForPool();
            Stack<FootstepSoundTransaction> pool =
                footstepSoundTransactionPool ??= new Stack<FootstepSoundTransaction>();
            if (pool.Count < FootstepSoundTransactionPoolLimit)
            {
                pool.Push(transaction);
            }
        }

        internal static void DrawMissingFashionSprites(
            Limb limb,
            LimbRenderTransaction transaction,
            SpriteBatch spriteBatch,
            Color? overrideColor)
        {
            if (limb?.character == null || spriteBatch == null || transaction == null || !transaction.IsOwner) { return; }
            try
            {
                if (!RenderSessions.TryGetValue(limb.character, out RenderSession session) ||
                    !session.IsActive ||
                    session.SpritesBySlot.Count == 0)
                {
                    return;
                }
                if (DrawWearableMethod == null)
                {
                    LogVirtualDrawError("Limb.DrawWearable method was not found.");
                    return;
                }

                HashSet<WearableSprite> drawnSprites = transaction.DrawnSprites;

                int defaultDepthIndex = Math.Max((limb.WearingItems?.Count ?? 0) + DefaultFallbackDepthPadding, DefaultFallbackDepthPadding);
                int recessedDepthIndex = RecessedFallbackDepthStart;
                foreach (FashionSpriteDescriptor descriptor in transaction.FashionDescriptors)
                {
                    WearableSprite sprite = descriptor.Sprite;
                    if (!IsFashionSpriteCompatibleWithLimb(session, sprite, limb)) { continue; }
                    if (ShouldHideFashionBehindVisibleEquipment(limb)) { continue; }
                    if (drawnSprites.Contains(sprite)) { continue; }

                    drawnSprites.Add(sprite);
                    fallbackDrawnFashionSpriteCount++;
                    int depthIndex = UsesRecessedFashionLayer(descriptor) ? recessedDepthIndex++ : defaultDepthIndex++;
                    DrawFashionWearable(session, limb, transaction, sprite, depthIndex, spriteBatch, overrideColor);
                }
            }
            catch (Exception ex)
            {
                LogVirtualDrawError($"Failed to draw missing fashion sprites: {ex.GetType().Name}: {ex.Message}");
                throw;
            }
        }

        private static void DrawFashionWearable(
            RenderSession session,
            Limb limb,
            LimbRenderTransaction transaction,
            WearableSprite wearable,
            int depthIndex,
            SpriteBatch spriteBatch,
            Color? overrideColor)
        {
            if (!SpriteBelongsToLimb(session, wearable, limb.type)) { return; }
            Color color = overrideColor.GetValueOrDefault(Color.White);
            color *= limb.Alpha;
            if (color.A <= 0) { return; }

            // DrawWearable delegates to the engine's CalculateDrawParameters,
            // which reads WearableComponent.Item.GetSpriteColor().
            SpriteEffects spriteEffect = limb.Dir > 0.0f ? SpriteEffects.None : SpriteEffects.FlipHorizontally;
            if (limb.Params.MirrorHorizontally)
            {
                spriteEffect = spriteEffect == SpriteEffects.None ? SpriteEffects.FlipHorizontally : SpriteEffects.None;
            }
            if (limb.Params.MirrorVertically)
            {
                spriteEffect |= SpriteEffects.FlipVertically;
            }

            transaction.EnterStoredFashionDraw();
            try
            {
                try
                {
                    DrawWearableMethod.Invoke(
                        limb,
                        transaction.GetDrawArguments(
                            wearable,
                            DrawDepthStep * depthIndex,
                            spriteBatch,
                            color,
                            color.A / 255.0f,
                            spriteEffect));
                }
                catch (TargetInvocationException ex) when (ex.InnerException != null)
                {
                    ExceptionDispatchInfo.Capture(ex.InnerException).Throw();
                    throw;
                }
            }
            finally
            {
                transaction.ExitStoredFashionDraw();
            }
        }

    }

}
