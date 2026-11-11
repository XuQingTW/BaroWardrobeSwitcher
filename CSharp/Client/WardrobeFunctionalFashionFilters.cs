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
        // 相容其他模組時優先補 tag／元件判斷；名稱比對僅作缺少標記時的後備。
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

        // 捕捉外觀動畫與抑制真裝備動畫是不同方向；修改規則時要一起檢查兩者。
        public static bool ShouldCaptureAnimation(Item item, object animationInfo)
        {
            bool sealedSuit = IsSealedSuit(item);
            return !(sealedSuit
                ? IsMovementAnimation(animationInfo)
                : IsLargeEquipmentMovementAnimation(animationInfo));
        }

        public static bool ShouldSuppressEquipmentAnimation(Item item, object animationInfo)
        {
            return IsSealedSuit(item) && IsMovementAnimation(animationInfo);
        }

        public static bool ShouldKeepComponentLoopAlive(ActionType actionType)
        {
            return actionType == ActionType.Always || actionType == ActionType.OnWearing;
        }

        // 受條件／所需物品控制的音效交給原遊戲，例如警報，不當成純外觀音效複製。
        // 反射欄位失效時回傳 true，讓上層保留遊戲對這類音效的控制。
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

        internal static bool IsSealedSuit(Item item)
        {
            if (HasTag(item, DeepDivingTag) || HasTag(item, DeepDivingLargeTag))
            {
                return true;
            }
            string text = NormalizedItemText(item);
            return text.Contains("exosuit") ||
                   text.Contains("divingsuit") ||
                   text.Contains("divesuit") ||
                   text.Contains("pucs") ||
                   text.Contains("puccs");
        }

        public static bool ShouldCaptureItemSounds(Item item)
        {
            if (IsSealedSuit(item)) { return false; }

            // Compatibility fallback for older and third-party prefabs that expose no
            // functional tag. Do not use localized display names unless needed.
            string text = NormalizedItemText(item);
            return !text.Contains("injectorheadset") && !text.Contains("autoinjector");
        }

        private static bool HasTag(Item item, Identifier tag)
        {
            return item != null && (item.HasTag(tag) || (item.Prefab?.Tags?.Contains(tag) ?? false));
        }

        private static bool HasEntriesOrCannotInspect(FieldInfo field, StatusEffect statusEffect)
        {
            object value = field.GetValue(statusEffect);
            if (value == null) { return false; }
            if (!(value is IEnumerable values)) { return true; }
            foreach (object entry in values)
            {
                if (entry != null) { return true; }
            }
            return false;
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

        private static string NormalizedItemText(Item item)
        {
            string name = item?.Prefab?.Name?.ToString() ?? item?.Name?.ToString() ?? string.Empty;
            string text = item?.Prefab?.Identifier.ToString() + " " + name;
            return new string(text.ToLowerInvariant().Where(char.IsLetterOrDigit).ToArray());
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
