using System;
using System.Collections;
using System.Linq;
using System.Reflection;
using Barotrauma;

namespace BaroWardrobeSwitcher
{
    /// <summary>
    /// Decides which functional effects are safe to reproduce for a cosmetic look.
    /// Stable prefab tags/components are preferred. Identifier/name matching remains as
    /// a one-release compatibility fallback for third-party items without useful tags.
    /// </summary>
    internal static class FashionEffectPolicy
    {
        private static readonly Identifier DeepDivingTag = new Identifier("deepdiving");
        private static readonly Identifier DeepDivingLargeTag = new Identifier("deepdivinglarge");
        private static readonly FieldInfo PropertyConditionalsField =
            typeof(StatusEffect).GetField("propertyConditionals", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        private static readonly FieldInfo RequiredItemsField =
            typeof(StatusEffect).GetField("requiredItems", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        private static readonly FieldInfo PlaySoundOnRequiredItemFailureField =
            typeof(StatusEffect).GetField("playSoundOnRequiredItemFailure", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        private static readonly FieldInfo OnlyInsideField =
            typeof(StatusEffect).GetField("OnlyInside", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        private static readonly FieldInfo OnlyOutsideField =
            typeof(StatusEffect).GetField("OnlyOutside", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        private static readonly FieldInfo TargetIdentifiersField =
            typeof(StatusEffect).GetField("TargetIdentifiers", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        private static readonly FieldInfo TargetItemComponentField =
            typeof(StatusEffect).GetField("TargetItemComponent", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);

        public static bool ShouldCaptureAnimation(Item item, object animationInfo)
        {
            bool sealedSuit = IsSealedSuit(item);
            return !(sealedSuit
                ? IsMovementAnimation(animationInfo)
                : IsLargeEquipmentMovementAnimation(animationInfo));
        }

        public static bool ShouldCaptureItemSounds(Item item) => !ShouldSuppressCosmeticSounds(item);

        public static bool ShouldCaptureStatusEffect(StatusEffect statusEffect)
        {
            return !IsStateDependentStatusEffect(statusEffect);
        }

        public static bool ShouldCaptureStatusSound(StatusEffect statusEffect)
        {
            return ShouldCaptureStatusEffect(statusEffect);
        }

        public static bool ShouldSuppressEquipmentAnimation(Item item, object animationInfo)
        {
            return IsSealedSuit(item) && IsMovementAnimation(animationInfo);
        }

        public static bool ShouldKeepComponentLoopAlive(ActionType actionType)
        {
            return actionType == ActionType.Always || actionType == ActionType.OnWearing;
        }

        public static bool ShouldPreserveSealedSuitMasks(Item item)
        {
            return IsSealedSuit(item);
        }

        internal static bool IsFunctionalEquipmentAlarm(StatusEffect statusEffect)
        {
            return IsStateDependentStatusEffect(statusEffect);
        }

        internal static bool IsStateDependentStatusEffect(StatusEffect statusEffect)
        {
            if (statusEffect == null) { return false; }
            try
            {
                // These fields are pinned by the compatibility probe. If a future
                // game build removes one, fail open and let Barotrauma own the sound
                // lifecycle instead of risking a swallowed safety warning.
                if (PropertyConditionalsField == null ||
                    RequiredItemsField == null ||
                    PlaySoundOnRequiredItemFailureField == null ||
                    OnlyInsideField == null ||
                    OnlyOutsideField == null ||
                    TargetIdentifiersField == null ||
                    TargetItemComponentField == null)
                {
                    return true;
                }

                if (HasEntriesOrCannotInspect(PropertyConditionalsField, statusEffect) ||
                    HasEntriesOrCannotInspect(RequiredItemsField, statusEffect) ||
                    IsEnabledOrCannotInspect(OnlyInsideField, statusEffect) ||
                    IsEnabledOrCannotInspect(OnlyOutsideField, statusEffect) ||
                    HasEntriesOrCannotInspect(TargetIdentifiersField, statusEffect) ||
                    HasTextOrCannotInspect(TargetItemComponentField, statusEffect))
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

        private static bool HasEntries(IEnumerable values) =>
            values?.Cast<object>().Any(value => value != null) ?? false;

        private static bool HasEntriesOrCannotInspect(FieldInfo field, StatusEffect statusEffect)
        {
            object value = field.GetValue(statusEffect);
            if (value == null) { return false; }
            if (!(value is IEnumerable values)) { return true; }
            return HasEntries(values);
        }

        private static bool IsEnabledOrCannotInspect(FieldInfo field, StatusEffect statusEffect)
        {
            object value = field.GetValue(statusEffect);
            if (value is bool enabled) { return enabled; }
            return value != null;
        }

        private static bool HasTextOrCannotInspect(FieldInfo field, StatusEffect statusEffect)
        {
            object value = field.GetValue(statusEffect);
            if (value == null) { return false; }
            if (value is string text) { return !string.IsNullOrWhiteSpace(text); }
            return true;
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

        internal static bool IsMovementAnimation(object animationInfo)
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

        internal static bool IsLargeEquipmentMovementAnimation(object animationInfo)
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

    }
}
