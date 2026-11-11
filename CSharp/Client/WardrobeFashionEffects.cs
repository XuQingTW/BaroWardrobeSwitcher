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

        internal static void KeepFashionEffectsAlive(AnimController animController)
        {
            if (animController?.Character != null &&
                RenderSessions.TryGetValue(animController.Character, out RenderSession session))
            {
                session.MovementAnimationFrame++;
            }
            KeepFashionAnimationsAlive(animController);
            KeepFashionSoundsAlive(animController);
        }

        internal static bool ShouldLoadTemporaryAnimation(AnimController animController, object animationInfo)
        {
            Character character = animController?.Character;
            if (character == null ||
                !RenderSessions.TryGetValue(character, out RenderSession session) ||
                !session.IsActive ||
                !session.IsValid ||
                !HasCapability("animation"))
            {
                return true;
            }
            if (!session.UseFashionMovementAnimations) { return true; }
            bool suppress = session.SuppressedEquipmentAnimations.Contains(animationInfo) ||
                (session.FashionAnimations.Count == 0 &&
                 FashionEffectPolicy.IsLargeEquipmentMovementAnimation(animationInfo));
            if (!suppress) { return true; }

            // Suppress the pose only. Diving suits encode their ground speed in
            // these animation files, not in Character.SpeedMultiplier.
            if (!(animController is HumanoidAnimController) ||
                !(animationInfo is StatusEffect.AnimLoadInfo info)) { return true; }
            try
            {
                if (!session.EquipmentMovementAnimations.TryGetValue(animationInfo, out var movement))
                {
                    GroundedMovementParams parameters = info.Type == AnimationType.Walk
                        ? HumanWalkParams.GetAnimParams(character, info.File, false)
                        : info.Type == AnimationType.Run
                            ? HumanRunParams.GetAnimParams(character, info.File, false)
                            : null;
                    if (parameters == null) { return true; }
                    movement = (parameters, info.Priority, session.MovementAnimationFrame);
                }
                movement.LastRefresh = session.MovementAnimationFrame;
                session.EquipmentMovementAnimations[animationInfo] = movement;
                return false;
            }
            catch (Exception ex)
            {
                LogAnimationError($"Failed to preserve equipment movement speed: {ex.Message}");
                return true;
            }
        }

        internal static void PreserveEquipmentMovementSpeed(
            AnimController animController, AnimationType type, ref float speed)
        {
            if ((type != AnimationType.Walk && type != AnimationType.Run) ||
                animController?.Character == null ||
                !RenderSessions.TryGetValue(animController.Character, out RenderSession session) ||
                !session.IsActive || !session.IsValid || !HasCapability("animation")) { return; }
            speed = session.LimitEquipmentMovementSpeed(type, animController.IsMovingBackwards, speed);
        }

        private static void KeepFashionAnimationsAlive(AnimController animController)
        {
            Character character = animController?.Character;
            if (character == null ||
                !RenderSessions.TryGetValue(character, out RenderSession session) ||
                !session.IsActive ||
                !session.IsValid ||
                !HasCapability("animation") ||
                session.FashionAnimations.Count == 0)
            {
                return;
            }
            if (TryLoadTemporaryAnimationMethod == null)
            {
                LogAnimationError("AnimController.TryLoadTemporaryAnimation method was not found.");
                return;
            }

            object[] invokeArguments = session.FashionAnimationInvokeArguments;
            foreach (object animationInfo in session.FashionAnimations)
            {
                if (!session.UseFashionMovementAnimations &&
                    session.FashionMovementAnimations.Contains(animationInfo))
                {
                    continue;
                }
                try
                {
                    invokeArguments[0] = animationInfo;
                    TryLoadTemporaryAnimationMethod.Invoke(animController, invokeArguments);
                }
                catch (Exception ex)
                {
                    LogAnimationError($"Failed to refresh fashion animation: {ex.GetType().Name}: {ex.Message}");
                }
            }
        }

        private static void KeepFashionSoundsAlive(AnimController animController)
        {
            Character character = animController?.Character;
            if (character == null ||
                !RenderSessions.TryGetValue(character, out RenderSession session) ||
                !session.IsActive ||
                !session.IsValid)
            {
                return;
            }

            foreach (StatusEffect fashionSound in session.LoopingFashionSounds)
            {
                if (fashionSound == null) { continue; }
                TryPlaySpecificFashionSound(
                    session,
                    fashionSound,
                    character,
                    character.CurrentHull,
                    character.WorldPosition);
            }

            foreach ((ItemComponent Component, ActionType ActionType) fashionSound in session.LoopingFashionComponentSounds)
            {
                if (fashionSound.Component == null) { continue; }
                TryPlaySpecificFashionComponentSound(character, fashionSound.Component, fashionSound.ActionType, character);
            }
        }

        private static bool HasFashionPayload(Character character)
        {
            return character != null &&
                   RenderSessions.TryGetValue(character, out RenderSession session) &&
                   HasFashionPayload(session);
        }

        private static bool HasFashionPayload(RenderSession session)
        {
            return session != null &&
                   (session.EmptyLook ||
                    session.SpriteCount > 0 ||
                    session.FashionAnimations.Count > 0 ||
                    session.FashionSounds.Count > 0 ||
                    session.FashionComponentSounds.Count > 0);
        }

        private static int CaptureFashionAnimations(RenderSession session, Item item)
        {
            if (session == null || item?.Components == null) { return 0; }
            if (!HasCapability("animation") || AnimationsToTriggerField == null) { return 0; }
            List<object> animationInfos = session.FashionAnimations;

            int count = 0;
            foreach (ItemComponent component in item.Components)
            {
                if (component?.statusEffectLists == null) { continue; }
                if (!component.statusEffectLists.TryGetValue(ActionType.OnWearing, out List<StatusEffect> statusEffects)) { continue; }
                foreach (StatusEffect statusEffect in statusEffects)
                {
                    if (FashionEffectPolicy.IsStateDependentStatusEffect(statusEffect)) { continue; }
                    IEnumerable animations = AnimationsToTriggerField.GetValue(statusEffect) as IEnumerable;
                    if (animations == null) { continue; }
                    foreach (object animationInfo in animations)
                    {
                        if (!FashionEffectPolicy.ShouldCaptureAnimation(item, animationInfo)) { continue; }
                        object boostedAnimationInfo = BoostFashionAnimationPriority(animationInfo);
                        if (boostedAnimationInfo == null || animationInfos.Contains(boostedAnimationInfo)) { continue; }
                        animationInfos.Add(boostedAnimationInfo);
                        if (FashionEffectPolicy.IsMovementAnimation(boostedAnimationInfo))
                        {
                            session.FashionMovementAnimations.Add(boostedAnimationInfo);
                        }
                        count++;
                    }
                }
            }

            return count;
        }

        private static int CaptureFashionSounds(RenderSession session, Item item)
        {
            if (session == null || item?.Components == null) { return 0; }
            if (!HasCapability("statusSound") ||
                SoundsField == null ||
                !FashionEffectPolicy.ShouldCaptureItemSounds(item))
            {
                return 0;
            }
            List<StatusEffect> soundEffects = session.FashionSounds;

            int count = 0;
            foreach (ItemComponent component in item.Components)
            {
                if (component?.statusEffectLists == null) { continue; }
                if (!component.statusEffectLists.TryGetValue(ActionType.OnWearing, out List<StatusEffect> statusEffects)) { continue; }
                foreach (StatusEffect statusEffect in statusEffects)
                {
                    if (!HasSounds(statusEffect)) { continue; }
                    if (FashionEffectPolicy.IsStateDependentStatusEffect(statusEffect)) { continue; }
                    if (soundEffects.Any(soundEffect => ReferenceEquals(soundEffect, statusEffect))) { continue; }

                    soundEffects.Add(statusEffect);
                    if (HasLoopingSound(statusEffect))
                    {
                        session.LoopingFashionSounds.Add(statusEffect);
                    }
                    count++;
                }
            }

            return count;
        }

        private static int CaptureFashionComponentSounds(RenderSession session, Item item)
        {
            if (session == null ||
                item?.Components == null ||
                !HasCapability("itemSound") ||
                ComponentSoundsField == null ||
                !FashionEffectPolicy.ShouldCaptureItemSounds(item))
            {
                return 0;
            }
            List<(ItemComponent Component, ActionType ActionType)> componentSounds = session.FashionComponentSounds;

            int count = 0;
            foreach (ItemComponent component in item.Components)
            {
                if (component == null || !HasComponentSounds(component)) { continue; }
                foreach (ActionType actionType in GetComponentSoundTypes(component))
                {
                    if (componentSounds.Any(sound => ReferenceEquals(sound.Component, component) && sound.ActionType == actionType)) { continue; }
                    componentSounds.Add((component, actionType));
                    if (FashionEffectPolicy.ShouldKeepComponentLoopAlive(actionType) &&
                        HasLoopingComponentSound(component, actionType))
                    {
                        session.LoopingFashionComponentSounds.Add((component, actionType));
                    }
                    count++;
                }
            }

            return count;
        }

        private static void RegisterSuppressedEquipmentAnimations(Character character, Item item)
        {
            if (character == null || item?.Components == null || AnimationsToTriggerField == null) { return; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session)) { return; }

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
                        if (FashionEffectPolicy.ShouldSuppressEquipmentAnimation(item, animationInfo))
                        {
                            session.SuppressedEquipmentAnimations.Add(animationInfo);
                        }
                    }
                }
            }
        }

        private static void RegisterSuppressedEquipmentSounds(Character character, Item item)
        {
            if (character == null || item?.Components == null || SoundsField == null) { return; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session)) { return; }
            // When the saved look carries its own sounds we suppress every matching real
            // equipment sound and replace it. When the look is silent we still have to
            // silence looping real-equipment sounds (diving suits, exosuits, beeping
            // headsets); otherwise they keep beeping while the look hides the gear, which
            // mirrors how ShouldLoadTemporaryAnimation suppresses their movement animation.
            bool hasFashionSound = HasAnyFashionSound(character);

            foreach (ItemComponent component in item.Components)
            {
                if (component?.statusEffectLists == null) { continue; }
                if (!component.statusEffectLists.TryGetValue(ActionType.OnWearing, out List<StatusEffect> statusEffects)) { continue; }
                foreach (StatusEffect statusEffect in statusEffects)
                {
                    if (!HasSounds(statusEffect)) { continue; }
                    if (IsFashionStatusSound(character, statusEffect)) { continue; }
                    // Conditional/required-item sounds are gameplay feedback, not
                    // ambience. Keep them on the real item so Barotrauma starts and
                    // stops oxygen alarms with the actual suit/tank lifecycle.
                    if (FashionEffectPolicy.IsStateDependentStatusEffect(statusEffect))
                    {
                        session.SuppressedEquipmentSounds.Remove(statusEffect);
                        session.LoopingEquipmentSounds.Remove(statusEffect);
                        continue;
                    }
                    bool isLooping = HasLoopingSound(statusEffect);
                    if (!hasFashionSound && !isLooping) { continue; }
                    session.SuppressedEquipmentSounds.Add(statusEffect);
                    if (isLooping) { session.LoopingEquipmentSounds.Add(statusEffect); }
                }
            }
        }

        private static void RegisterSuppressedEquipmentComponentSounds(Character character, Item item)
        {
            if (character == null || item?.Components == null || ComponentSoundsField == null) { return; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session)) { return; }
            // Same rule as the status-effect sounds above: a silent saved look still has to
            // silence looping real-equipment item sounds so cosmetic gear stops beeping.
            bool hasFashionSound = HasAnyFashionSound(character);

            foreach (ItemComponent component in item.Components)
            {
                if (component == null || !HasComponentSounds(component)) { continue; }
                if (IsFashionComponentSound(character, component)) { continue; }
                bool hasLoopingSound = false;
                foreach (ActionType actionType in GetComponentSoundTypes(component))
                {
                    if (!HasLoopingComponentSound(component, actionType)) { continue; }
                    hasLoopingSound = true;
                    session.LoopingEquipmentComponentSounds.Add((component, actionType));
                }
                if (!hasFashionSound && !hasLoopingSound) { continue; }
                session.SuppressedEquipmentComponentSounds.Add(component);
            }
        }

        internal static bool ShouldPlayOriginalStatusEffectSound(StatusEffect statusEffect, Entity entity, Hull hull, Vector2 worldPosition)
        {
            if (statusEffect == null) { return true; }
            RenderSession session = null;
            foreach (RenderSession candidate in RenderSessions.Values)
            {
                if (!candidate.SuppressedEquipmentSounds.Contains(statusEffect)) { continue; }
                session = candidate;
                break;
            }
            Character character = session?.Character;
            if (character == null) { return true; }
            if (!session.IsActive || !session.IsValid || !HasCapability("statusSound")) { return true; }
            if (FashionEffectPolicy.IsStateDependentStatusEffect(statusEffect))
            {
                session.SuppressedEquipmentSounds.Remove(statusEffect);
                session.LoopingEquipmentSounds.Remove(statusEffect);
                return true;
            }
            if (!HasAnyFashionSound(character))
            {
                return false;
            }
            if (session.LoopingEquipmentSounds.Contains(statusEffect))
            {
                // Looping equipment sounds retrigger every update; force-restarting a
                // one-shot fashion sound for each retrigger produces continuous beeping.
                // Looping fashion sounds are kept alive separately by KeepFashionSoundsAlive.
                return false;
            }

            bool played = TryPlayReplacementFashionSound(session, session.FashionSounds, entity, hull, worldPosition);
            if (!played)
            {
                played = TryPlayReplacementFashionComponentSound(
                    session,
                    session.FashionComponentSounds,
                    ActionType.OnWearing,
                    character);
            }
            if (!played)
            {
                LogSoundError("Skipped real equipment sound but could not play a saved appearance sound.");
            }
            return false;
        }

        internal static bool ShouldPlayOriginalItemComponentSound(ItemComponent component, ActionType actionType, Character user)
        {
            if (component == null) { return true; }
            RenderSession session = null;
            foreach (RenderSession candidate in RenderSessions.Values)
            {
                if (!candidate.SuppressedEquipmentComponentSounds.Contains(component)) { continue; }
                session = candidate;
                break;
            }
            Character character = session?.Character;
            if (character == null) { return true; }
            if (!session.IsActive || !session.IsValid || !HasCapability("itemSound")) { return true; }
            if (user != null && character != user) { return true; }
            if (!HasAnyFashionSound(character))
            {
                return false;
            }
            if (session.LoopingEquipmentComponentSounds.Contains((component, actionType)))
            {
                // Same as looping status-effect sounds: never replay one-shot fashion
                // sounds for every retrigger of a looping equipment sound.
                return false;
            }

            bool played = TryPlayReplacementFashionComponentSound(
                session,
                session.FashionComponentSounds,
                actionType,
                user ?? character);
            if (!played)
            {
                played = TryPlayReplacementFashionSound(
                    session,
                    session.FashionSounds,
                    user ?? character,
                    character.CurrentHull,
                    character.WorldPosition);
            }
            if (!played)
            {
                LogSoundError("Skipped real equipment item sound but could not play a saved appearance item sound.");
            }
            return false;
        }

        private static bool HasAnyFashionSound(Character character)
        {
            return character != null &&
                   RenderSessions.TryGetValue(character, out RenderSession session) &&
                   (session.FashionSounds.Count > 0 || session.FashionComponentSounds.Count > 0);
        }

        private static bool IsFashionStatusSound(Character character, StatusEffect statusEffect)
        {
            return character != null &&
                   statusEffect != null &&
                   RenderSessions.TryGetValue(character, out RenderSession session) &&
                   session.FashionSounds.Any(sound => ReferenceEquals(sound, statusEffect));
        }

        private static bool IsFashionComponentSound(Character character, ItemComponent component)
        {
            return character != null &&
                   component != null &&
                   RenderSessions.TryGetValue(character, out RenderSession session) &&
                   session.FashionComponentSounds.Any(sound => ReferenceEquals(sound.Component, component));
        }

        private static bool TryPlayReplacementFashionSound(
            RenderSession session,
            List<StatusEffect> fashionSounds,
            Entity entity,
            Hull hull,
            Vector2 worldPosition)
        {
            Character character = session?.Character;
            if (character == null || fashionSounds == null || fashionSounds.Count == 0 || PlaySoundMethod == null)
            {
                return false;
            }

            int cursor = session.FashionSoundCursor;
            for (int offset = 0; offset < fashionSounds.Count; offset++)
            {
                int index = (cursor + offset) % fashionSounds.Count;
                StatusEffect fashionSound = fashionSounds[index];
                if (fashionSound == null) { continue; }

                session.FashionSoundCursor = (index + 1) % fashionSounds.Count;
                return TryPlaySpecificFashionSound(
                    session,
                    fashionSound,
                    entity,
                    hull,
                    worldPosition,
                    forceRestart: true);
            }

            return false;
        }

        private static bool TryPlaySpecificFashionSound(
            RenderSession session,
            StatusEffect statusEffect,
            Entity entity,
            Hull hull,
            Vector2 worldPosition,
            bool forceRestart = false)
        {
            Character character = session?.Character;
            if (character == null || statusEffect == null || PlaySoundMethod == null) { return false; }

            bool originalForcePlay = false;
            bool forcePlayChanged = false;
            try
            {
                if (forceRestart && ForcePlaySoundsField != null)
                {
                    object originalValue = ForcePlaySoundsField.GetValue(statusEffect);
                    originalForcePlay = originalValue is bool boolValue && boolValue;
                    ForcePlaySoundsField.SetValue(statusEffect, true);
                    forcePlayChanged = true;
                }

                object[] arguments = session.FashionSoundInvokeArguments;
                arguments[0] = entity ?? character;
                arguments[1] = hull ?? character.CurrentHull;
                arguments[2] = worldPosition;
                PlaySoundMethod.Invoke(statusEffect, arguments);
                return true;
            }
            catch (Exception ex)
            {
                LogSoundError($"Failed to play saved appearance sound: {ex.GetType().Name}: {ex.Message}");
                return false;
            }
            finally
            {
                if (forcePlayChanged)
                {
                    try
                    {
                        ForcePlaySoundsField.SetValue(statusEffect, originalForcePlay);
                    }
                    catch (Exception ex)
                    {
                        LogSoundError($"Failed to restore sound force flag: {ex.GetType().Name}: {ex.Message}");
                    }
                }
            }
        }

        private static bool TryPlayReplacementFashionComponentSound(
            RenderSession session,
            List<(ItemComponent Component, ActionType ActionType)> fashionSounds,
            ActionType actionType,
            Character user)
        {
            Character character = session?.Character;
            if (character == null || fashionSounds == null || fashionSounds.Count == 0) { return false; }

            int cursor = session.FashionComponentSoundCursor;
            for (int offset = 0; offset < fashionSounds.Count; offset++)
            {
                int index = (cursor + offset) % fashionSounds.Count;
                (ItemComponent Component, ActionType ActionType) fashionSound = fashionSounds[index];
                if (fashionSound.Component == null || fashionSound.ActionType != actionType) { continue; }

                session.FashionComponentSoundCursor = (index + 1) % fashionSounds.Count;
                return TryPlaySpecificFashionComponentSound(
                    character,
                    fashionSound.Component,
                    fashionSound.ActionType,
                    user ?? character);
            }

            return false;
        }

        private static bool TryPlaySpecificFashionComponentSound(
            Character character,
            ItemComponent component,
            ActionType actionType,
            Character user)
        {
            if (character == null || component == null) { return false; }
            try
            {
                component.PlaySound(actionType, user ?? character);
                return true;
            }
            catch (Exception ex)
            {
                LogSoundError($"Failed to play saved appearance item sound: {ex.GetType().Name}: {ex.Message}");
                return false;
            }
        }

        private static bool HasSounds(StatusEffect statusEffect)
        {
            if (statusEffect == null || SoundsField == null) { return false; }
            try
            {
                IEnumerable sounds = SoundsField.GetValue(statusEffect) as IEnumerable;
                if (sounds == null) { return false; }
                foreach (object sound in sounds)
                {
                    if (sound != null) { return true; }
                }
            }
            catch (Exception ex)
            {
                LogSoundError($"Failed to inspect fashion sounds: {ex.GetType().Name}: {ex.Message}");
            }
            return false;
        }

        private static bool HasComponentSounds(ItemComponent component)
        {
            if (component == null || ComponentSoundsField == null) { return false; }
            try
            {
                object sounds = ComponentSoundsField.GetValue(component);
                return sounds is System.Collections.IDictionary dictionary && dictionary.Count > 0;
            }
            catch (Exception ex)
            {
                LogSoundError($"Failed to inspect item component sounds: {ex.GetType().Name}: {ex.Message}");
                return false;
            }
        }

        private static bool HasLoopingSound(StatusEffect statusEffect)
        {
            if (statusEffect == null || LoopSoundField == null) { return false; }
            try
            {
                object loop = LoopSoundField.GetValue(statusEffect);
                return loop is bool loopValue && loopValue;
            }
            catch (Exception ex)
            {
                LogSoundError($"Failed to inspect fashion loop sound: {ex.GetType().Name}: {ex.Message}");
                return false;
            }
        }

        private static bool HasLoopingComponentSound(ItemComponent component, ActionType actionType)
        {
            if (component == null || ComponentSoundsField == null || ItemSoundLoopField == null) { return false; }
            try
            {
                if (!(ComponentSoundsField.GetValue(component) is System.Collections.IDictionary dictionary)) { return false; }
                if (!dictionary.Contains(actionType)) { return false; }
                if (!(dictionary[actionType] is IEnumerable sounds)) { return false; }
                foreach (object sound in sounds)
                {
                    object loop = ItemSoundLoopField.GetValue(sound);
                    if (loop is bool loopValue && loopValue) { return true; }
                }
            }
            catch (Exception ex)
            {
                LogSoundError($"Failed to inspect looping item component sounds: {ex.GetType().Name}: {ex.Message}");
            }
            return false;
        }

        private static IEnumerable<ActionType> GetComponentSoundTypes(ItemComponent component)
        {
            if (component == null || ComponentSoundsField == null) { yield break; }
            System.Collections.IDictionary dictionary = null;
            try
            {
                dictionary = ComponentSoundsField.GetValue(component) as System.Collections.IDictionary;
            }
            catch (Exception ex)
            {
                LogSoundError($"Failed to enumerate item component sounds: {ex.GetType().Name}: {ex.Message}");
            }

            if (dictionary == null) { yield break; }
            foreach (object key in dictionary.Keys)
            {
                if (key is ActionType actionType)
                {
                    yield return actionType;
                }
            }
        }

    }

}
