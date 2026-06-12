using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using Barotrauma;
using Barotrauma.Items.Components;
using Barotrauma.LuaCs;
using HarmonyLib;

namespace BaroWardrobeSwitcher
{
    public sealed class WardrobeFunctionalFashionFiltersPlugin : IAssemblyPlugin
    {
        private Harmony harmonyInstance;

        public void Initialize()
        {
            harmonyInstance = new Harmony("BaroWardrobeSwitcher.FunctionalFashionFilters");
            LuaCsLogger.Log("[Baro Wardrobe Switcher] Functional fashion filters initializing.");
        }

        public void OnLoadCompleted()
        {
            FunctionalFashionFilters.InstallPatches(harmonyInstance);
            LuaCsLogger.Log("[Baro Wardrobe Switcher] Functional fashion filters loaded.");
        }

        public void PreInitPatching() { }

        public void Dispose()
        {
            FunctionalFashionFilters.Clear();
            harmonyInstance?.UnpatchSelf();
            LuaCsLogger.Log("[Baro Wardrobe Switcher] Functional fashion filters disposed.");
        }
    }

    internal static class FunctionalFashionFilters
    {
        private static readonly MethodInfo CaptureFashionAnimationsMethod =
            AccessTools.Method(typeof(VisualOverride), "CaptureFashionAnimations");
        private static readonly MethodInfo CaptureFashionSoundsMethod =
            AccessTools.Method(typeof(VisualOverride), "CaptureFashionSounds");
        private static readonly MethodInfo CaptureFashionComponentSoundsMethod =
            AccessTools.Method(typeof(VisualOverride), "CaptureFashionComponentSounds");
        private static readonly MethodInfo CreateFashionSpriteCloneMethod =
            AccessTools.Method(typeof(VisualOverride), "CreateFashionSpriteClone");
        private static readonly MethodInfo GetCharacterDebugStatusMethod =
            AccessTools.Method(typeof(VisualOverride), "GetCharacterDebugStatus");
        private static readonly MethodInfo ClearCharacterMethod =
            AccessTools.Method(typeof(VisualOverride), "ClearCharacter");
        private static readonly MethodInfo ClearAllMethod =
            AccessTools.Method(typeof(VisualOverride), "ClearAll");
        private static readonly MethodInfo RestoreCharacterItemVisualsMethod =
            AccessTools.Method(typeof(VisualOverride), "RestoreCharacterItemVisuals");

        private static readonly FieldInfo FashionAnimationsField =
            AccessTools.Field(typeof(VisualOverride), "FashionAnimationsByCharacter");
        private static readonly FieldInfo AnimationsToTriggerField =
            AccessTools.Field(typeof(StatusEffect), "animationsToTrigger");
        private static readonly FieldInfo SoundsField =
            AccessTools.Field(typeof(StatusEffect), "sounds");
        private static readonly FieldInfo ComponentSoundsField =
            AccessTools.Field(typeof(ItemComponent), "sounds");
        private static readonly MethodInfo MemberwiseCloneMethod =
            AccessTools.Method(typeof(object), "MemberwiseClone") ??
            typeof(object).GetMethod("MemberwiseClone", BindingFlags.Instance | BindingFlags.NonPublic);

        private static readonly Dictionary<Character, FunctionalFilterDiagnostics> DiagnosticsByCharacter =
            new Dictionary<Character, FunctionalFilterDiagnostics>();

        public static void InstallPatches(Harmony harmony)
        {
            if (harmony == null) { return; }
            PatchTarget(harmony, "VisualOverride.CaptureFashionAnimations", CaptureFashionAnimationsMethod,
                prefix: AccessTools.Method(typeof(CaptureFashionAnimationsPatch), "Prefix"));
            PatchTarget(harmony, "VisualOverride.CaptureFashionSounds", CaptureFashionSoundsMethod,
                prefix: AccessTools.Method(typeof(CaptureFashionSoundsPatch), "Prefix"));
            PatchTarget(harmony, "VisualOverride.CaptureFashionComponentSounds", CaptureFashionComponentSoundsMethod,
                prefix: AccessTools.Method(typeof(CaptureFashionComponentSoundsPatch), "Prefix"));
            PatchTarget(harmony, "VisualOverride.CreateFashionSpriteClone", CreateFashionSpriteCloneMethod,
                prefix: AccessTools.Method(typeof(CreateFashionSpriteClonePatch), "Prefix"));
            PatchTarget(harmony, "VisualOverride.GetCharacterDebugStatus", GetCharacterDebugStatusMethod,
                postfix: AccessTools.Method(typeof(GetCharacterDebugStatusPatch), "Postfix"));
            PatchTarget(harmony, "VisualOverride.ClearCharacter", ClearCharacterMethod,
                postfix: AccessTools.Method(typeof(ClearCharacterPatch), "Postfix"));
            PatchTarget(harmony, "VisualOverride.ClearAll", ClearAllMethod,
                postfix: AccessTools.Method(typeof(ClearAllPatch), "Postfix"));
            PatchTarget(harmony, "VisualOverride.RestoreCharacterItemVisuals", RestoreCharacterItemVisualsMethod,
                postfix: AccessTools.Method(typeof(ClearCharacterPatch), "Postfix"));
        }

        public static void Clear()
        {
            DiagnosticsByCharacter.Clear();
        }

        private static void PatchTarget(
            Harmony harmony,
            string name,
            MethodBase target,
            MethodInfo prefix = null,
            MethodInfo postfix = null)
        {
            if (target == null)
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] Functional filter patch skipped; target missing: " + name);
                return;
            }
            try
            {
                harmony.Patch(
                    target,
                    prefix == null ? null : new HarmonyMethod(prefix),
                    postfix == null ? null : new HarmonyMethod(postfix));
            }
            catch (Exception ex)
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] Functional filter patch failed for " + name + ": " + ex.GetType().Name + ": " + ex.Message);
            }
        }

        public static bool TryCaptureFilteredFashionAnimations(object[] args, out int result)
        {
            result = 0;
            if (args == null || args.Length < 2) { return false; }
            Character character = args[0] as Character;
            Item item = args[1] as Item;
            if (character == null || item?.Components == null) { return false; }
            if (AnimationsToTriggerField == null || FashionAnimationsField == null) { return false; }

            Dictionary<Character, List<object>> animationsByCharacter = GetFashionAnimationsByCharacter();
            if (animationsByCharacter == null) { return false; }

            if (!animationsByCharacter.TryGetValue(character, out List<object> animationInfos))
            {
                animationInfos = new List<object>();
                animationsByCharacter[character] = animationInfos;
            }

            int captured = 0;
            int filtered = 0;
            bool isSealedSuit = IsSealedSuit(item);
            foreach (ItemComponent component in item.Components)
            {
                if (component?.statusEffectLists == null) { continue; }
                if (!component.statusEffectLists.TryGetValue(ActionType.OnWearing, out List<StatusEffect> statusEffects)) { continue; }
                foreach (StatusEffect statusEffect in statusEffects)
                {
                    IEnumerable animations = AnimationsToTriggerField.GetValue(statusEffect) as IEnumerable;
                    if (animations == null) { continue; }
                    foreach (object animationInfo in animations)
                    {
                        if (ShouldFilterFashionAnimation(isSealedSuit, animationInfo))
                        {
                            filtered++;
                            continue;
                        }

                        object boostedAnimationInfo = BoostFashionAnimationPriority(animationInfo);
                        if (boostedAnimationInfo == null || animationInfos.Contains(boostedAnimationInfo)) { continue; }
                        animationInfos.Add(boostedAnimationInfo);
                        captured++;
                    }
                }
            }

            if (filtered > 0)
            {
                Diagnostics(character).FilteredMovementAnimations += filtered;
                Diagnostics(character).RememberPolicy(PolicyDescription(item));
            }
            result = captured;
            return true;
        }

        public static bool ShouldSkipFashionStatusSounds(object[] args, out int result)
        {
            result = 0;
            if (args == null || args.Length < 2) { return false; }
            Character character = args[0] as Character;
            Item item = args[1] as Item;
            if (character == null || item == null) { return false; }
            if (!ShouldSuppressCosmeticSounds(item)) { return false; }

            result = 0;
            int suppressed = CountFashionStatusSounds(item);
            if (suppressed > 0)
            {
                Diagnostics(character).SuppressedStatusSounds += suppressed;
                Diagnostics(character).RememberPolicy(PolicyDescription(item));
            }
            return true;
        }

        public static bool ShouldSkipFashionComponentSounds(object[] args, out int result)
        {
            result = 0;
            if (args == null || args.Length < 2) { return false; }
            Character character = args[0] as Character;
            Item item = args[1] as Item;
            if (character == null || item == null) { return false; }
            if (!ShouldSuppressCosmeticSounds(item)) { return false; }

            int suppressed = CountFashionComponentSounds(item);
            if (suppressed > 0)
            {
                Diagnostics(character).SuppressedItemSounds += suppressed;
                Diagnostics(character).RememberPolicy(PolicyDescription(item));
            }
            return true;
        }

        public static bool TryCreateSealedSuitSpriteClone(object[] args, out WearableSprite result)
        {
            result = null;
            if (args == null || args.Length < 2) { return false; }
            Character character = args[0] as Character;
            WearableSprite original = args[1] as WearableSprite;
            if (original == null) { return false; }

            Item sourceItem = GetSourceItem(original);
            if (!ShouldPreserveSealedSuitMasks(sourceItem)) { return false; }

            WearableSprite clone = original;
            try
            {
                clone = MemberwiseCloneMethod?.Invoke(original, null) as WearableSprite ?? original;
            }
            catch (Exception ex)
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] Failed to clone sealed fashion sprite, using original: " + ex.GetType().Name + ": " + ex.Message);
            }

            if (character != null)
            {
                Diagnostics(character).PreservedSealedMaskSprites++;
                Diagnostics(character).RememberPolicy(PolicyDescription(sourceItem));
            }
            result = clone;
            return true;
        }

        public static void AppendDebugStatus(object[] args, ref string result)
        {
            if (args == null || args.Length < 1) { return; }
            Character character = args[0] as Character;
            if (character == null) { return; }
            if (!DiagnosticsByCharacter.TryGetValue(character, out FunctionalFilterDiagnostics diagnostics)) { return; }
            string suffix = diagnostics.Describe();
            if (string.IsNullOrWhiteSpace(suffix)) { return; }
            result = (result ?? string.Empty) + ", functionalFilters=" + suffix;
        }

        public static void ClearCharacterDiagnostics(object[] args)
        {
            if (args == null || args.Length < 1) { return; }
            Character character = args[0] as Character;
            if (character != null)
            {
                DiagnosticsByCharacter.Remove(character);
            }
        }

        private static FunctionalFilterDiagnostics Diagnostics(Character character)
        {
            if (!DiagnosticsByCharacter.TryGetValue(character, out FunctionalFilterDiagnostics diagnostics))
            {
                diagnostics = new FunctionalFilterDiagnostics();
                DiagnosticsByCharacter[character] = diagnostics;
            }
            return diagnostics;
        }

        private static Dictionary<Character, List<object>> GetFashionAnimationsByCharacter()
        {
            try
            {
                return FashionAnimationsField?.GetValue(null) as Dictionary<Character, List<object>>;
            }
            catch (Exception ex)
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] Failed to access fashion animation state: " + ex.GetType().Name + ": " + ex.Message);
                return null;
            }
        }

        private static int CountFashionStatusSounds(Item item)
        {
            if (item?.Components == null || SoundsField == null) { return 0; }
            int count = 0;
            foreach (ItemComponent component in item.Components)
            {
                if (component?.statusEffectLists == null) { continue; }
                if (!component.statusEffectLists.TryGetValue(ActionType.OnWearing, out List<StatusEffect> statusEffects)) { continue; }
                foreach (StatusEffect statusEffect in statusEffects)
                {
                    if (HasSounds(statusEffect)) { count++; }
                }
            }
            return count;
        }

        private static int CountFashionComponentSounds(Item item)
        {
            if (item?.Components == null || ComponentSoundsField == null) { return 0; }
            int count = 0;
            foreach (ItemComponent component in item.Components)
            {
                System.Collections.IDictionary sounds = ComponentSoundsField.GetValue(component) as System.Collections.IDictionary;
                if (sounds != null)
                {
                    count += sounds.Count;
                }
            }
            return count;
        }

        private static bool HasSounds(StatusEffect statusEffect)
        {
            if (statusEffect == null || SoundsField == null) { return false; }
            IEnumerable sounds = SoundsField.GetValue(statusEffect) as IEnumerable;
            if (sounds == null) { return false; }
            foreach (object sound in sounds)
            {
                if (sound != null) { return true; }
            }
            return false;
        }

        private static Item GetSourceItem(WearableSprite sprite)
        {
            ItemComponent component = sprite?.WearableComponent;
            if (component == null) { return null; }
            try
            {
                PropertyInfo property = component.GetType().GetProperty("Item", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic) ??
                                        typeof(ItemComponent).GetProperty("Item", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                return property?.GetValue(component) as Item;
            }
            catch
            {
                return null;
            }
        }

        private static bool ShouldSuppressCosmeticSounds(Item item)
        {
            string text = NormalizedItemText(item);
            return IsSealedSuitText(text) ||
                   text.Contains("autoinjectorheadset") ||
                   text.Contains("injectorheadset") ||
                   text.Contains("autoinjector");
        }

        private static bool ShouldPreserveSealedSuitMasks(Item item)
        {
            return IsSealedSuit(item);
        }

        private static bool IsSealedSuit(Item item)
        {
            return IsSealedSuitText(NormalizedItemText(item));
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
            string text = NormalizedItemText(item);
            if (IsSealedSuitText(text)) { return "sealed-suit"; }
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
            char[] buffer = value
                .ToLowerInvariant()
                .Where(char.IsLetterOrDigit)
                .ToArray();
            return new string(buffer);
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
                    priority + 10000.0f,
                    expectedSpeciesProperty.GetValue(animationInfo)
                });
            }
            catch (Exception ex)
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] Failed to boost filtered fashion animation priority: " + ex.GetType().Name + ": " + ex.Message);
                return animationInfo;
            }
        }

        private static bool ShouldFilterFashionAnimation(bool isSealedSuit, object animationInfo)
        {
            return isSealedSuit
                ? IsMovementAnimation(animationInfo)
                : IsLargeEquipmentMovementAnimation(animationInfo);
        }

        private static bool IsMovementAnimation(object animationInfo)
        {
            if (animationInfo == null) { return false; }
            Type animationInfoType = animationInfo.GetType();
            try
            {
                string animationType = animationInfoType.GetProperty("Type")?.GetValue(animationInfo)?.ToString();
                return string.Equals(animationType, "Walk", StringComparison.OrdinalIgnoreCase) ||
                       string.Equals(animationType, "Run", StringComparison.OrdinalIgnoreCase);
            }
            catch (Exception ex)
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] Failed to inspect functional fashion animation type: " + ex.GetType().Name + ": " + ex.Message);
                return false;
            }
        }

        private static bool IsLargeEquipmentMovementAnimation(object animationInfo)
        {
            if (!IsMovementAnimation(animationInfo)) { return false; }
            Type animationInfoType = animationInfo.GetType();
            try
            {
                string file = animationInfoType.GetProperty("File")?.GetValue(animationInfo)?.ToString() ?? string.Empty;
                return file.IndexOf("Exosuit", StringComparison.OrdinalIgnoreCase) >= 0 ||
                       file.IndexOf("DivingSuit", StringComparison.OrdinalIgnoreCase) >= 0;
            }
            catch (Exception ex)
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] Failed to inspect functional fashion animation: " + ex.GetType().Name + ": " + ex.Message);
                return false;
            }
        }

        private sealed class FunctionalFilterDiagnostics
        {
            private readonly HashSet<string> policies = new HashSet<string>();

            public int FilteredMovementAnimations { get; set; }
            public int SuppressedStatusSounds { get; set; }
            public int SuppressedItemSounds { get; set; }
            public int PreservedSealedMaskSprites { get; set; }

            public void RememberPolicy(string policy)
            {
                if (!string.IsNullOrWhiteSpace(policy))
                {
                    policies.Add(policy);
                }
            }

            public string Describe()
            {
                List<string> parts = new List<string>();
                if (FilteredMovementAnimations > 0) { parts.Add("filteredMovementAnimations=" + FilteredMovementAnimations); }
                if (SuppressedStatusSounds > 0) { parts.Add("suppressedStatusSounds=" + SuppressedStatusSounds); }
                if (SuppressedItemSounds > 0) { parts.Add("suppressedItemSounds=" + SuppressedItemSounds); }
                if (PreservedSealedMaskSprites > 0) { parts.Add("preservedSealedMaskSprites=" + PreservedSealedMaskSprites); }
                if (policies.Count > 0) { parts.Add("policies=" + string.Join("/", policies.OrderBy(policy => policy))); }
                return string.Join(";", parts);
            }
        }
    }

    internal static class CaptureFashionAnimationsPatch
    {
        private static bool Prefix(object[] __args, ref int __result)
        {
            if (FunctionalFashionFilters.TryCaptureFilteredFashionAnimations(__args, out int result))
            {
                __result = result;
                return false;
            }
            return true;
        }
    }

    internal static class CaptureFashionSoundsPatch
    {
        private static bool Prefix(object[] __args, ref int __result)
        {
            if (FunctionalFashionFilters.ShouldSkipFashionStatusSounds(__args, out int result))
            {
                __result = result;
                return false;
            }
            return true;
        }
    }

    internal static class CaptureFashionComponentSoundsPatch
    {
        private static bool Prefix(object[] __args, ref int __result)
        {
            if (FunctionalFashionFilters.ShouldSkipFashionComponentSounds(__args, out int result))
            {
                __result = result;
                return false;
            }
            return true;
        }
    }

    internal static class CreateFashionSpriteClonePatch
    {
        private static bool Prefix(object[] __args, ref WearableSprite __result)
        {
            if (FunctionalFashionFilters.TryCreateSealedSuitSpriteClone(__args, out WearableSprite result))
            {
                __result = result;
                return false;
            }
            return true;
        }
    }

    internal static class GetCharacterDebugStatusPatch
    {
        private static void Postfix(object[] __args, ref string __result)
        {
            FunctionalFashionFilters.AppendDebugStatus(__args, ref __result);
        }
    }

    internal static class ClearCharacterPatch
    {
        private static void Postfix(object[] __args)
        {
            FunctionalFashionFilters.ClearCharacterDiagnostics(__args);
        }
    }

    internal static class ClearAllPatch
    {
        private static void Postfix()
        {
            FunctionalFashionFilters.Clear();
        }
    }
}
