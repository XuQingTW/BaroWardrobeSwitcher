using System;
using System.Collections.Generic;
using System.Linq;
using Barotrauma;
using Barotrauma.Items.Components;

namespace BaroWardrobeSwitcher
{
    /// <summary>
    /// Owns one independently initialized sprite and the stable metadata needed by the
    /// renderer. It never owns or removes a real inventory item.
    /// </summary>
    internal sealed class FashionSpriteDescriptor : IDisposable
    {
        private bool disposed;

        private FashionSpriteDescriptor(
            WearableSprite sprite,
            IEnumerable<InvSlotType> allowedSlots,
            string sourceIdentifier,
            string sourceContentPackage,
            string resolvedSpritePath)
        {
            Sprite = sprite;
            AllowedSlots = new HashSet<InvSlotType>(allowedSlots ?? Enumerable.Empty<InvSlotType>());
            SourceIdentifier = sourceIdentifier ?? string.Empty;
            SourceContentPackage = sourceContentPackage ?? string.Empty;
            ResolvedSpritePath = resolvedSpritePath ?? string.Empty;
        }

        public WearableSprite Sprite { get; }

        public HashSet<InvSlotType> AllowedSlots { get; }

        public string SourceIdentifier { get; }

        public string SourceContentPackage { get; }

        public string ResolvedSpritePath { get; }

        public bool IsValid(out string error)
        {
            if (disposed)
            {
                error = "descriptor disposed";
                return false;
            }
            if (Sprite == null)
            {
                error = "sprite missing";
                return false;
            }
            if (!Sprite.IsInitialized)
            {
                error = "wearable sprite not initialized";
                return false;
            }
            if (Sprite.SourceElement == null)
            {
                error = "source element missing";
                return false;
            }
            if (Sprite.Sprite == null)
            {
                error = "render sprite missing";
                return false;
            }
            // Limb.Draw calls Enumerable.Any on this collection. A null collection was
            // the direct cause of the confirmed ArgumentNullException("source") crash.
            if (Sprite.CanBeHiddenByItem == null)
            {
                error = "CanBeHiddenByItem was not initialized";
                return false;
            }
            error = null;
            return true;
        }

        public static bool TryCreate(
            Character character,
            Item sourceItem,
            WearableSprite source,
            bool preserveMasks,
            out FashionSpriteDescriptor descriptor,
            out string error)
        {
            descriptor = null;
            error = null;
            if (character == null)
            {
                error = "character missing";
                return false;
            }
            if (source == null)
            {
                error = "source wearable sprite missing";
                return false;
            }
            if (source.SourceElement == null)
            {
                error = "source wearable element missing";
                return false;
            }
            if (source.WearableComponent == null)
            {
                error = "source wearable component missing";
                return false;
            }

            WearableSprite ownedSprite = null;
            Sprite clonedSprite = null;
            try
            {
                // Live inventory items have normally initialized their wearable sprites
                // already. Prefab fallback items have not, so initialize the source first
                // to resolve override package paths, gender variants and sheet indices.
                if (!source.IsInitialized)
                {
                    source.Init(character);
                }
                if (!source.IsInitialized)
                {
                    throw new InvalidOperationException("source wearable sprite was not initialized");
                }
                if (source.Sprite == null)
                {
                    throw new InvalidOperationException("source render sprite missing after initialization");
                }

                // Use the official item-sprite lifecycle. This creates a distinct Sprite
                // resource and resolves gender/variant/relative paths for the target
                // character. MemberwiseClone is deliberately forbidden here.
                ownedSprite = new WearableSprite(source.SourceElement, source.WearableComponent, source.Variant);
                ownedSprite.Init(character);

                // The constructor above can resolve an inherited/vanilla XML path instead
                // of the final runtime sprite selected by a content-package Override.
                // Replace that temporary resource with an independently ref-counted copy
                // of the actual initialized source sprite, then preserve all mutable
                // rendering state that the engine may have adjusted at runtime.
                Sprite initializedSprite = ownedSprite.Sprite;
                clonedSprite = CloneResolvedSprite(source.Sprite);
                CopyRuntimeVisualState(source, ownedSprite, character);
                ownedSprite.Sprite = clonedSprite;
                clonedSprite = null;
                if (!ReferenceEquals(initializedSprite, ownedSprite.Sprite))
                {
                    RemoveSprite(initializedSprite);
                }

                // Wardrobe's cosmetic masking policy intentionally runs after the exact
                // runtime state has been copied. Light components and functional item
                // components are never copied from the source item.
                if (!preserveMasks)
                {
                    ownedSprite.HideWearablesOfType = new List<WearableType>();
                    ownedSprite.ObscureOtherWearables = WearableSprite.ObscuringMode.None;
                    ownedSprite.CanBeHiddenByOtherWearables = false;
                    if (IsHeadVisual(ownedSprite, source.WearableComponent.AllowedSlots))
                    {
                        ownedSprite.HideLimb = false;
                    }
                }

                descriptor = new FashionSpriteDescriptor(
                    ownedSprite,
                    source.WearableComponent.AllowedSlots,
                    sourceItem?.Prefab?.Identifier.ToString(),
                    sourceItem?.Prefab?.ContentPackage?.Name,
                    GetResolvedSpritePath(ownedSprite.Sprite));
                if (!descriptor.IsValid(out error))
                {
                    descriptor.Dispose();
                    descriptor = null;
                    return false;
                }
                return true;
            }
            catch (Exception ex)
            {
                RemoveSprite(clonedSprite);
                try { ownedSprite?.Remove(); } catch { }
                error = ex.GetType().Name + ": " + ex.Message;
                return false;
            }
        }

        public void Dispose()
        {
            if (disposed) { return; }
            disposed = true;
            try
            {
                Sprite?.Remove();
            }
            catch
            {
                // Cleanup is best effort and must not prevent other descriptors from
                // releasing their resources.
            }
        }

        private static bool IsHeadVisual(WearableSprite sprite, IEnumerable<InvSlotType> slots)
        {
            return sprite?.Limb == LimbType.Head ||
                   (slots?.Contains(InvSlotType.Head) ?? false) ||
                   (slots?.Contains(InvSlotType.Headset) ?? false);
        }

        private static Sprite CloneResolvedSprite(Sprite source)
        {
            if (source == null) { throw new ArgumentNullException(nameof(source)); }
            Sprite clone = null;
            try
            {
                clone = new Sprite(source);
                clone.SourceRect = source.SourceRect;
                clone.RelativeSize = source.RelativeSize;
                clone.RelativeOrigin = source.RelativeOrigin;
                clone.Origin = source.Origin;
                clone.Depth = source.Depth;
                clone.size = source.size;
                clone.offset = source.offset;
                clone.rotation = source.rotation;
                clone.effects = source.effects;
                return clone;
            }
            catch
            {
                RemoveSprite(clone);
                throw;
            }
        }

        private static void CopyRuntimeVisualState(
            WearableSprite source,
            WearableSprite target,
            Character character)
        {
            target.Type = source.Type;
            target.Limb = source.Limb;
            target.DepthLimb = source.DepthLimb;
            target.Scale = source.Scale;
            target.Rotation = source.Rotation;
            target.InheritLimbDepth = source.InheritLimbDepth;
            target.InheritOrigin = source.InheritOrigin;
            target.InheritScale = source.InheritScale;
            target.InheritSourceRect = source.InheritSourceRect;
            target.IgnoreLimbScale = source.IgnoreLimbScale;
            target.IgnoreRagdollScale = source.IgnoreRagdollScale;
            target.IgnoreTextureScale = source.IgnoreTextureScale;
            target.HideLimb = source.HideLimb;
            target.HideWearablesOfType = source.HideWearablesOfType == null
                ? null
                : new List<WearableType>(source.HideWearablesOfType);
            target.ObscureOtherWearables = source.ObscureOtherWearables;
            target.CanBeHiddenByOtherWearables = source.CanBeHiddenByOtherWearables;
            target.CanBeHiddenByItem = source.CanBeHiddenByItem;
            target.SheetIndex = source.SheetIndex;
            target.Sound = source.Sound;
            target.SpritePath = source.SpritePath;
            target.UnassignedSpritePath = source.UnassignedSpritePath;
            target.Variant = source.Variant;
            target.Picker = character;
        }

        private static string GetResolvedSpritePath(Sprite sprite)
        {
            if (sprite == null) { return string.Empty; }
            try
            {
                if (!string.IsNullOrWhiteSpace(sprite.FullPath))
                {
                    return sprite.FullPath;
                }
            }
            catch
            {
                // Fall through to the content path value.
            }
            try
            {
                return sprite.FilePath?.Value ?? string.Empty;
            }
            catch
            {
                return string.Empty;
            }
        }

        private static void RemoveSprite(Sprite sprite)
        {
            try { sprite?.Remove(); } catch { }
        }
    }

    /// <summary>
    /// Aggregate root for all renderer-owned state of one character.
    /// </summary>
    internal sealed class RenderSession : IDisposable
    {
        private readonly Dictionary<WearableSprite, FashionSpriteDescriptor> descriptorsBySprite =
            new Dictionary<WearableSprite, FashionSpriteDescriptor>();
        private readonly List<Item> ownedTemporaryItems = new List<Item>();
        private readonly Dictionary<Limb, object> activeDraws = new Dictionary<Limb, object>();
        private RenderSession pendingCapture;
        private bool disposed;

        public RenderSession(Character character)
        {
            Character = character ?? throw new ArgumentNullException(nameof(character));
        }

        public Character Character { get; }

        public Dictionary<Tuple<WearableType, LimbType>, List<FashionSpriteDescriptor>> SpritesBySlot { get; } =
            new Dictionary<Tuple<WearableType, LimbType>, List<FashionSpriteDescriptor>>();

        public HashSet<WearableType> HiddenWearableTypes { get; } = new HashSet<WearableType>();

        public HashSet<InvSlotType> EmptySlots { get; set; } = new HashSet<InvSlotType>();

        public HashSet<InvSlotType> SavedSlots { get; set; } = new HashSet<InvSlotType>();

        public HashSet<WearableSprite> EquipmentMasksToSanitize { get; } = new HashSet<WearableSprite>();

        public List<object> FashionAnimations { get; } = new List<object>();

        public List<FashionSoundEffect> FashionSounds { get; } = new List<FashionSoundEffect>();

        public List<FashionComponentSound> FashionComponentSounds { get; } = new List<FashionComponentSound>();

        public HashSet<StatusEffect> SuppressedEquipmentSounds { get; } = new HashSet<StatusEffect>();

        public HashSet<ItemComponent> SuppressedEquipmentComponentSounds { get; } = new HashSet<ItemComponent>();

        public FashionEffectPolicy EffectPolicy { get; } = new FashionEffectPolicy();

        public int FashionSoundCursor { get; set; }

        public int FashionComponentSoundCursor { get; set; }

        public int ForceHideAttachmentMask { get; set; }

        public int ForceShowAttachmentMask { get; set; }

        public bool EmptyLook { get; set; }

        public bool IsActive { get; set; }

        public bool IsValid { get; private set; } = true;

        public string Error { get; private set; }

        public int SpriteCount => descriptorsBySprite.Count;

        public IEnumerable<FashionSpriteDescriptor> Descriptors => descriptorsBySprite.Values;

        public bool HasPendingCapture => pendingCapture != null;

        public bool IsCommitted { get; private set; }

        // New captures write into a child session so the committed look remains
        // drawable until the entire replacement has validated successfully.
        public RenderSession CaptureTarget => pendingCapture ?? this;

        public RenderSession BeginPendingCapture()
        {
            if (disposed) { throw new ObjectDisposedException(nameof(RenderSession)); }
            pendingCapture?.Dispose();
            pendingCapture = new RenderSession(Character);
            return pendingCapture;
        }

        public RenderSession DetachPendingCapture()
        {
            RenderSession detached = pendingCapture;
            pendingCapture = null;
            return detached;
        }

        public bool AbortPendingCapture()
        {
            if (pendingCapture == null) { return false; }
            RenderSession aborted = pendingCapture;
            pendingCapture = null;
            aborted.Dispose();
            return true;
        }

        public void MarkCommitted()
        {
            if (disposed) { throw new ObjectDisposedException(nameof(RenderSession)); }
            IsCommitted = true;
        }

        public void Add(FashionSpriteDescriptor descriptor)
        {
            if (descriptor == null) { throw new ArgumentNullException(nameof(descriptor)); }
            if (!descriptor.IsValid(out string error))
            {
                throw new InvalidOperationException(error);
            }
            Tuple<WearableType, LimbType> key = Tuple.Create(descriptor.Sprite.Type, descriptor.Sprite.Limb);
            if (!SpritesBySlot.TryGetValue(key, out List<FashionSpriteDescriptor> descriptors))
            {
                descriptors = new List<FashionSpriteDescriptor>();
                SpritesBySlot[key] = descriptors;
            }
            descriptors.Add(descriptor);
            descriptorsBySprite[descriptor.Sprite] = descriptor;
        }

        public bool TryGetDescriptor(WearableSprite sprite, out FashionSpriteDescriptor descriptor)
        {
            descriptor = null;
            return sprite != null && descriptorsBySprite.TryGetValue(sprite, out descriptor);
        }

        public void AddOwnedTemporaryItem(Item item)
        {
            if (item != null && !ownedTemporaryItems.Contains(item))
            {
                ownedTemporaryItems.Add(item);
            }
        }

        public void MarkInvalid(string error)
        {
            IsValid = false;
            IsActive = false;
            Error = string.IsNullOrWhiteSpace(error) ? "invalid render session" : error;
        }

        public bool Validate(out string error)
        {
            if (disposed)
            {
                error = "render session disposed";
                return false;
            }
            if (!IsValid)
            {
                error = Error ?? "invalid render session";
                return false;
            }
            foreach (FashionSpriteDescriptor descriptor in descriptorsBySprite.Values)
            {
                if (!descriptor.IsValid(out error))
                {
                    MarkInvalid(error);
                    return false;
                }
            }
            error = null;
            return true;
        }

        public bool TryEnterDraw(Limb limb, object context)
        {
            if (limb == null || activeDraws.ContainsKey(limb)) { return false; }
            activeDraws[limb] = context;
            return true;
        }

        public bool TryGetDrawContext(Limb limb, out object context)
        {
            context = null;
            return limb != null && activeDraws.TryGetValue(limb, out context);
        }

        public void ExitDraw(Limb limb)
        {
            if (limb != null) { activeDraws.Remove(limb); }
        }

        public void Dispose()
        {
            if (disposed) { return; }
            disposed = true;
            IsActive = false;
            AbortPendingCapture();
            activeDraws.Clear();

            foreach (FashionSpriteDescriptor descriptor in descriptorsBySprite.Values.Distinct().ToList())
            {
                descriptor.Dispose();
            }
            descriptorsBySprite.Clear();
            SpritesBySlot.Clear();
            EquipmentMasksToSanitize.Clear();
            FashionAnimations.Clear();
            FashionSounds.Clear();
            FashionComponentSounds.Clear();
            SuppressedEquipmentSounds.Clear();
            SuppressedEquipmentComponentSounds.Clear();

            // Temporary prefab items stay alive for exactly as long as any descriptor
            // or captured effect can reference their components. Remove them last.
            foreach (Item item in ownedTemporaryItems.ToList())
            {
                try { item?.Remove(); } catch { }
            }
            ownedTemporaryItems.Clear();
        }
    }

    internal sealed class FashionSoundEffect
    {
        public FashionSoundEffect(StatusEffect statusEffect)
        {
            StatusEffect = statusEffect;
        }

        public StatusEffect StatusEffect { get; }
    }

    internal sealed class FashionComponentSound
    {
        public FashionComponentSound(ItemComponent component, ActionType actionType)
        {
            Component = component;
            ActionType = actionType;
        }

        public ItemComponent Component { get; }

        public ActionType ActionType { get; }
    }
}
