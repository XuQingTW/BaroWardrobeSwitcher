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
    internal static class WardrobeEntityRemoveAllPatch
    {
        public static void Prefix()
        {
            VisualOverride.ClearAll();
        }
    }

    internal static class LimbDrawWearablePatch
    {
        private static bool Prefix(Limb __instance, ref WearableSprite wearable)
        {
            if (!VisualOverride.TryOverrideDrawWearable(__instance, wearable, out WearableSprite replacement, out bool skipOriginal))
            {
                return true;
            }
            if (skipOriginal)
            {
                return false;
            }
            wearable = replacement;
            return true;
        }

    }

    // Prefix 暫時換入外觀，Postfix 補畫缺少的圖像，Finalizer 負責還原。
    // 還原必須涵蓋例外路徑，且不能吞掉遊戲或其他模組拋出的原始例外。
    internal static class LimbDrawPatch
    {
        internal struct State
        {
            public VisualOverride.LimbRenderTransaction FashionTransaction;
            public WearableSprite HuskSprite;
        }

        private static bool Prefix(Limb __instance, out State __state)
        {
            __state = default;
            if (VisualOverride.ShouldSuppressAfflictionAppendage(__instance) ||
                VisualOverride.ShouldSuppressEquipmentAppendage(__instance))
            {
                return false;
            }
            __state.HuskSprite = VisualOverride.BeginHuskSpriteSuppression(__instance);
            __state.FashionTransaction = VisualOverride.BeginLimbDraw(__instance);
            return true;
        }

        private static void Postfix(
            Limb __instance,
            SpriteBatch spriteBatch,
            Camera cam,
            Color? overrideColor,
            bool disableDeformations,
            State __state)
        {
            VisualOverride.DrawMissingFashionSprites(
                __instance,
                __state.FashionTransaction,
                spriteBatch,
                overrideColor);
        }

        private static Exception Finalizer(
            Limb __instance,
            Exception __exception,
            State __state)
        {
            Exception exception = VisualOverride.EndLimbDraw(
                __instance,
                __state.FashionTransaction,
                __exception);
            return VisualOverride.EndHuskSpriteSuppression(
                __instance,
                __state.HuskSprite,
                exception);
        }
    }

    internal static class AfflictionBodyTintPatch
    {
        private static void Postfix(Affliction __instance, ref Color __result)
        {
            VisualOverride.SuppressHuskTint(__instance, ref __result);
        }
    }

    internal static class AfflictionFaceTintPatch
    {
        private static void Postfix(Affliction __instance, ref Color __result)
        {
            VisualOverride.SuppressHuskTint(__instance, ref __result);
        }
    }

    internal static class AnimControllerUpdateAnimationsPatch
    {
        private static void Postfix(AnimController __instance)
        {
            VisualOverride.KeepFashionEffectsAlive(__instance);
        }
    }

    internal static class AnimControllerTryLoadTemporaryAnimationPatch
    {
        private static bool Prefix(AnimController __instance, object __0, ref bool __result)
        {
            if (VisualOverride.ShouldLoadTemporaryAnimation(__instance, __0)) { return true; }
            // StatusEffect blacklists (character, animation) after a false result.
            // A cosmetic suppression must count as success so equipment can resume.
            __result = true;
            return false;
        }
    }

    internal static class AnimControllerGetSpeedPatch
    {
        private static void Postfix(AnimController __instance, AnimationType __0, ref float __result)
        {
            VisualOverride.PreserveEquipmentMovementSpeed(__instance, __0, ref __result);
        }
    }

    internal static class StatusEffectPlaySoundPatch
    {
        private static bool Prefix(StatusEffect __instance, Entity entity, Hull hull, Vector2 worldPosition)
        {
            return VisualOverride.ShouldPlayOriginalStatusEffectSound(__instance, entity, hull, worldPosition);
        }
    }

    internal static class ItemComponentPlaySoundPatch
    {
        private static bool Prefix(ItemComponent __instance, ActionType type, Character user)
        {
            return VisualOverride.ShouldPlayOriginalItemComponentSound(__instance, type, user);
        }
    }

    internal static class RagdollPlayImpactSoundPatch
    {
        private static void Prefix(Limb __0, out VisualOverride.FootstepSoundTransaction __state)
        {
            __state = VisualOverride.BeginFootstepSound(__0);
        }

        private static Exception Finalizer(
            Exception __exception,
            VisualOverride.FootstepSoundTransaction __state)
        {
            return VisualOverride.EndFootstepSound(__state, __exception);
        }
    }
}
