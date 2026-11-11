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

        internal sealed class FootstepSoundTransaction
        {
            private Limb limb;
            private List<WearableSprite> originalOrder;
            private bool cleaned;

            public void Reset(Limb nextLimb)
            {
                limb = nextLimb;
                cleaned = false;
                originalOrder?.Clear();
            }

            public void ResetForPool()
            {
                limb = null;
                cleaned = true;
                originalOrder?.Clear();
            }

            public void Begin(RenderSession session)
            {
                if (session == null) { throw new ArgumentNullException(nameof(session)); }
                List<WearableSprite> wearingItems = limb?.WearingItems;
                if (wearingItems == null) { return; }

                originalOrder ??= new List<WearableSprite>(wearingItems.Count);
                originalOrder.Clear();
                originalOrder.AddRange(wearingItems);
                for (int index = wearingItems.Count - 1; index >= 0; index--)
                {
                    if (IsEquipmentSprite(wearingItems[index]))
                    {
                        wearingItems.RemoveAt(index);
                    }
                }

                foreach (FashionSpriteDescriptor descriptor in session.Descriptors)
                {
                    if (descriptor == null)
                    {
                        throw new InvalidOperationException("fashion footstep descriptor is missing");
                    }
                    if (!descriptor.IsValid(out string error))
                    {
                        throw new InvalidOperationException("invalid fashion footstep descriptor: " + error);
                    }
                    WearableSprite sprite = descriptor.Sprite;
                    if (sprite.Limb == limb.type && !wearingItems.Contains(sprite))
                    {
                        wearingItems.Add(sprite);
                    }
                }
            }

            public void Cleanup()
            {
                if (cleaned) { return; }
                cleaned = true;
                if (originalOrder == null || limb?.WearingItems == null) { return; }
                limb.WearingItems.Clear();
                limb.WearingItems.AddRange(originalOrder);
                originalOrder.Clear();
            }
        }

        internal sealed class LimbRenderTransaction
        {
            private Limb limb;
            private Dictionary<WearableSprite, SpriteMaskState> originalMasks;
            private List<WearableSprite> originalOrder;
            private readonly List<WearableType> emptyHideWearablesOfType = new List<WearableType>();
            private RenderSession session;
            private object[] drawArguments;
            private bool cleaned;
            private bool wearingItemsChanged;
            private bool wearableTypesCacheChanged;
            private int storedFashionDrawDepth;

            public LimbRenderTransaction(Limb limb)
            {
                Reset(limb);
            }

            public bool IsOwner { get; private set; }

            public bool IsDrawingStoredFashion => storedFashionDrawDepth > 0;

            public HashSet<WearableSprite> DrawnSprites { get; } = new HashSet<WearableSprite>();

            public List<WearableSprite> InjectedSprites { get; } = new List<WearableSprite>();

            public IReadOnlyList<FashionSpriteDescriptor> FashionDescriptors { get; private set; } =
                Array.Empty<FashionSpriteDescriptor>();

            public object[] GetDrawArguments(
                WearableSprite wearable,
                float depth,
                SpriteBatch spriteBatch,
                Color color,
                float alpha,
                SpriteEffects spriteEffect)
            {
                drawArguments ??= new object[6];
                drawArguments[0] = wearable;
                drawArguments[1] = depth;
                drawArguments[2] = spriteBatch;
                drawArguments[3] = color;
                drawArguments[4] = alpha;
                drawArguments[5] = spriteEffect;
                return drawArguments;
            }

            public void Reset(Limb nextLimb)
            {
                limb = nextLimb;
                session = null;
                cleaned = false;
                wearingItemsChanged = false;
                wearableTypesCacheChanged = false;
                storedFashionDrawDepth = 0;
                IsOwner = false;
                originalOrder?.Clear();
                originalMasks?.Clear();
                emptyHideWearablesOfType.Clear();
                InjectedSprites.Clear();
                DrawnSprites.Clear();
                FashionDescriptors = Array.Empty<FashionSpriteDescriptor>();
                if (drawArguments != null) { Array.Clear(drawArguments, 0, drawArguments.Length); }
            }

            public void ResetForPool()
            {
                limb = null;
                session = null;
                cleaned = true;
                wearingItemsChanged = false;
                wearableTypesCacheChanged = false;
                storedFashionDrawDepth = 0;
                IsOwner = false;
                originalOrder?.Clear();
                originalMasks?.Clear();
                emptyHideWearablesOfType.Clear();
                InjectedSprites.Clear();
                DrawnSprites.Clear();
                FashionDescriptors = Array.Empty<FashionSpriteDescriptor>();
                if (drawArguments != null) { Array.Clear(drawArguments, 0, drawArguments.Length); }
            }

            public void EnterStoredFashionDraw()
            {
                if (!IsOwner) { throw new InvalidOperationException("Render transaction is not active."); }
                storedFashionDrawDepth++;
            }

            public void ExitStoredFashionDraw()
            {
                if (storedFashionDrawDepth <= 0)
                {
                    throw new InvalidOperationException("Stored fashion draw guard is unbalanced.");
                }
                storedFashionDrawDepth--;
            }

            public void Begin(RenderSession renderSession)
            {
                session = renderSession ?? throw new ArgumentNullException(nameof(renderSession));
                IsOwner = true;
                List<WearableSprite> wearingItems = limb?.WearingItems;
                if (wearingItems == null)
                {
                    FashionDescriptors = GetFashionSpritesForLimb(session, limb);
                    return;
                }

                // Replaced equipment must not transfer its body masks to fashion.
                // The saved sprite's own HideLimb controls exposed hands/feet.
                for (int index = 0; index < wearingItems.Count; index++)
                {
                    WearableSprite equipmentSprite = wearingItems[index];
                    if (!IsEquipmentSprite(equipmentSprite) || session.TryGetDescriptor(equipmentSprite, out _))
                    {
                        continue;
                    }
                    bool preserveEquipmentMasks = ShouldDrawOriginalForEmptySavedSlot(limb.character, equipmentSprite);
                    List<WearableType> filteredHideTypes = null;
                    if (preserveEquipmentMasks)
                    {
                        // Visible real gear keeps its native body and attachment masks.
                        // Only explicit Show choices override its attachment hiding.
                        if (session.ForceShowAttachmentMask != 0 && equipmentSprite.HideWearablesOfType != null)
                        {
                            foreach (WearableType hiddenType in equipmentSprite.HideWearablesOfType)
                            {
                                if (AttachmentBits.TryGetValue(hiddenType, out int bit) &&
                                    (session.ForceShowAttachmentMask & bit) != 0)
                                {
                                    filteredHideTypes ??= new List<WearableType>(equipmentSprite.HideWearablesOfType);
                                    filteredHideTypes.Remove(hiddenType);
                                }
                            }
                        }
                        if (filteredHideTypes == null) { continue; }
                    }
                    if (!NeedsMaskClear(equipmentSprite)) { continue; }
                    originalMasks ??= new Dictionary<WearableSprite, SpriteMaskState>();
                    originalMasks[equipmentSprite] = new SpriteMaskState(equipmentSprite);
                    if (equipmentSprite.HideWearablesOfType?.Count > 0)
                    {
                        wearableTypesCacheChanged = true;
                    }
                    if (preserveEquipmentMasks)
                    {
                        equipmentSprite.HideWearablesOfType = filteredHideTypes;
                    }
                    else
                    {
                        ClearMask(equipmentSprite, emptyHideWearablesOfType);
                    }
                }
                static List<FashionSpriteDescriptor> GetFashionSpritesForLimb(RenderSession session, Limb limb)
                {
                    if (session.FashionSpritesByLimb.TryGetValue(limb.type, out List<FashionSpriteDescriptor> cached))
                    {
                        return cached;
                    }
                    List<FashionSpriteDescriptor> descriptors = EnumerateFashionSpritesForLimb(session, limb.type).ToList();
                    session.FashionSpritesByLimb[limb.type] = descriptors;
                    return descriptors;
                }

                List<FashionSpriteDescriptor> descriptors = GetFashionSpritesForLimb(session, limb);
                FashionDescriptors = descriptors;
                for (int index = 0; index < descriptors.Count; index++)
                {
                    FashionSpriteDescriptor descriptor = descriptors[index];
                    if (!IsFashionSpriteCompatibleWithLimb(session, descriptor.Sprite, limb) ||
                        wearingItems.Contains(descriptor.Sprite))
                    {
                        continue;
                    }
                    if (!descriptor.IsValid(out string error))
                    {
                        throw new InvalidOperationException("invalid fashion descriptor: " + error);
                    }
                    if (!wearingItemsChanged)
                    {
                        originalOrder ??= new List<WearableSprite>(wearingItems.Count);
                        originalOrder.Clear();
                        originalOrder.AddRange(wearingItems);
                        wearingItemsChanged = true;
                    }
                    wearingItems.Add(descriptor.Sprite);
                    InjectedSprites.Add(descriptor.Sprite);
                }
                if (InjectedSprites.Count > 0)
                {
                    SortWearablesForDraw(wearingItems);
                    wearableTypesCacheChanged = true;
                }
                // Equip caches HideWearablesOfType before Limb.Draw starts. Rebuild
                // that cache after native mask changes and fashion injection so
                // fashion clothing can hide its own arm and attachment sprites.
                if (wearableTypesCacheChanged)
                {
                    limb.UpdateWearableTypesToHide();
                }
                lastInjectedSpriteCount = InjectedSprites.Count;
            }

            public void Cleanup()
            {
                if (cleaned) { return; }
                cleaned = true;
                List<Exception> cleanupErrors = null;
                try
                {
                    List<WearableSprite> wearingItems = limb?.WearingItems;
                    if (IsOwner && wearingItemsChanged && wearingItems != null)
                    {
                        wearingItems.Clear();
                        wearingItems.AddRange(originalOrder);
                    }
                }
                catch (Exception ex)
                {
                    (cleanupErrors ??= new List<Exception>()).Add(
                        new InvalidOperationException("Failed to restore Limb.WearingItems snapshot.", ex));
                }

                if (originalMasks != null)
                {
                    foreach (KeyValuePair<WearableSprite, SpriteMaskState> pair in originalMasks)
                    {
                        try
                        {
                            pair.Value.Restore(pair.Key);
                        }
                        catch (Exception ex)
                        {
                            (cleanupErrors ??= new List<Exception>()).Add(
                                new InvalidOperationException("Failed to restore wearable mask snapshot.", ex));
                        }
                    }
                }

                if (wearableTypesCacheChanged)
                {
                    try
                    {
                        limb.UpdateWearableTypesToHide();
                    }
                    catch (Exception ex)
                    {
                        (cleanupErrors ??= new List<Exception>()).Add(
                            new InvalidOperationException("Failed to restore wearable type hide cache.", ex));
                    }
                }

                if (IsOwner)
                {
                    try
                    {
                        session?.ExitDraw(limb);
                    }
                    catch (Exception ex)
                    {
                        (cleanupErrors ??= new List<Exception>()).Add(
                            new InvalidOperationException("Failed to release render transaction ownership.", ex));
                    }
                }

                originalMasks?.Clear();
                InjectedSprites.Clear();
                DrawnSprites.Clear();
                storedFashionDrawDepth = 0;
                wearingItemsChanged = false;
                IsOwner = false;

                if (cleanupErrors?.Count == 1) { throw cleanupErrors[0]; }
                if (cleanupErrors?.Count > 1)
                {
                    throw new AggregateException("Multiple render transaction cleanup operations failed.", cleanupErrors);
                }
            }
        }

        private sealed class PatchState
        {
            public PatchState(bool required)
            {
                Required = required;
                Applied = false;
                Error = "not installed";
            }

            public bool Required { get; }
            public bool Applied { get; set; }
            public string Error { get; set; }

            public void Fail(string error)
            {
                Applied = false;
                Error = string.IsNullOrWhiteSpace(error) ? "unknown error" : error;
            }
        }

        private readonly struct SpriteMaskState
        {
            private readonly bool hideLimb;
            private readonly List<WearableType> hideWearablesOfType;
            private readonly WearableSprite.ObscuringMode obscureOtherWearables;
            private readonly bool canBeHiddenByOtherWearables;

            public SpriteMaskState(WearableSprite sprite)
            {
                hideLimb = sprite.HideLimb;
                hideWearablesOfType = sprite.HideWearablesOfType;
                obscureOtherWearables = sprite.ObscureOtherWearables;
                canBeHiddenByOtherWearables = sprite.CanBeHiddenByOtherWearables;
            }

            public void Restore(WearableSprite sprite)
            {
                if (sprite == null) { return; }
                sprite.HideLimb = hideLimb;
                sprite.HideWearablesOfType = hideWearablesOfType;
                sprite.ObscureOtherWearables = obscureOtherWearables;
                sprite.CanBeHiddenByOtherWearables = canBeHiddenByOtherWearables;
            }
        }
    }

}
