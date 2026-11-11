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

        public const string Version = "0.5.10";
        // 設定缺失時使用此鍵；Lua currentPanelKey 與 Config 的預設值也要一起檢查。
        private const string DefaultPanelKeyName = "F8";
        private static ISettingBase<string> panelKeySetting;
        private static ISettingBase<bool> hideHuskVisualsSetting;
        private static ISettingBase<bool> unequipOnSaveSetting;
        private static ISettingBase<bool> hideEmptySlotEquipmentSetting;
        private static ISettingBase<bool> overrideGeneSplicerAppearanceSetting;
        private static IConfigService configService;
        private static bool hideHuskVisualsFallback;
        private static bool unequipOnSaveFallback = true;
        private static bool hideEmptySlotEquipmentFallback = true;
        private static bool overrideGeneSplicerAppearanceFallback;

        public static string GetVersion()
        {
            return Version;
        }

        // A character is the lifetime boundary for every captured sprite, mask and
        // effect. Keeping one aggregate avoids partial cleanup across side tables.
        private static readonly Dictionary<Character, RenderSession> RenderSessions =
            new Dictionary<Character, RenderSession>();
        private static readonly Dictionary<string, PatchState> PatchStates =
            new Dictionary<string, PatchState>();
        [ThreadStatic]
        private static Stack<LimbRenderTransaction> limbRenderTransactionPool;
        private const int LimbRenderTransactionPoolLimit = 64;
        [ThreadStatic]
        private static Stack<FootstepSoundTransaction> footstepSoundTransactionPool;
        private const int FootstepSoundTransactionPoolLimit = 32;
        private static readonly MethodInfo OnWearablesChangedMethod = AccessTools.Method(typeof(Character), "OnWearablesChanged");
        private static readonly MethodInfo LimbDrawMethod = AccessTools.Method(
            typeof(Limb),
            "Draw",
            new[] { typeof(SpriteBatch), typeof(Camera), typeof(Color?), typeof(bool) });
        private static readonly MethodInfo DrawWearableMethod = AccessTools.Method(
            typeof(Limb),
            "DrawWearable",
            new[] { typeof(WearableSprite), typeof(float), typeof(SpriteBatch), typeof(Color), typeof(float), typeof(SpriteEffects) });
        private static readonly MethodInfo UpdateAnimationsMethod =
            AccessTools.Method(typeof(AnimController), "UpdateAnimations", new[] { typeof(float) });
        private static readonly MethodInfo GetSpeedMethod =
            AccessTools.Method(typeof(AnimController), "GetSpeed", new[] { typeof(AnimationType) });
        private static readonly Type AnimLoadInfoType =
            typeof(StatusEffect).GetNestedType("AnimLoadInfo", BindingFlags.Public | BindingFlags.NonPublic);
        private static readonly MethodInfo TryLoadTemporaryAnimationMethod = AnimLoadInfoType == null
            ? null
            : AccessTools.Method(typeof(AnimController), "TryLoadTemporaryAnimation", new[] { AnimLoadInfoType, typeof(bool) });
        private static readonly MethodInfo PlaySoundMethod = AccessTools.Method(
            typeof(StatusEffect),
            "PlaySound",
            new[] { typeof(Entity), typeof(Hull), typeof(Vector2) });
        private static readonly MethodInfo ItemComponentPlaySoundMethod =
            AccessTools.Method(typeof(ItemComponent), "PlaySound", new[] { typeof(ActionType), typeof(Character) });
        private static readonly MethodInfo PlayImpactSoundMethod =
            AccessTools.Method(typeof(Ragdoll), "PlayImpactSound", new[] { typeof(Limb) });
        private static readonly MethodInfo GetBodyTintMethod =
            AccessTools.Method(typeof(Affliction), "GetBodyTint", Type.EmptyTypes);
        private static readonly MethodInfo GetFaceTintMethod =
            AccessTools.Method(typeof(Affliction), "GetFaceTint", Type.EmptyTypes);
        private static readonly FieldInfo AnimationsToTriggerField =
            AccessTools.Field(typeof(StatusEffect), "animationsToTrigger");
        private static readonly FieldInfo SoundsField =
            AccessTools.Field(typeof(StatusEffect), "sounds");
        private static readonly FieldInfo ComponentSoundsField =
            AccessTools.Field(typeof(ItemComponent), "sounds");
        private static readonly FieldInfo ForcePlaySoundsField =
            AccessTools.Field(typeof(StatusEffect), "forcePlaySounds");
        private static readonly FieldInfo LoopSoundField =
            AccessTools.Field(typeof(StatusEffect), "loopSound");
        private static readonly FieldInfo ItemSoundLoopField =
            AccessTools.Field("Barotrauma.Items.Components.ItemSound:Loop");
        private static readonly FieldInfo HuskAppendageField =
            AccessTools.Field(typeof(AfflictionHusk), "huskAppendage");
        private static readonly FieldInfo HuskSpriteField =
            AccessTools.Field(typeof(Limb), "<HuskSprite>k__BackingField");
        private static readonly PropertyInfo CharacterRemovedProperty = AccessTools.Property(typeof(Character), "Removed");
        private const float DrawDepthStep = 0.000001f;
        private const int DefaultFallbackDepthPadding = 8;
        private const int RecessedFallbackDepthStart = -32;
        private const float FashionAnimationPriorityBoost = 10000.0f;
        private const string Xds01EngineIdentifier = "Wf_New_XDS01_Engine";
        private const string Xds01EngineAfflictionIdentifier = "XDS01engine";
        private const string Xds01AppendageTexture = "Wf_New_XDS01_Engine_limb.png";
        private const int Xds01ExpectedAppendageLimbCount = 6;
        private static readonly HashSet<Identifier> HuskAppearanceAfflictionIdentifiers = new HashSet<Identifier>
        {
            new Identifier("huskinfection"),
            new Identifier("husksymbiosis")
        };
        private static readonly HashSet<Identifier> TouhouWingAfflictionIdentifiers = new HashSet<Identifier>
        {
            new Identifier("Piece_Wings_Spawn"),
            new Identifier("Cirno_Wings_Spawn"),
            new Identifier("Sunny_Wings_Spawn"),
            new Identifier("Luna_Wings_Spawn"),
            new Identifier("Star_Wings_Spawn"),
            new Identifier("Flandre_Wings_Spawn"),
            new Identifier("Remilia_Wings_Spawn"),
            new Identifier("Lilywhite_Wings_Spawn"),
            new Identifier("Lilywhite_Black_Wings_Spawn"),
            new Identifier("Touhou_Dichromatic_Lotus_Butterfly_Wings_Spawn"),
            new Identifier("Ema_Wings_Spawn"),
            new Identifier("Normal_Yousei_Wings_Spawn"),
            new Identifier("Normal_Yokai_Wings_Spawn"),
            new Identifier("Shinki_Wings_Spawn"),
            new Identifier("Koakuma_Wings_Spawn"),
            new Identifier("Nue_Eclipse_Wings_Spawn")
        };
        private static readonly WearableType[] FashionHideableAttachmentTypes =
        {
            WearableType.Hair,
            WearableType.Beard,
            WearableType.Moustache,
            WearableType.FaceAttachment
        };
        private const int AttachmentHairBit = 0x01;
        private const int AttachmentBeardBit = 0x02;
        private const int AttachmentMoustacheBit = 0x04;
        private const int AttachmentFaceBit = 0x08;
        private const int AttachmentVisibilityMask = 0x0F;
        private static readonly Dictionary<WearableType, int> AttachmentBits =
            new Dictionary<WearableType, int>
        {
            [WearableType.Hair] = AttachmentHairBit,
            [WearableType.Beard] = AttachmentBeardBit,
            [WearableType.Moustache] = AttachmentMoustacheBit,
            [WearableType.FaceAttachment] = AttachmentFaceBit
        };
        private static int virtualDrawErrorLogCount;
        private static int animationOverrideErrorLogCount;
        private static int soundOverrideErrorLogCount;
        private static int lastInjectedSpriteCount;
        private static int drawOverrideHitCount;
        private static int drawOverrideMissCount;
        private static int drawOverrideHiddenAfterDrawCount;
        private static int drawOverrideHiddenEmptySlotCount;
        private static int drawOverrideHiddenSavedSlotCount;
        private static int drawOverrideHiddenAttachmentCount;
        private static int fallbackDrawnFashionSpriteCount;

        public static void ResetPatchStatus()
        {
            PatchStates.Clear();
            PatchStates["Limb.DrawWearable"] = new PatchState(required: true);
            PatchStates["Limb.Draw"] = new PatchState(required: true);
            PatchStates["AnimController.UpdateAnimations"] = new PatchState(required: false);
            PatchStates["AnimController.GetSpeed"] = new PatchState(required: false);
            PatchStates["AnimController.TryLoadTemporaryAnimation"] = new PatchState(required: false);
            PatchStates["StatusEffect.PlaySound"] = new PatchState(required: false);
            PatchStates["ItemComponent.PlaySound"] = new PatchState(required: false);
            PatchStates["Ragdoll.PlayImpactSound"] = new PatchState(required: false);
            PatchStates["Affliction.GetBodyTint"] = new PatchState(required: false);
            PatchStates["Affliction.GetFaceTint"] = new PatchState(required: false);
        }

        // 遊戲更新後若 hook 失效，先核對實際方法簽章與相容性探針，再調整註冊。
        public static void InstallPatches(Harmony harmony)
        {
            ResetPatchStatus();
            if (harmony == null)
            {
                foreach (PatchState state in PatchStates.Values)
                {
                    state.Fail("Harmony instance missing");
                }
                return;
            }

            harmony.Patch(
                AccessTools.Method(typeof(Entity), nameof(Entity.RemoveAll), Type.EmptyTypes),
                prefix: new HarmonyMethod(
                    typeof(WardrobeEntityRemoveAllPatch),
                    nameof(WardrobeEntityRemoveAllPatch.Prefix)));

            PatchTarget(
                harmony,
                "Limb.DrawWearable",
                DrawWearableMethod,
                prefix: AccessTools.Method(typeof(LimbDrawWearablePatch), "Prefix"));
            PatchTarget(
                harmony,
                "Limb.Draw",
                LimbDrawMethod,
                prefix: AccessTools.Method(typeof(LimbDrawPatch), "Prefix"),
                postfix: AccessTools.Method(typeof(LimbDrawPatch), "Postfix"),
                finalizer: AccessTools.Method(typeof(LimbDrawPatch), "Finalizer"));
            PatchTarget(
                harmony,
                "AnimController.UpdateAnimations",
                UpdateAnimationsMethod,
                postfix: AccessTools.Method(typeof(AnimControllerUpdateAnimationsPatch), "Postfix"),
                required: false);
            PatchTarget(
                harmony,
                "AnimController.GetSpeed",
                GetSpeedMethod,
                postfix: AccessTools.Method(typeof(AnimControllerGetSpeedPatch), "Postfix"),
                required: false);
            PatchTarget(
                harmony,
                "AnimController.TryLoadTemporaryAnimation",
                TryLoadTemporaryAnimationMethod,
                prefix: AccessTools.Method(typeof(AnimControllerTryLoadTemporaryAnimationPatch), "Prefix"),
                required: false);
            PatchTarget(
                harmony,
                "StatusEffect.PlaySound",
                PlaySoundMethod,
                prefix: AccessTools.Method(typeof(StatusEffectPlaySoundPatch), "Prefix"),
                required: false);
            PatchTarget(
                harmony,
                "ItemComponent.PlaySound",
                ItemComponentPlaySoundMethod,
                prefix: AccessTools.Method(typeof(ItemComponentPlaySoundPatch), "Prefix"),
                required: false);
            PatchTarget(
                harmony,
                "Ragdoll.PlayImpactSound",
                PlayImpactSoundMethod,
                prefix: AccessTools.Method(typeof(RagdollPlayImpactSoundPatch), "Prefix"),
                finalizer: AccessTools.Method(typeof(RagdollPlayImpactSoundPatch), "Finalizer"),
                required: false);
            PatchTarget(
                harmony,
                "Affliction.GetBodyTint",
                GetBodyTintMethod,
                postfix: AccessTools.Method(typeof(AfflictionBodyTintPatch), "Postfix"),
                required: false);
            PatchTarget(
                harmony,
                "Affliction.GetFaceTint",
                GetFaceTintMethod,
                postfix: AccessTools.Method(typeof(AfflictionFaceTintPatch), "Postfix"),
                required: false);
        }

        public static bool IsReady()
        {
            if (PatchStates.Count == 0) { ResetPatchStatus(); }
            return PatchStates.Values.Where(state => state.Required).All(state => state.Applied);
        }

        public static bool HasCapability(string name)
        {
            if (PatchStates.Count == 0) { ResetPatchStatus(); }
            switch ((name ?? string.Empty).Trim().ToLowerInvariant())
            {
                case "renderer":
                    return PatchApplied("Limb.Draw") &&
                           PatchApplied("Limb.DrawWearable") &&
                           LimbDrawMethod != null &&
                           DrawWearableMethod != null;
                case "animation":
                    return PatchApplied("AnimController.UpdateAnimations") &&
                           PatchApplied("AnimController.GetSpeed") &&
                           PatchApplied("AnimController.TryLoadTemporaryAnimation") &&
                           UpdateAnimationsMethod != null &&
                           TryLoadTemporaryAnimationMethod != null &&
                           AnimationsToTriggerField != null;
                case "statussound":
                case "status-sound":
                    return PatchApplied("StatusEffect.PlaySound") &&
                           PlaySoundMethod != null &&
                           SoundsField != null;
                case "itemsound":
                case "item-sound":
                    return PatchApplied("ItemComponent.PlaySound") &&
                           ItemComponentPlaySoundMethod != null &&
                           ComponentSoundsField != null;
                case "footstepsound":
                case "footstep-sound":
                    return PatchApplied("Ragdoll.PlayImpactSound") &&
                           PlayImpactSoundMethod != null;
                case "huskvisual":
                case "husk-visual":
                    return PatchApplied("Limb.Draw") &&
                           PatchApplied("Affliction.GetBodyTint") &&
                           PatchApplied("Affliction.GetFaceTint") &&
                           HuskAppendageField != null &&
                           HuskSpriteField != null;
                default:
                    return false;
            }
        }

        public static string GetReadinessStatus()
        {
            if (PatchStates.Count == 0) { ResetPatchStatus(); }
            List<string> missingRequired = PatchStates
                .Where(pair => pair.Value.Required && !pair.Value.Applied)
                .Select(pair => pair.Key + " (" + pair.Value.Error + ")")
                .ToList();
            List<string> missingOptional = PatchStates
                .Where(pair => !pair.Value.Required && !pair.Value.Applied)
                .Select(pair => pair.Key + " (" + pair.Value.Error + ")")
                .ToList();

            string capabilities = "capabilities(renderer=" + HasCapability("renderer") +
                                  ",animation=" + HasCapability("animation") +
                                  ",statusSound=" + HasCapability("statusSound") +
                                  ",itemSound=" + HasCapability("itemSound") +
                                  ",footstepSound=" + HasCapability("footstepSound") +
                                  ",huskVisual=" + HasCapability("huskVisual") + ")";

            if (missingRequired.Count == 0)
            {
                return missingOptional.Count == 0
                    ? "ready; " + capabilities
                    : "ready; " + capabilities + "; optional hook unavailable: " + string.Join(", ", missingOptional);
            }

            bool hasAnyRequired = PatchStates.Values.Any(state => state.Required && state.Applied);
            return (hasAnyRequired ? "degraded; missing " : "missing required hooks: ") +
                   string.Join(", ", missingRequired) + "; " + capabilities;
        }

        private static bool PatchApplied(string name)
        {
            return PatchStates.TryGetValue(name, out PatchState state) && state.Applied;
        }

        private static void PatchTarget(
            Harmony harmony,
            string name,
            MethodBase target,
            MethodInfo prefix = null,
            MethodInfo postfix = null,
            MethodInfo finalizer = null,
            bool required = true)
        {
            if (!PatchStates.TryGetValue(name, out PatchState state))
            {
                state = new PatchState(required);
                PatchStates[name] = state;
            }

            if (target == null)
            {
                state.Fail("target missing");
                return;
            }

            if (prefix == null && postfix == null && finalizer == null)
            {
                state.Fail("patch method missing");
                return;
            }

            try
            {
                PatchProcessor processor = harmony.CreateProcessor(target);
                if (prefix != null)
                {
                    processor.AddPrefix(new HarmonyMethod(prefix));
                }
                if (postfix != null)
                {
                    processor.AddPostfix(new HarmonyMethod(postfix));
                }
                if (finalizer != null)
                {
                    processor.AddFinalizer(new HarmonyMethod(finalizer));
                }
                processor.Patch();
                state.Applied = true;
                state.Error = null;
            }
            catch (Exception ex)
            {
                state.Fail(ex.GetType().Name + ": " + ex.Message);
                LuaCsLogger.Log($"[Baro Wardrobe Switcher] Failed to patch {name}: {ex.GetType().Name}: {ex.Message}");
            }
        }

        public static string GetCharacterDebugStatus(Character character)
        {
            if (character == null) { return "character=nil"; }
            RenderSessions.TryGetValue(character, out RenderSession session);
            int spriteCount = session?.SpriteCount ?? 0;
            int animationCount = session?.FashionAnimations.Count ?? 0;
            int soundCount = session?.FashionSounds.Count ?? 0;
            int componentSoundCount = session?.FashionComponentSounds.Count ?? 0;
            int suppressedSoundCount = session?.SuppressedEquipmentSounds.Count ?? 0;
            int suppressedComponentSoundCount = session?.SuppressedEquipmentComponentSounds.Count ?? 0;
            string status = "active=" + (session?.IsActive ?? false) +
                   ", valid=" + (session?.IsValid ?? false) +
                   ", committed=" + (session?.IsCommitted ?? false) +
                   ", pending=" + (session?.HasPendingCapture ?? false) +
                   ", sessionError=" + (session?.Error ?? "none") +
                   ", empty=" + (session?.EmptyLook ?? false) +
                   ", forceHideAttachments=0x" + (session?.ForceHideAttachmentMask ?? 0).ToString("X2") +
                   ", forceShowAttachments=0x" + (session?.ForceShowAttachmentMask ?? 0).ToString("X2") +
                   ", hideHuskVisuals=" + GetHideHuskVisuals() +
                   ", hideEmptySlotEquipment=" + GetHideEmptySlotEquipment() +
                   ", sprites=" + spriteCount +
                   ", animations=" + animationCount +
                   ", fashionFootsteps=" + (session?.UseFashionFootstepSounds ?? false) +
                   ", footstepCalls=" + (session?.FootstepSoundCalls ?? 0) +
                   ", fashionFootstepCalls=" + (session?.FashionFootstepSoundCalls ?? 0) +
                   ", fashionFootstepTags=" + DescribeFashionFootstepSounds(session) +
                   ", sounds=" + soundCount +
                   ", itemSounds=" + componentSoundCount +
                   ", suppressedSounds=" + suppressedSoundCount +
                   ", suppressedItemSounds=" + suppressedComponentSoundCount +
                   ", drawPatchTarget=" + (LimbDrawMethod != null) +
                   ", drawPatchTargets=" + (LimbDrawMethod == null ? 0 : 1) +
                   ", drawWearableTarget=" + (DrawWearableMethod != null) +
                   ", lastInjected=" + lastInjectedSpriteCount +
                   ", drawHits=" + drawOverrideHitCount +
                   ", drawMisses=" + drawOverrideMissCount +
                   ", hiddenAfterDraw=" + drawOverrideHiddenAfterDrawCount +
                   ", hiddenEmptySlots=" + drawOverrideHiddenEmptySlotCount +
                   ", hiddenSavedSlots=" + drawOverrideHiddenSavedSlotCount +
                   ", hiddenAttachments=" + drawOverrideHiddenAttachmentCount +
                   ", hiddenAttachmentTypes=" + DescribeFashionHiddenTypes(character) +
                   ", fallbackDrawn=" + fallbackDrawnFashionSpriteCount +
                   ", savedSlots=" + DescribeSavedSlots(character) +
                   ", emptySlots=" + DescribeEmptySlots(character) +
                   ", spriteSlots=" + DescribeFashionSprites(character) +
                   ", spriteLayers=" + DescribeFashionSpriteLayers(character) +
                   ", spriteSources=" + DescribeFashionSpriteSources(character);
            return status;
        }

        public static void ClearAll()
        {
            foreach (RenderSession session in RenderSessions.Values.ToList())
            {
                session.Dispose();
            }
            RenderSessions.Clear();
        }

        public static void RestoreItemVisuals()
        {
            foreach (RenderSession session in RenderSessions.Values)
            {
                session.SuppressedEquipmentAnimations.Clear();
                session.EquipmentMovementAnimations.Clear();
                session.IsActive = false;
                session.RemoveOwnedAppendages();
                session.ForceHideAttachmentMask = 0;
                session.ForceShowAttachmentMask = 0;
                session.EmptySlots.Clear();
                session.SavedSlots.Clear();
            }
        }

        public static void RestoreCharacterItemVisuals(Character character)
        {
            if (character == null) { return; }
            if (RenderSessions.TryGetValue(character, out RenderSession session))
            {
                session.SuppressedEquipmentAnimations.Clear();
                session.EquipmentMovementAnimations.Clear();
                session.SuppressedEquipmentSounds.Clear();
                session.SuppressedEquipmentComponentSounds.Clear();
                session.IsActive = false;
                session.RemoveOwnedAppendages();
                session.ForceHideAttachmentMask = 0;
                session.ForceShowAttachmentMask = 0;
                session.EmptySlots.Clear();
                session.SavedSlots.Clear();
            }
            fallbackDrawnFashionSpriteCount = 0;
            RefreshWearables(character);
        }

        internal static void SetPanelKeySetting(ISettingBase<string> setting)
        {
            panelKeySetting = setting;
        }

        internal static void SetHideHuskVisualsSetting(
            ISettingBase<bool> setting,
            IConfigService service)
        {
            if (hideHuskVisualsSetting != null)
            {
                hideHuskVisualsSetting.OnValueChanged -= OnHideHuskVisualsChanged;
            }
            hideHuskVisualsSetting = setting;
            configService = service;
            hideHuskVisualsFallback = setting?.Value ?? false;
            if (hideHuskVisualsSetting != null)
            {
                hideHuskVisualsSetting.OnValueChanged += OnHideHuskVisualsChanged;
            }
            ForceUpdateCharacterVisuals();
        }

        public static string GetPanelKeyName()
        {
            string value = panelKeySetting?.Value;
            return string.IsNullOrWhiteSpace(value) ? DefaultPanelKeyName : value.Trim();
        }

        public static bool GetHideHuskVisuals()
        {
            return hideHuskVisualsSetting?.Value ?? hideHuskVisualsFallback;
        }

        public static bool SetHideHuskVisuals(bool enabled)
        {
            if (enabled && !HasCapability("huskVisual")) { return false; }
            if (hideHuskVisualsSetting != null)
            {
                bool previous = hideHuskVisualsSetting.Value;
                if (!hideHuskVisualsSetting.TrySetValue(enabled)) { return false; }
                if (!SaveBooleanSetting(hideHuskVisualsSetting))
                {
                    hideHuskVisualsSetting.TrySetValue(previous);
                    LuaCsLogger.Log("[Baro Wardrobe Switcher] Failed to persist HideHuskVisuals.");
                    return false;
                }
            }
            hideHuskVisualsFallback = enabled;
            ForceUpdateCharacterVisuals();
            return true;
        }

        internal static void SetUnequipOnSaveSetting(
            ISettingBase<bool> setting,
            IConfigService service)
        {
            unequipOnSaveSetting = setting;
            configService = service;
            unequipOnSaveFallback = setting?.Value ?? true;
        }

        public static bool GetUnequipOnSave()
        {
            return unequipOnSaveSetting?.Value ?? unequipOnSaveFallback;
        }

        public static bool SetUnequipOnSave(bool enabled)
        {
            if (unequipOnSaveSetting != null)
            {
                bool previous = unequipOnSaveSetting.Value;
                if (!unequipOnSaveSetting.TrySetValue(enabled)) { return false; }
                if (!SaveBooleanSetting(unequipOnSaveSetting))
                {
                    unequipOnSaveSetting.TrySetValue(previous);
                    LuaCsLogger.Log("[Baro Wardrobe Switcher] Failed to persist UnequipOnSave.");
                    return false;
                }
            }
            unequipOnSaveFallback = enabled;
            return true;
        }

        internal static void SetHideEmptySlotEquipmentSetting(
            ISettingBase<bool> setting,
            IConfigService service)
        {
            hideEmptySlotEquipmentSetting = setting;
            configService = service;
            hideEmptySlotEquipmentFallback = setting?.Value ?? true;
        }

        public static bool GetHideEmptySlotEquipment()
        {
            return hideEmptySlotEquipmentSetting?.Value ?? hideEmptySlotEquipmentFallback;
        }

        public static bool SetHideEmptySlotEquipment(bool enabled)
        {
            if (hideEmptySlotEquipmentSetting != null)
            {
                bool previous = hideEmptySlotEquipmentSetting.Value;
                if (!hideEmptySlotEquipmentSetting.TrySetValue(enabled)) { return false; }
                if (!SaveBooleanSetting(hideEmptySlotEquipmentSetting))
                {
                    hideEmptySlotEquipmentSetting.TrySetValue(previous);
                    LuaCsLogger.Log("[Baro Wardrobe Switcher] Failed to persist HideEmptySlotEquipment.");
                    return false;
                }
            }
            hideEmptySlotEquipmentFallback = enabled;
            return true;
        }

        internal static void SetOverrideGeneSplicerAppearanceSetting(
            ISettingBase<bool> setting,
            IConfigService service)
        {
            overrideGeneSplicerAppearanceSetting = setting;
            configService = service;
            overrideGeneSplicerAppearanceFallback = setting?.Value ?? false;
        }

        public static bool GetOverrideGeneSplicerAppearance()
        {
            return overrideGeneSplicerAppearanceSetting?.Value ?? overrideGeneSplicerAppearanceFallback;
        }

        public static bool SetOverrideGeneSplicerAppearance(bool enabled)
        {
            if (overrideGeneSplicerAppearanceSetting != null)
            {
                bool previous = overrideGeneSplicerAppearanceSetting.Value;
                if (!overrideGeneSplicerAppearanceSetting.TrySetValue(enabled)) { return false; }
                if (!SaveBooleanSetting(overrideGeneSplicerAppearanceSetting))
                {
                    overrideGeneSplicerAppearanceSetting.TrySetValue(previous);
                    LuaCsLogger.Log("[Baro Wardrobe Switcher] Failed to persist OverrideGeneSplicerAppearance.");
                    return false;
                }
            }
            overrideGeneSplicerAppearanceFallback = enabled;
            return true;
        }

        private static bool SaveBooleanSetting(ISettingBase<bool> setting)
        {
            if (configService == null || setting == null) { return true; }
            try
            {
                return configService.SaveConfigValue(setting).IsSuccess;
            }
            catch
            {
                return false;
            }
        }

        private static void OnHideHuskVisualsChanged(ISettingBase setting)
        {
            hideHuskVisualsFallback = hideHuskVisualsSetting?.Value ?? false;
            ForceUpdateCharacterVisuals();
        }

        private static void ForceUpdateCharacterVisuals()
        {
            foreach (Character character in Character.CharacterList)
            {
                try { character?.CharacterHealth?.ForceUpdateVisuals(); } catch { }
            }
        }

    }

}
