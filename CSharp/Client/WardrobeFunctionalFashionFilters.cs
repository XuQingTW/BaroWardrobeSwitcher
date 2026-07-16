using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using Barotrauma;
using Barotrauma.Items.Components;
using Barotrauma.LuaCs;

namespace BaroWardrobeSwitcher
{
    /// <summary>
    /// Kept as an assembly plugin so existing source-loading configurations continue to
    /// discover this file. The policy is now composed directly by VisualOverride; it no
    /// longer Harmony-patches private methods in its own assembly.
    /// </summary>
    public sealed class WardrobeFunctionalFashionFiltersPlugin : IAssemblyPlugin
    {
        public void Initialize()
        {
            LuaCsLogger.Log("[Baro Wardrobe Switcher] Fashion effect policy initialized.");
        }

        public void OnLoadCompleted() { }

        public void PreInitPatching() { }

        public void Dispose()
        {
            LuaCsLogger.Log("[Baro Wardrobe Switcher] Fashion effect policy disposed.");
        }
    }

    /// <summary>
    /// Decides which functional effects are safe to reproduce for a cosmetic look.
    /// Stable prefab tags/components are preferred. Identifier/name matching remains as
    /// a one-release compatibility fallback for third-party items without useful tags.
    /// </summary>
    internal sealed class FashionEffectPolicy
    {
        private static readonly Identifier DeepDivingTag = new Identifier("deepdiving");
        private static readonly Identifier DeepDivingLargeTag = new Identifier("deepdivinglarge");
        private static readonly FieldInfo SoundsField =
            typeof(StatusEffect).GetField("sounds", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        private static readonly FieldInfo ComponentSoundsField =
            typeof(ItemComponent).GetField("sounds", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        private static readonly FieldInfo PropertyConditionalsField =
            typeof(StatusEffect).GetField("propertyConditionals", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        private static readonly FieldInfo RequiredItemsField =
            typeof(StatusEffect).GetField("requiredItems", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        private static readonly FieldInfo PlaySoundOnRequiredItemFailureField =
            typeof(StatusEffect).GetField("playSoundOnRequiredItemFailure", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        private readonly FashionEffectDiagnostics diagnostics = new FashionEffectDiagnostics();

        public bool ShouldCaptureAnimation(Item item, object animationInfo)
        {
            bool sealedSuit = IsSealedSuit(item);
            bool filtered = sealedSuit
                ? IsMovementAnimation(animationInfo)
                : IsLargeEquipmentMovementAnimation(animationInfo);
            if (!filtered) { return true; }

            diagnostics.FilteredMovementAnimations++;
            diagnostics.RememberPolicy(PolicyDescription(item));
            return false;
        }

        public bool ShouldCaptureStatusSounds(Item item)
        {
            if (!ShouldSuppressCosmeticSounds(item)) { return true; }
            int count = CountStatusSounds(item);
            if (count > 0)
            {
                diagnostics.SuppressedStatusSounds += count;
                diagnostics.RememberPolicy(PolicyDescription(item));
            }
            return false;
        }

        public bool ShouldCaptureStatusSound(Item item, StatusEffect statusEffect)
        {
            if (!IsFunctionalEquipmentAlarm(statusEffect)) { return true; }
            diagnostics.ExcludedFunctionalAlarms++;
            diagnostics.RememberPolicy(PolicyDescription(item));
            return false;
        }

        public bool ShouldCaptureComponentSounds(Item item)
        {
            if (!ShouldSuppressCosmeticSounds(item)) { return true; }
            int count = CountComponentSounds(item);
            if (count > 0)
            {
                diagnostics.SuppressedItemSounds += count;
                diagnostics.RememberPolicy(PolicyDescription(item));
            }
            return false;
        }

        public bool ShouldPreserveSealedSuitMasks(Item item)
        {
            if (!IsSealedSuit(item)) { return false; }
            diagnostics.PreservedSealedMaskSprites++;
            diagnostics.RememberPolicy(PolicyDescription(item));
            return true;
        }

        public string AppendDebugStatus(string status)
        {
            string suffix = diagnostics.Describe();
            return string.IsNullOrWhiteSpace(suffix)
                ? status
                : (status ?? string.Empty) + ", fashionPolicy=" + suffix;
        }

        internal static bool IsFunctionalEquipmentAlarm(StatusEffect statusEffect)
        {
            if (statusEffect == null) { return false; }
            try
            {
                // These fields are pinned by the compatibility probe. If a future
                // game build removes one, fail open and let Barotrauma own the sound
                // lifecycle instead of risking a swallowed safety warning.
                if (PropertyConditionalsField == null ||
                    RequiredItemsField == null ||
                    PlaySoundOnRequiredItemFailureField == null)
                {
                    return true;
                }

                if (HasEntriesOrCannotInspect(PropertyConditionalsField, statusEffect) ||
                    HasEntriesOrCannotInspect(RequiredItemsField, statusEffect))
                {
                    return true;
                }

                object playOnFailure = PlaySoundOnRequiredItemFailureField.GetValue(statusEffect);
                if (playOnFailure is bool enabled) { return enabled; }
                return playOnFailure != null;
            }
            catch
            {
                return true;
            }
        }

        private static bool IsSealedSuit(Item item)
        {
            if (HasTag(item, DeepDivingTag) || HasTag(item, DeepDivingLargeTag))
            {
                return true;
            }
            return IsSealedSuitText(NormalizedItemText(item));
        }

        private static bool ShouldSuppressCosmeticSounds(Item item)
        {
            if (IsSealedSuit(item)) { return true; }

            string identifier = ItemIdentifier(item);
            if (identifier.Equals("autoinjectorheadset", StringComparison.OrdinalIgnoreCase) ||
                identifier.Equals("injectorheadset", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }

            // Compatibility fallback for older and third-party prefabs that expose no
            // functional tag. Do not use localized display names unless needed.
            string text = NormalizedItemText(item);
            return text.Contains("autoinjectorheadset") ||
                   text.Contains("injectorheadset") ||
                   text.Contains("autoinjector");
        }

        private static bool HasTag(Item item, Identifier tag)
        {
            try
            {
                return item != null && (item.HasTag(tag) || (item.Prefab?.Tags?.Contains(tag) ?? false));
            }
            catch
            {
                return false;
            }
        }

        private static int CountStatusSounds(Item item)
        {
            if (item?.Components == null || SoundsField == null) { return 0; }
            int count = 0;
            foreach (ItemComponent component in item.Components)
            {
                if (component?.statusEffectLists == null ||
                    !component.statusEffectLists.TryGetValue(ActionType.OnWearing, out List<StatusEffect> effects))
                {
                    continue;
                }
                count += effects.Count(HasSounds);
            }
            return count;
        }

        private static int CountComponentSounds(Item item)
        {
            if (item?.Components == null || ComponentSoundsField == null) { return 0; }
            int count = 0;
            foreach (ItemComponent component in item.Components)
            {
                try
                {
                    if (ComponentSoundsField.GetValue(component) is IDictionary sounds)
                    {
                        count += sounds.Count;
                    }
                }
                catch
                {
                    // Optional diagnostics must never make capture fail.
                }
            }
            return count;
        }

        private static bool HasSounds(StatusEffect statusEffect)
        {
            if (statusEffect == null || SoundsField == null) { return false; }
            try
            {
                if (!(SoundsField.GetValue(statusEffect) is IEnumerable sounds)) { return false; }
                foreach (object sound in sounds)
                {
                    if (sound != null) { return true; }
                }
            }
            catch
            {
                // Optional diagnostics must never make capture fail.
            }
            return false;
        }

        private static bool HasEntries(IEnumerable values)
        {
            if (values == null) { return false; }
            foreach (object value in values)
            {
                if (value != null) { return true; }
            }
            return false;
        }

        private static bool HasEntriesOrCannotInspect(FieldInfo field, StatusEffect statusEffect)
        {
            object value = field.GetValue(statusEffect);
            if (value == null) { return false; }
            if (!(value is IEnumerable values)) { return true; }
            return HasEntries(values);
        }

        private static bool IsSealedSuitText(string text)
        {
            if (string.IsNullOrEmpty(text)) { return false; }
            return text.Contains("exosuit") ||
                   text.Contains("divingsuit") ||
                   text.Contains("divesuit") ||
                   text.Contains("pucs") ||
                   text.Contains("puccs");
        }

        private static string PolicyDescription(Item item)
        {
            if (IsSealedSuit(item)) { return "sealed-suit"; }
            if (ShouldSuppressCosmeticSounds(item)) { return "functional-soundless"; }
            return "movement-filter";
        }

        private static string NormalizedItemText(Item item)
        {
            return Normalize(ItemIdentifier(item) + " " + ItemName(item));
        }

        private static string ItemIdentifier(Item item)
        {
            try
            {
                return item?.Prefab?.Identifier.ToString() ?? string.Empty;
            }
            catch
            {
                return string.Empty;
            }
        }

        private static string ItemName(Item item)
        {
            try
            {
                if (item?.Prefab?.Name != null) { return item.Prefab.Name.ToString(); }
                return item?.Name.ToString() ?? string.Empty;
            }
            catch
            {
                return string.Empty;
            }
        }

        private static string Normalize(string value)
        {
            if (string.IsNullOrWhiteSpace(value)) { return string.Empty; }
            return new string(value.ToLowerInvariant().Where(char.IsLetterOrDigit).ToArray());
        }

        private static bool IsMovementAnimation(object animationInfo)
        {
            if (animationInfo == null) { return false; }
            try
            {
                string type = animationInfo.GetType().GetProperty("Type")?.GetValue(animationInfo)?.ToString();
                return string.Equals(type, "Walk", StringComparison.OrdinalIgnoreCase) ||
                       string.Equals(type, "Run", StringComparison.OrdinalIgnoreCase);
            }
            catch
            {
                return false;
            }
        }

        private static bool IsLargeEquipmentMovementAnimation(object animationInfo)
        {
            if (!IsMovementAnimation(animationInfo)) { return false; }
            try
            {
                string file = animationInfo.GetType().GetProperty("File")?.GetValue(animationInfo)?.ToString() ?? string.Empty;
                return file.IndexOf("Exosuit", StringComparison.OrdinalIgnoreCase) >= 0 ||
                       file.IndexOf("DivingSuit", StringComparison.OrdinalIgnoreCase) >= 0;
            }
            catch
            {
                return false;
            }
        }

        private sealed class FashionEffectDiagnostics
        {
            private readonly HashSet<string> policies = new HashSet<string>();

            public int FilteredMovementAnimations { get; set; }
            public int SuppressedStatusSounds { get; set; }
            public int ExcludedFunctionalAlarms { get; set; }
            public int SuppressedItemSounds { get; set; }
            public int PreservedSealedMaskSprites { get; set; }

            public void RememberPolicy(string policy)
            {
                if (!string.IsNullOrWhiteSpace(policy)) { policies.Add(policy); }
            }

            public string Describe()
            {
                List<string> parts = new List<string>();
                if (FilteredMovementAnimations > 0) { parts.Add("filteredMovementAnimations=" + FilteredMovementAnimations); }
                if (SuppressedStatusSounds > 0) { parts.Add("suppressedStatusSounds=" + SuppressedStatusSounds); }
                if (ExcludedFunctionalAlarms > 0) { parts.Add("excludedFunctionalAlarms=" + ExcludedFunctionalAlarms); }
                if (SuppressedItemSounds > 0) { parts.Add("suppressedItemSounds=" + SuppressedItemSounds); }
                if (PreservedSealedMaskSprites > 0) { parts.Add("preservedSealedMaskSprites=" + PreservedSealedMaskSprites); }
                if (policies.Count > 0) { parts.Add("policies=" + string.Join("/", policies.OrderBy(policy => policy))); }
                return string.Join(";", parts);
            }
        }
    }
}
