using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Text.Json;
using Barotrauma;
using Barotrauma.Items.Components;
using Barotrauma.LuaCs;
using HarmonyLib;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace BaroWardrobeSwitcher
{
    public sealed class WardrobeVisualOverridePlugin : IAssemblyPlugin
    {
        private Harmony harmonyInstance;

        public void Initialize()
        {
            LuaCsLogger.Log($"[Baro Wardrobe Switcher] C# visual override v{VisualOverride.Version} initializing.");
            harmonyInstance = new Harmony("BaroWardrobeSwitcher.VisualOverride");
            VisualOverride.ResetPatchStatus();
        }

        public void OnLoadCompleted()
        {
            VisualOverride.InstallPatches(harmonyInstance);
            LuaCsLogger.Log($"[Baro Wardrobe Switcher] C# visual override loaded: {VisualOverride.GetReadinessStatus()}.");
        }

        public void PreInitPatching() { }

        public void Dispose()
        {
            VisualOverride.ClearAll();
            harmonyInstance?.UnpatchSelf();
            LuaCsLogger.Log("[Baro Wardrobe Switcher] C# visual override disposed.");
        }
    }

    public static class WardrobePersistence
    {
        private const int PersistenceVersion = 1;
        private const string ModFolderName = "BaroWardrobeSwitcher";
        private const string ClientLookFileName = "ClientLook.json";
        private const string ServerLooksFileName = "ServerLooks.json";
        private static readonly string[] SlotKeys =
        {
            "Head",
            "Headset",
            "InnerClothes",
            "OuterClothes",
            "Bag",
            "HealthInterface"
        };
        private static readonly JsonSerializerOptions JsonOptions = new JsonSerializerOptions
        {
            WriteIndented = true
        };

        public static string GetStorageDirectory()
        {
            try
            {
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                if (string.IsNullOrWhiteSpace(localAppData))
                {
                    localAppData = AppContext.BaseDirectory;
                }
                return Path.Combine(
                    localAppData,
                    "Daedalic Entertainment GmbH",
                    "Barotrauma",
                    "ModData",
                    ModFolderName);
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to resolve storage directory", ex);
                return Path.Combine(AppContext.BaseDirectory, "ModData", ModFolderName);
            }
        }

        public static string GetClientLookPath()
        {
            return Path.Combine(GetStorageDirectory(), ClientLookFileName);
        }

        public static string GetServerLooksPath()
        {
            return Path.Combine(GetStorageDirectory(), ServerLooksFileName);
        }

        public static string LoadClientLook()
        {
            try
            {
                string path = GetClientLookPath();
                if (!File.Exists(path)) { return string.Empty; }
                ClientLookDocument document = ReadJson<ClientLookDocument>(path);
                if (document == null || !HasAnySlot(document.Slots) && !document.Captured)
                {
                    return string.Empty;
                }
                return EncodeClientLook(document);
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to load client look", ex);
                return string.Empty;
            }
        }

        public static bool ClientLookFileExists()
        {
            try
            {
                return File.Exists(GetClientLookPath());
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to inspect client look file", ex);
                return false;
            }
        }

        public static bool SaveClientLook(string encodedLook)
        {
            try
            {
                ClientLookDocument document = ParseClientLook(encodedLook);
                if (document == null || !HasAnySlot(document.Slots) && !document.Captured)
                {
                    return ClearClientLook();
                }
                WriteJson(GetClientLookPath(), document);
                return true;
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to save client look", ex);
                return false;
            }
        }

        public static bool ClearClientLook()
        {
            try
            {
                WriteJson(
                    GetClientLookPath(),
                    new ClientLookDocument
                    {
                        Version = PersistenceVersion,
                        Captured = false,
                        Active = false,
                        AutoApply = false,
                        HideHair = false,
                        SessionKey = null,
                        Slots = new Dictionary<string, WardrobeSlotDocument>()
                    });
                return true;
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to clear client look", ex);
                return false;
            }
        }

        public static string LoadServerLooks()
        {
            try
            {
                string path = GetServerLooksPath();
                if (!File.Exists(path)) { return string.Empty; }
                ServerLooksDocument document = ReadJson<ServerLooksDocument>(path);
                if (document?.Looks == null || document.Looks.Count == 0)
                {
                    return string.Empty;
                }

                List<string> lines = new List<string>();
                foreach (KeyValuePair<string, ServerLookDocument> pair in document.Looks)
                {
                    if (string.IsNullOrWhiteSpace(pair.Key) || pair.Value == null) { continue; }
                    lines.Add(EncodeServerLook(pair.Key, pair.Value));
                }
                return string.Join("\n", lines);
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to load server looks", ex);
                return string.Empty;
            }
        }

        public static bool SaveServerLooks(string encodedLooks)
        {
            try
            {
                ServerLooksDocument document = ParseServerLooks(encodedLooks);
                WriteJson(GetServerLooksPath(), document);
                return true;
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to save server looks", ex);
                return false;
            }
        }

        private static T ReadJson<T>(string path)
        {
            string json = File.ReadAllText(path, Encoding.UTF8);
            return JsonSerializer.Deserialize<T>(json, JsonOptions);
        }

        private static void WriteJson<T>(string path, T value)
        {
            string directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            string tempPath = path + ".tmp";
            string json = JsonSerializer.Serialize(value, JsonOptions);
            File.WriteAllText(tempPath, json, Encoding.UTF8);
            if (File.Exists(path))
            {
                File.Replace(tempPath, path, null);
            }
            else
            {
                File.Move(tempPath, path);
            }
        }

        private static ClientLookDocument ParseClientLook(string encodedLook)
        {
            Dictionary<string, string> parts = ParseParts(encodedLook);
            ClientLookDocument document = new ClientLookDocument
            {
                Version = PersistenceVersion,
                Captured = GetBoolean(parts, "captured"),
                Active = GetBoolean(parts, "active"),
                AutoApply = GetBoolean(parts, "auto"),
                HideHair = GetBoolean(parts, "hidehair"),
                SessionKey = parts.TryGetValue("session", out string encodedSessionKey) ? Unescape(encodedSessionKey) : null,
                Slots = ParseSlots(parts)
            };
            return document;
        }

        private static ServerLooksDocument ParseServerLooks(string encodedLooks)
        {
            ServerLooksDocument document = new ServerLooksDocument
            {
                Version = PersistenceVersion,
                Looks = new Dictionary<string, ServerLookDocument>()
            };

            foreach (string rawLine in SplitLines(encodedLooks))
            {
                Dictionary<string, string> parts = ParseParts(rawLine);
                if (!parts.TryGetValue("key", out string encodedKey)) { continue; }
                string key = Unescape(encodedKey);
                if (string.IsNullOrWhiteSpace(key)) { continue; }
                document.Looks[key] = new ServerLookDocument
                {
                    Active = GetBoolean(parts, "active"),
                    Slots = ParseSlots(parts)
                };
            }

            return document;
        }

        private static string EncodeClientLook(ClientLookDocument document)
        {
            List<string> parts = new List<string>
            {
                "captured=" + document.Captured.ToString().ToLowerInvariant(),
                "active=" + document.Active.ToString().ToLowerInvariant(),
                "auto=" + document.AutoApply.ToString().ToLowerInvariant(),
                "hidehair=" + document.HideHair.ToString().ToLowerInvariant()
            };
            if (!string.IsNullOrWhiteSpace(document.SessionKey))
            {
                parts.Add("session=" + Escape(document.SessionKey));
            }
            AppendEncodedSlots(parts, document.Slots);
            return string.Join("|", parts);
        }

        private static string EncodeServerLook(string key, ServerLookDocument document)
        {
            List<string> parts = new List<string>
            {
                "key=" + Escape(key),
                "active=" + document.Active.ToString().ToLowerInvariant()
            };
            AppendEncodedSlots(parts, document.Slots);
            return string.Join("|", parts);
        }

        private static void AppendEncodedSlots(List<string> parts, Dictionary<string, WardrobeSlotDocument> slots)
        {
            if (parts == null || slots == null) { return; }
            foreach (string slotKey in SlotKeys)
            {
                if (!slots.TryGetValue(slotKey, out WardrobeSlotDocument slot) || slot == null) { continue; }
                if (string.IsNullOrWhiteSpace(slot.Identifier)) { continue; }
                parts.Add(slotKey + "=" + Escape(slot.Identifier) + "," + Escape(slot.Name));
            }
        }

        private static Dictionary<string, WardrobeSlotDocument> ParseSlots(Dictionary<string, string> parts)
        {
            Dictionary<string, WardrobeSlotDocument> slots = new Dictionary<string, WardrobeSlotDocument>();
            foreach (string slotKey in SlotKeys)
            {
                if (!parts.TryGetValue(slotKey, out string encodedValue)) { continue; }
                int commaIndex = encodedValue.IndexOf(',');
                if (commaIndex < 0) { continue; }
                string identifier = Unescape(encodedValue.Substring(0, commaIndex));
                if (string.IsNullOrWhiteSpace(identifier)) { continue; }
                string name = Unescape(encodedValue.Substring(commaIndex + 1));
                slots[slotKey] = new WardrobeSlotDocument
                {
                    Identifier = identifier,
                    Name = name ?? string.Empty
                };
            }
            return slots;
        }

        private static Dictionary<string, string> ParseParts(string line)
        {
            Dictionary<string, string> parts = new Dictionary<string, string>();
            if (string.IsNullOrWhiteSpace(line)) { return parts; }
            foreach (string part in line.Split('|'))
            {
                int equalsIndex = part.IndexOf('=');
                if (equalsIndex <= 0) { continue; }
                string name = part.Substring(0, equalsIndex);
                string value = part.Substring(equalsIndex + 1);
                parts[name] = value;
            }
            return parts;
        }

        private static IEnumerable<string> SplitLines(string text)
        {
            if (string.IsNullOrWhiteSpace(text)) { yield break; }
            string normalized = text.Replace("\r\n", "\n").Replace('\r', '\n');
            foreach (string line in normalized.Split('\n'))
            {
                if (!string.IsNullOrWhiteSpace(line))
                {
                    yield return line;
                }
            }
        }

        private static bool GetBoolean(Dictionary<string, string> parts, string key)
        {
            return parts != null &&
                   parts.TryGetValue(key, out string value) &&
                   string.Equals(value, "true", StringComparison.OrdinalIgnoreCase);
        }

        private static bool HasAnySlot(Dictionary<string, WardrobeSlotDocument> slots)
        {
            return slots != null &&
                   slots.Values.Any(slot => slot != null && !string.IsNullOrWhiteSpace(slot.Identifier));
        }

        private static string Escape(string value)
        {
            return (value ?? string.Empty)
                .Replace("%", "%25")
                .Replace("|", "%7C")
                .Replace(",", "%2C")
                .Replace("=", "%3D")
                .Replace("\r", "%0D")
                .Replace("\n", "%0A");
        }

        private static string Unescape(string value)
        {
            return (value ?? string.Empty)
                .Replace("%0A", "\n")
                .Replace("%0D", "\r")
                .Replace("%3D", "=")
                .Replace("%2C", ",")
                .Replace("%7C", "|")
                .Replace("%25", "%");
        }

        private static void LogPersistenceError(string message, Exception ex)
        {
            LuaCsLogger.Log("[Baro Wardrobe Switcher] " + message + ": " + ex.GetType().Name + ": " + ex.Message);
        }

        private sealed class WardrobeSlotDocument
        {
            public string Identifier { get; set; }
            public string Name { get; set; }
        }

        private sealed class ClientLookDocument
        {
            public int Version { get; set; }
            public bool Captured { get; set; }
            public bool Active { get; set; }
            public bool AutoApply { get; set; }
            public bool HideHair { get; set; }
            public string SessionKey { get; set; }
            public Dictionary<string, WardrobeSlotDocument> Slots { get; set; }
        }

        private sealed class ServerLookDocument
        {
            public bool Active { get; set; }
            public Dictionary<string, WardrobeSlotDocument> Slots { get; set; }
        }

        private sealed class ServerLooksDocument
        {
            public int Version { get; set; }
            public Dictionary<string, ServerLookDocument> Looks { get; set; }
        }
    }

    public static class VisualOverride
    {

        public const string Version = "0.3.22";

        private static readonly Dictionary<Character, Dictionary<Tuple<WearableType, LimbType>, List<WearableSprite>>> FashionSpritesByCharacter =
            new Dictionary<Character, Dictionary<Tuple<WearableType, LimbType>, List<WearableSprite>>>();
        private static readonly Dictionary<Character, List<object>> FashionAnimationsByCharacter =
            new Dictionary<Character, List<object>>();
        private static readonly Dictionary<Character, List<FashionSoundEffect>> FashionSoundsByCharacter =
            new Dictionary<Character, List<FashionSoundEffect>>();
        private static readonly Dictionary<Character, List<FashionComponentSound>> FashionComponentSoundsByCharacter =
            new Dictionary<Character, List<FashionComponentSound>>();
        private static readonly Dictionary<Character, HashSet<StatusEffect>> SuppressedEquipmentSoundsByCharacter =
            new Dictionary<Character, HashSet<StatusEffect>>();
        private static readonly Dictionary<StatusEffect, Character> SuppressedEquipmentSoundOwners =
            new Dictionary<StatusEffect, Character>();
        private static readonly Dictionary<Character, HashSet<ItemComponent>> SuppressedEquipmentComponentSoundsByCharacter =
            new Dictionary<Character, HashSet<ItemComponent>>();
        private static readonly Dictionary<ItemComponent, Character> SuppressedEquipmentComponentSoundOwners =
            new Dictionary<ItemComponent, Character>();
        private static readonly Dictionary<Character, int> FashionSoundCursorByCharacter =
            new Dictionary<Character, int>();
        private static readonly Dictionary<Character, int> FashionComponentSoundCursorByCharacter =
            new Dictionary<Character, int>();
        private static readonly Dictionary<Character, HashSet<WearableType>> FashionHiddenWearableTypesByCharacter =
            new Dictionary<Character, HashSet<WearableType>>();
        private static readonly HashSet<Character> ForceHideHairCharacters = new HashSet<Character>();
        private static readonly HashSet<Character> EmptyFashionCharacters = new HashSet<Character>();
        private static readonly Dictionary<Character, HashSet<InvSlotType>> EmptyFashionSlotsByCharacter =
            new Dictionary<Character, HashSet<InvSlotType>>();
        private static readonly Dictionary<Character, HashSet<InvSlotType>> SavedFashionSlotsByCharacter =
            new Dictionary<Character, HashSet<InvSlotType>>();
        private static readonly HashSet<Character> ActiveCharacters = new HashSet<Character>();
        private static readonly Dictionary<Character, Dictionary<WearableSprite, SpriteMaskState>> OriginalSpriteMasksByCharacter =
            new Dictionary<Character, Dictionary<WearableSprite, SpriteMaskState>>();
        private static readonly Dictionary<Limb, HashSet<WearableSprite>> DrawnFashionSpritesByLimb =
            new Dictionary<Limb, HashSet<WearableSprite>>();
        private static readonly Dictionary<Limb, List<WearableSprite>> InjectedFashionSpritesByLimb =
            new Dictionary<Limb, List<WearableSprite>>();
        private static readonly Dictionary<Limb, List<WearableSprite>> OriginalWearableOrderByLimb =
            new Dictionary<Limb, List<WearableSprite>>();
        private static readonly Dictionary<string, PatchState> PatchStates =
            new Dictionary<string, PatchState>();
        private static readonly MethodInfo OnWearablesChangedMethod = AccessTools.Method(typeof(Character), "OnWearablesChanged");
        private static readonly MethodInfo DrawWearableMethod = AccessTools.Method(
            typeof(Limb),
            "DrawWearable",
            new[] { typeof(WearableSprite), typeof(float), typeof(SpriteBatch), typeof(Color), typeof(float), typeof(SpriteEffects) });
        private static readonly MethodInfo TryLoadTemporaryAnimationMethod =
            AccessTools.Method(typeof(AnimController), "TryLoadTemporaryAnimation");
        private static readonly MethodInfo PlaySoundMethod =
            AccessTools.Method(typeof(StatusEffect), "PlaySound");
        private static readonly MethodInfo ItemComponentPlaySoundMethod =
            AccessTools.Method(typeof(ItemComponent), "PlaySound", new[] { typeof(ActionType), typeof(Character) });
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
        private static readonly MethodInfo MemberwiseCloneMethod = AccessTools.Method(typeof(object), "MemberwiseClone");
        private static readonly PropertyInfo CharacterRemovedProperty = AccessTools.Property(typeof(Character), "Removed");
        private const float DrawDepthStep = 0.000001f;
        private const int DefaultFallbackDepthPadding = 8;
        private const int RecessedFallbackDepthStart = -32;
        private const float FashionAnimationPriorityBoost = 10000.0f;
        private static readonly WearableType[] FashionHideableAttachmentTypes =
        {
            WearableType.Hair,
            WearableType.Beard,
            WearableType.Moustache,
            WearableType.FaceAttachment
        };
        // Attachment types hidden when the player opts to hide hair while a look is active.
        private static readonly WearableType[] HairAttachmentTypes =
        {
            WearableType.Hair,
            WearableType.Beard,
            WearableType.Moustache
        };
        private static int drawOverrideLogCount;
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
        private static int storedFashionDrawDepth;

        public static void ResetPatchStatus()
        {
            PatchStates.Clear();
            PatchStates["Limb.DrawWearable"] = new PatchState(required: true);
            PatchStates["Limb.Draw"] = new PatchState(required: true);
            PatchStates["AnimController.UpdateAnimations"] = new PatchState(required: false);
            PatchStates["AnimController.TryLoadTemporaryAnimation"] = new PatchState(required: false);
            PatchStates["StatusEffect.PlaySound"] = new PatchState(required: false);
            PatchStates["ItemComponent.PlaySound"] = new PatchState(required: false);
        }

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

            PatchTarget(
                harmony,
                "Limb.DrawWearable",
                DrawWearableMethod,
                prefix: AccessTools.Method(typeof(LimbDrawWearablePatch), "Prefix"));
            PatchLimbDrawTargets(harmony);
            PatchTarget(
                harmony,
                "AnimController.UpdateAnimations",
                AccessTools.Method(typeof(AnimController), "UpdateAnimations"),
                postfix: AccessTools.Method(typeof(AnimControllerUpdateAnimationsPatch), "Postfix"),
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
        }

        public static bool IsReady()
        {
            if (PatchStates.Count == 0) { ResetPatchStatus(); }
            return PatchStates.Values.Where(state => state.Required).All(state => state.Applied);
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

            if (missingRequired.Count == 0)
            {
                return missingOptional.Count == 0
                    ? "ready"
                    : "ready; optional hook unavailable: " + string.Join(", ", missingOptional);
            }

            bool hasAnyRequired = PatchStates.Values.Any(state => state.Required && state.Applied);
            return (hasAnyRequired ? "degraded; missing " : "missing required hooks: ") +
                   string.Join(", ", missingRequired);
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

        private static void PatchLimbDrawTargets(Harmony harmony)
        {
            const string name = "Limb.Draw";
            if (!PatchStates.TryGetValue(name, out PatchState state))
            {
                state = new PatchState(required: true);
                PatchStates[name] = state;
            }

            List<MethodInfo> targets = FindLimbDrawMethods().ToList();
            if (targets.Count == 0)
            {
                state.Fail("target missing");
                return;
            }

            MethodInfo prefix = AccessTools.Method(typeof(LimbDrawPatch), "Prefix");
            MethodInfo postfix = AccessTools.Method(typeof(LimbDrawPatch), "Postfix");
            MethodInfo finalizer = AccessTools.Method(typeof(LimbDrawPatch), "Finalizer");
            List<string> errors = new List<string>();
            int patched = 0;

            foreach (MethodInfo target in targets)
            {
                try
                {
                    PatchProcessor processor = harmony.CreateProcessor(target);
                    processor.AddPrefix(new HarmonyMethod(prefix));
                    processor.AddPostfix(new HarmonyMethod(postfix));
                    processor.AddFinalizer(new HarmonyMethod(finalizer));
                    processor.Patch();
                    patched++;
                }
                catch (Exception ex)
                {
                    errors.Add(DescribeMethod(target) + ": " + ex.GetType().Name + ": " + ex.Message);
                    LuaCsLogger.Log($"[Baro Wardrobe Switcher] Failed to patch {name} overload {DescribeMethod(target)}: {ex.GetType().Name}: {ex.Message}");
                }
            }

            if (patched > 0)
            {
                state.Applied = true;
                state.Error = errors.Count == 0
                    ? "patched " + patched + " overload(s)"
                    : "patched " + patched + " overload(s); failed " + errors.Count + " overload(s)";
            }
            else
            {
                state.Fail(string.Join("; ", errors));
            }
        }

        public static string GetCharacterDebugStatus(Character character)
        {
            if (character == null) { return "character=nil"; }
            int spriteCount = FashionSpritesByCharacter.TryGetValue(character, out Dictionary<Tuple<WearableType, LimbType>, List<WearableSprite>> spritesBySlot)
                ? spritesBySlot.Values.Sum(spriteList => spriteList.Count)
                : 0;
            int animationCount = FashionAnimationsByCharacter.TryGetValue(character, out List<object> animationInfos)
                ? animationInfos.Count
                : 0;
            int soundCount = FashionSoundsByCharacter.TryGetValue(character, out List<FashionSoundEffect> soundEffects)
                ? soundEffects.Count
                : 0;
            int componentSoundCount = FashionComponentSoundsByCharacter.TryGetValue(character, out List<FashionComponentSound> componentSounds)
                ? componentSounds.Count
                : 0;
            int suppressedSoundCount = SuppressedEquipmentSoundsByCharacter.TryGetValue(character, out HashSet<StatusEffect> suppressedSounds)
                ? suppressedSounds.Count
                : 0;
            int suppressedComponentSoundCount = SuppressedEquipmentComponentSoundsByCharacter.TryGetValue(character, out HashSet<ItemComponent> suppressedComponentSounds)
                ? suppressedComponentSounds.Count
                : 0;
            return "active=" + ActiveCharacters.Contains(character) +
                   ", empty=" + EmptyFashionCharacters.Contains(character) +
                   ", hideHair=" + ForceHideHairCharacters.Contains(character) +
                   ", sprites=" + spriteCount +
                   ", animations=" + animationCount +
                   ", sounds=" + soundCount +
                   ", itemSounds=" + componentSoundCount +
                   ", suppressedSounds=" + suppressedSoundCount +
                   ", suppressedItemSounds=" + suppressedComponentSoundCount +
                   ", drawPatchTarget=" + (FindLimbDrawMethod() != null) +
                   ", drawPatchTargets=" + FindLimbDrawMethods().Count() +
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
                   ", spriteLayers=" + DescribeFashionSpriteLayers(character);
        }

        public static void ClearAll()
        {
            RestoreAllSpriteMasks();
            FashionSpritesByCharacter.Clear();
            FashionHiddenWearableTypesByCharacter.Clear();
            ForceHideHairCharacters.Clear();
            FashionAnimationsByCharacter.Clear();
            FashionSoundsByCharacter.Clear();
            FashionComponentSoundsByCharacter.Clear();
            SuppressedEquipmentSoundsByCharacter.Clear();
            SuppressedEquipmentSoundOwners.Clear();
            SuppressedEquipmentComponentSoundsByCharacter.Clear();
            SuppressedEquipmentComponentSoundOwners.Clear();
            FashionSoundCursorByCharacter.Clear();
            FashionComponentSoundCursorByCharacter.Clear();
            EmptyFashionCharacters.Clear();
            EmptyFashionSlotsByCharacter.Clear();
            SavedFashionSlotsByCharacter.Clear();
            ActiveCharacters.Clear();
            SuppressedEquipmentSoundsByCharacter.Clear();
            SuppressedEquipmentSoundOwners.Clear();
            SuppressedEquipmentComponentSoundsByCharacter.Clear();
            SuppressedEquipmentComponentSoundOwners.Clear();
            FashionSoundCursorByCharacter.Clear();
            FashionComponentSoundCursorByCharacter.Clear();
            DrawnFashionSpritesByLimb.Clear();
            InjectedFashionSpritesByLimb.Clear();
            OriginalWearableOrderByLimb.Clear();
            EmptyFashionSlotsByCharacter.Clear();
            SavedFashionSlotsByCharacter.Clear();
        }

        public static void RestoreItemVisuals()
        {
            RestoreAllSpriteMasks();
            ActiveCharacters.Clear();
            ForceHideHairCharacters.Clear();
            DrawnFashionSpritesByLimb.Clear();
            InjectedFashionSpritesByLimb.Clear();
            OriginalWearableOrderByLimb.Clear();
            EmptyFashionSlotsByCharacter.Clear();
            SavedFashionSlotsByCharacter.Clear();
        }

        public static void RestoreCharacterItemVisuals(Character character)
        {
            if (character == null) { return; }
            RestoreSpriteMasks(character);
            ClearSuppressedEquipmentSounds(character);
            ClearSuppressedEquipmentComponentSounds(character);
            ActiveCharacters.Remove(character);
            ForceHideHairCharacters.Remove(character);
            EmptyFashionSlotsByCharacter.Remove(character);
            SavedFashionSlotsByCharacter.Remove(character);
            DrawnFashionSpritesByLimb.Clear();
            InjectedFashionSpritesByLimb.Clear();
            OriginalWearableOrderByLimb.Clear();
            fallbackDrawnFashionSpriteCount = 0;
            RefreshWearables(character);
        }

        public static void ClearCharacter(Character character)
        {
            if (character == null) { return; }
            RestoreSpriteMasks(character);
            FashionSpritesByCharacter.Remove(character);
            FashionHiddenWearableTypesByCharacter.Remove(character);
            ForceHideHairCharacters.Remove(character);
            FashionAnimationsByCharacter.Remove(character);
            FashionSoundsByCharacter.Remove(character);
            FashionComponentSoundsByCharacter.Remove(character);
            ClearSuppressedEquipmentSounds(character);
            ClearSuppressedEquipmentComponentSounds(character);
            FashionSoundCursorByCharacter.Remove(character);
            FashionComponentSoundCursorByCharacter.Remove(character);
            EmptyFashionCharacters.Remove(character);
            EmptyFashionSlotsByCharacter.Remove(character);
            SavedFashionSlotsByCharacter.Remove(character);
            ActiveCharacters.Remove(character);
            DrawnFashionSpritesByLimb.Clear();
            InjectedFashionSpritesByLimb.Clear();
            OriginalWearableOrderByLimb.Clear();
            RefreshWearables(character);
        }

        public static void PruneStaleCharacters()
        {
            List<Character> characters = FashionSpritesByCharacter.Keys
                .Concat(FashionHiddenWearableTypesByCharacter.Keys)
                .Concat(ForceHideHairCharacters)
                .Concat(FashionAnimationsByCharacter.Keys)
                .Concat(FashionSoundsByCharacter.Keys)
                .Concat(FashionComponentSoundsByCharacter.Keys)
                .Concat(SuppressedEquipmentSoundsByCharacter.Keys)
                .Concat(SuppressedEquipmentComponentSoundsByCharacter.Keys)
                .Concat(EmptyFashionCharacters)
                .Concat(ActiveCharacters)
                .Concat(OriginalSpriteMasksByCharacter.Keys)
                .Where(IsCharacterStale)
                .Distinct()
                .ToList();

            foreach (Character character in characters)
            {
                RestoreSpriteMasks(character);
                FashionSpritesByCharacter.Remove(character);
                FashionHiddenWearableTypesByCharacter.Remove(character);
                ForceHideHairCharacters.Remove(character);
                FashionAnimationsByCharacter.Remove(character);
                FashionSoundsByCharacter.Remove(character);
                FashionComponentSoundsByCharacter.Remove(character);
                ClearSuppressedEquipmentSounds(character);
                ClearSuppressedEquipmentComponentSounds(character);
                FashionSoundCursorByCharacter.Remove(character);
                FashionComponentSoundCursorByCharacter.Remove(character);
                EmptyFashionCharacters.Remove(character);
                EmptyFashionSlotsByCharacter.Remove(character);
                SavedFashionSlotsByCharacter.Remove(character);
                ActiveCharacters.Remove(character);
                OriginalSpriteMasksByCharacter.Remove(character);
            }
        }

        public static int CaptureFashionItem(Character character, Item item)
        {
            if (character == null || item == null) { return 0; }

            EmptyFashionCharacters.Remove(character);
            int animationCount = CaptureFashionAnimations(character, item);
            int soundCount = CaptureFashionSounds(character, item);
            int itemSoundCount = CaptureFashionComponentSounds(character, item);
            Wearable wearable = item.GetComponent<Wearable>();
            if (wearable?.wearableSprites == null || wearable.wearableSprites.Length == 0)
            {
                drawOverrideLogCount = 0;
                ActiveCharacters.Remove(character);
                LuaCsLogger.Log($"[Baro Wardrobe Switcher] Captured 0 wearable sprites, {animationCount} animation triggers, {soundCount} status sound triggers, and {itemSoundCount} item sound components from fashion item without wearable sprites: {item.Name}.");
                return 0;
            }

            if (!FashionSpritesByCharacter.TryGetValue(character, out Dictionary<Tuple<WearableType, LimbType>, List<WearableSprite>> spritesBySlot))
            {
                spritesBySlot = new Dictionary<Tuple<WearableType, LimbType>, List<WearableSprite>>();
                FashionSpritesByCharacter[character] = spritesBySlot;
            }

            int count = 0;
            foreach (WearableSprite sprite in wearable.wearableSprites.Where(sprite => sprite != null))
            {
                if (!IsEquipmentSprite(sprite))
                {
                    continue;
                }
                CaptureFashionHiddenWearableTypes(character, sprite);
                Tuple<WearableType, LimbType> key = Tuple.Create(sprite.Type, sprite.Limb);
                if (!spritesBySlot.TryGetValue(key, out List<WearableSprite> spriteList))
                {
                    spriteList = new List<WearableSprite>();
                    spritesBySlot[key] = spriteList;
                }
                spriteList.Add(CreateFashionSpriteClone(character, sprite));
                count++;
            }
            drawOverrideLogCount = 0;
            ActiveCharacters.Remove(character);
            LuaCsLogger.Log($"[Baro Wardrobe Switcher] Captured {count} wearable sprites, {animationCount} animation triggers, {soundCount} status sound triggers, and {itemSoundCount} item sound components from fashion item: {item.Name}.");
            return count;
        }

        public static int CaptureFashionPrefab(Character character, string identifier)
        {
            if (character == null || string.IsNullOrWhiteSpace(identifier)) { return 0; }

            try
            {
                Identifier prefabIdentifier = new Identifier(identifier);
                if (!ItemPrefab.Prefabs.TryGet(prefabIdentifier, out ItemPrefab prefab) || prefab == null)
                {
                    LuaCsLogger.Log($"[Baro Wardrobe Switcher] Could not find fashion prefab by identifier: {identifier}.");
                    return 0;
                }

                Item tempItem = null;
                try
                {
                    tempItem = new Item(prefab, Vector2.Zero, null, 0, false);
                    int captured = CaptureFashionItem(character, tempItem);
                    LuaCsLogger.Log($"[Baro Wardrobe Switcher] Captured {captured} wearable sprite(s) from fashion prefab fallback: {identifier}.");
                    return captured;
                }
                finally
                {
                    try
                    {
                        tempItem?.Remove();
                    }
                    catch (Exception ex)
                    {
                        LuaCsLogger.Log($"[Baro Wardrobe Switcher] Failed to remove temporary fashion prefab item {identifier}: {ex.GetType().Name}: {ex.Message}");
                    }
                }
            }
            catch (Exception ex)
            {
                LuaCsLogger.Log($"[Baro Wardrobe Switcher] Fashion prefab fallback failed for {identifier}: {ex.GetType().Name}: {ex.Message}");
                return 0;
            }
        }

        public static bool CaptureEmptyFashion(Character character)
        {
            if (character == null) { return false; }
            EmptyFashionCharacters.Add(character);
            ActiveCharacters.Remove(character);
            drawOverrideLogCount = 0;
            LuaCsLogger.Log("[Baro Wardrobe Switcher] Captured empty fashion look.");
            return true;
        }

        public static bool SetFashionSlots(Character character, string savedSlotsCsv, string emptySlotsCsv)
        {
            if (character == null) { return false; }
            SavedFashionSlotsByCharacter[character] = ParseSlotCsv(savedSlotsCsv);
            EmptyFashionSlotsByCharacter[character] = ParseSlotCsv(emptySlotsCsv);
            LuaCsLogger.Log(
                "[Baro Wardrobe Switcher] Fashion slot mask: saved=" +
                DescribeSavedSlots(character) +
                ", empty=" +
                DescribeEmptySlots(character) +
                ".");
            return true;
        }

        // Opt-in hiding of the character's own hair/beard/moustache while a saved look
        // is active, so helmets and hats that do not declare HideWearablesOfType no longer
        // leave hair poking through. Only takes visible effect while the look is active.
        public static bool SetHideHair(Character character, bool hideHair)
        {
            if (character == null) { return false; }
            bool changed = hideHair
                ? ForceHideHairCharacters.Add(character)
                : ForceHideHairCharacters.Remove(character);
            if (changed)
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] Fashion hair visibility set: hideHair=" + hideHair + ".");
                RefreshWearables(character);
            }
            return true;
        }

        public static bool ApplyFashionItemVisual(Character character, Item item, bool carrier)
        {
            if (character == null || item == null) { return false; }
            if (!HasFashionPayload(character))
            {
                return false;
            }

            RegisterSuppressedEquipmentSounds(character, item);
            RegisterSuppressedEquipmentComponentSounds(character, item);

            Wearable wearable = item.GetComponent<Wearable>();
            if (wearable?.wearableSprites == null || wearable.wearableSprites.Length == 0)
            {
                return ActivateFashionVisual(character);
            }

            int sanitized = SanitizeEquippedItemMasks(character, wearable);
            bool activated = ActivateFashionVisual(character);
            if (carrier)
            {
                int capturedSprites = FashionSpritesByCharacter.TryGetValue(character, out Dictionary<Tuple<WearableType, LimbType>, List<WearableSprite>> spritesBySlot)
                    ? spritesBySlot.Values.Sum(spriteList => spriteList.Count)
                    : 0;
                LuaCsLogger.Log($"[Baro Wardrobe Switcher] Enabled draw-only fashion override through carrier: {item.Name}, capturedSprites={capturedSprites}, sanitizedSprites={sanitized}.");
            }
            drawOverrideLogCount = 0;
            return activated;
        }

        public static bool ActivateFashionVisual(Character character)
        {
            if (character == null || !HasFashionPayload(character)) { return false; }
            ActiveCharacters.Add(character);
            drawOverrideLogCount = 0;
            virtualDrawErrorLogCount = 0;
            animationOverrideErrorLogCount = 0;
            soundOverrideErrorLogCount = 0;
            lastInjectedSpriteCount = 0;
            drawOverrideHitCount = 0;
            drawOverrideMissCount = 0;
            drawOverrideHiddenAfterDrawCount = 0;
            drawOverrideHiddenEmptySlotCount = 0;
            drawOverrideHiddenSavedSlotCount = 0;
            drawOverrideHiddenAttachmentCount = 0;
            RefreshWearables(character);
            return true;
        }

        internal static bool TryOverrideDrawWearable(Limb limb, WearableSprite original, out WearableSprite replacement, out bool skipOriginal)
        {
            replacement = null;
            skipOriginal = false;
            if (limb == null || original == null) { return false; }
            if (limb.character == null || !ActiveCharacters.Contains(limb.character)) { return false; }
            if (storedFashionDrawDepth > 0) { return false; }
            if (!IsEquipmentSprite(original))
            {
                if (ShouldHideAttachmentForFashion(limb.character, original))
                {
                    skipOriginal = true;
                    drawOverrideHiddenAttachmentCount++;
                    if (drawOverrideLogCount < 12)
                    {
                        drawOverrideLogCount++;
                        LuaCsLogger.Log($"[Baro Wardrobe Switcher] DrawWearable hidden attachment for fashion mask: limb={limb.type}, type={original.Type}.");
                    }
                    return true;
                }
                return false;
            }
            if (!DrawnFashionSpritesByLimb.TryGetValue(limb, out HashSet<WearableSprite> drawnSprites))
            {
                drawnSprites = new HashSet<WearableSprite>();
                DrawnFashionSpritesByLimb[limb] = drawnSprites;
            }
            if (IsInjectedFashionSprite(limb, original))
            {
                drawnSprites.Add(original);
                drawOverrideHitCount++;
                return false;
            }
            bool hideOriginalForEmptySavedSlot = ShouldHideOriginalForEmptySavedSlot(limb.character, original);
            bool hideOriginalForSavedSlot = ShouldHideOriginalForSavedSlot(limb.character, original);
            if (!TryGetFashionSprite(limb.character, original.Type, limb.type, drawnSprites, out WearableSprite fashionSprite))
            {
                if (hideOriginalForEmptySavedSlot)
                {
                    skipOriginal = true;
                    drawOverrideHiddenEmptySlotCount++;
                    if (drawOverrideLogCount < 12)
                    {
                        drawOverrideLogCount++;
                        LuaCsLogger.Log($"[Baro Wardrobe Switcher] DrawWearable hidden original for empty saved slot: limb={limb.type}, type={original.Type}, slots={DescribeWearableSlots(original)}.");
                    }
                    return true;
                }
                if (hideOriginalForSavedSlot)
                {
                    skipOriginal = true;
                    drawOverrideHiddenSavedSlotCount++;
                    if (drawOverrideLogCount < 12)
                    {
                        drawOverrideLogCount++;
                        LuaCsLogger.Log($"[Baro Wardrobe Switcher] DrawWearable hidden original for saved slot override: limb={limb.type}, type={original.Type}, slots={DescribeWearableSlots(original)}.");
                    }
                    return true;
                }
                if (FashionSpriteAlreadyDrawn(limb.character, original.Type, limb.type, drawnSprites))
                {
                    skipOriginal = true;
                    drawOverrideHiddenAfterDrawCount++;
                    if (drawOverrideLogCount < 12)
                    {
                        drawOverrideLogCount++;
                        LuaCsLogger.Log($"[Baro Wardrobe Switcher] DrawWearable hidden original after fashion draw: limb={limb.type}, type={original.Type}.");
                    }
                    return true;
                }
                drawOverrideMissCount++;
                if (drawOverrideLogCount < 12)
                {
                    drawOverrideLogCount++;
                    LuaCsLogger.Log($"[Baro Wardrobe Switcher] DrawWearable kept original; no fashion sprite matched: limb={limb.type}, type={original.Type}.");
                }
                return false;
            }

            if (hideOriginalForSavedSlot)
            {
                skipOriginal = true;
                drawOverrideHiddenSavedSlotCount++;
                if (drawOverrideLogCount < 12)
                {
                    drawOverrideLogCount++;
                    LuaCsLogger.Log($"[Baro Wardrobe Switcher] DrawWearable hidden original for saved slot; stored fashion will be fallback drawn: limb={limb.type}, type={original.Type}.");
                }
                return true;
            }
            drawOverrideMissCount++;
            if (drawOverrideLogCount < 12)
            {
                drawOverrideLogCount++;
                LuaCsLogger.Log($"[Baro Wardrobe Switcher] DrawWearable kept original; stored fashion will be fallback drawn: limb={limb.type}, type={original.Type}.");
            }
            return false;
        }

        internal static void BeginLimbDraw(Limb limb)
        {
            try
            {
                if (limb?.character == null || !ActiveCharacters.Contains(limb.character)) { return; }
                if (!FashionSpritesByCharacter.TryGetValue(limb.character, out Dictionary<Tuple<WearableType, LimbType>, List<WearableSprite>> spritesBySlot) ||
                    spritesBySlot.Count == 0)
                {
                    return;
                }
                DrawnFashionSpritesByLimb[limb] = new HashSet<WearableSprite>();
                InjectFashionSpritesForLimb(limb, spritesBySlot);
            }
            catch (Exception ex)
            {
                LogVirtualDrawError($"Failed to begin fashion limb draw: {ex.GetType().Name}: {ex.Message}");
            }
        }

        internal static Exception EndLimbDraw(Limb limb, Exception exception = null)
        {
            try
            {
                if (limb == null) { return exception; }
                List<WearableSprite> injectedSprites = null;
                if (InjectedFashionSpritesByLimb.TryGetValue(limb, out injectedSprites))
                {
                    InjectedFashionSpritesByLimb.Remove(limb);
                }
                HashSet<WearableSprite> injectedSet = injectedSprites == null
                    ? new HashSet<WearableSprite>()
                    : new HashSet<WearableSprite>(injectedSprites);

                List<WearableSprite> wearingItems = limb.WearingItems;
                if (wearingItems == null)
                {
                    OriginalWearableOrderByLimb.Remove(limb);
                    DrawnFashionSpritesByLimb.Remove(limb);
                    return FinalizeLimbDrawException(limb, exception);
                }

                if (OriginalWearableOrderByLimb.TryGetValue(limb, out List<WearableSprite> originalOrder))
                {
                    List<WearableSprite> remainingWearables = wearingItems
                        .Where(wearable => wearable != null && !injectedSet.Contains(wearable))
                        .ToList();
                    wearingItems.Clear();
                    foreach (WearableSprite originalWearable in originalOrder)
                    {
                        if (originalWearable == null || !remainingWearables.Contains(originalWearable) || wearingItems.Contains(originalWearable))
                        {
                            continue;
                        }
                        wearingItems.Add(originalWearable);
                    }
                    foreach (WearableSprite remainingWearable in remainingWearables)
                    {
                        if (remainingWearable != null && !wearingItems.Contains(remainingWearable))
                        {
                            wearingItems.Add(remainingWearable);
                        }
                    }
                    OriginalWearableOrderByLimb.Remove(limb);
                }
                else if (injectedSprites != null)
                {
                    foreach (WearableSprite injectedSprite in injectedSprites)
                    {
                        wearingItems.RemoveAll(wearable => wearable == injectedSprite);
                    }
                }
                DrawnFashionSpritesByLimb.Remove(limb);
            }
            catch (Exception ex)
            {
                LogVirtualDrawError($"Failed to end fashion limb draw: {ex.GetType().Name}: {ex.Message}");
                if (limb != null)
                {
                    OriginalWearableOrderByLimb.Remove(limb);
                    InjectedFashionSpritesByLimb.Remove(limb);
                    DrawnFashionSpritesByLimb.Remove(limb);
                }
            }
            return FinalizeLimbDrawException(limb, exception);
        }

        private static void InjectFashionSpritesForLimb(
            Limb limb,
            Dictionary<Tuple<WearableType, LimbType>, List<WearableSprite>> spritesBySlot)
        {
            if (limb == null || spritesBySlot == null || spritesBySlot.Count == 0) { return; }

            List<WearableSprite> wearingItems = limb.WearingItems;
            if (wearingItems == null) { return; }

            List<WearableSprite> spritesToInject = EnumerateFashionSpritesForLimb(spritesBySlot, limb.type)
                .Select(pair => pair.Value)
                .Where(sprite => sprite != null && !wearingItems.Contains(sprite))
                .Distinct()
                .ToList();
            if (spritesToInject.Count == 0) { return; }

            if (!OriginalWearableOrderByLimb.ContainsKey(limb))
            {
                OriginalWearableOrderByLimb[limb] = wearingItems
                    .Where(wearable => wearable != null)
                    .ToList();
            }

            if (!InjectedFashionSpritesByLimb.TryGetValue(limb, out List<WearableSprite> injectedSprites))
            {
                injectedSprites = new List<WearableSprite>();
                InjectedFashionSpritesByLimb[limb] = injectedSprites;
            }

            foreach (WearableSprite sprite in spritesToInject)
            {
                wearingItems.Add(sprite);
                injectedSprites.Add(sprite);
            }

            SortWearablesForDraw(wearingItems);
            lastInjectedSpriteCount = spritesToInject.Count;
        }

        private static bool IsInjectedFashionSprite(Limb limb, WearableSprite sprite)
        {
            return limb != null &&
                   sprite != null &&
                   InjectedFashionSpritesByLimb.TryGetValue(limb, out List<WearableSprite> injectedSprites) &&
                   injectedSprites.Contains(sprite);
        }

        private static Exception FinalizeLimbDrawException(Limb limb, Exception exception)
        {
            if (exception == null) { return null; }
            if (limb?.character == null || !ActiveCharacters.Contains(limb.character)) { return exception; }
            if (exception is ArgumentNullException argumentNullException &&
                string.Equals(argumentNullException.ParamName, "source", StringComparison.Ordinal))
            {
                LogVirtualDrawError($"Suppressed wardrobe Limb.Draw transition exception for limb={limb.type}: {exception.GetType().Name}: {exception.Message}");
                return null;
            }
            return exception;
        }

        internal static void DrawMissingFashionSprites(Limb limb, SpriteBatch spriteBatch, Color? overrideColor)
        {
            try
            {
                if (limb?.character == null || spriteBatch == null || !ActiveCharacters.Contains(limb.character)) { return; }
                if (!FashionSpritesByCharacter.TryGetValue(limb.character, out Dictionary<Tuple<WearableType, LimbType>, List<WearableSprite>> spritesBySlot) ||
                    spritesBySlot.Count == 0)
                {
                    return;
                }
                if (DrawWearableMethod == null)
                {
                    LogVirtualDrawError("Limb.DrawWearable method was not found.");
                    return;
                }

                if (!DrawnFashionSpritesByLimb.TryGetValue(limb, out HashSet<WearableSprite> drawnSprites))
                {
                    drawnSprites = new HashSet<WearableSprite>();
                }

                int defaultDepthIndex = Math.Max((limb.WearingItems?.Count ?? 0) + DefaultFallbackDepthPadding, DefaultFallbackDepthPadding);
                int recessedDepthIndex = RecessedFallbackDepthStart;
                foreach (KeyValuePair<Tuple<WearableType, LimbType>, WearableSprite> pair in EnumerateFashionSpritesForLimb(spritesBySlot, limb.type))
                {
                    if (drawnSprites.Contains(pair.Value)) { continue; }
                    if (!ShouldFallbackDrawMissingFashionSprite(pair.Value, limb.type)) { continue; }

                    drawnSprites.Add(pair.Value);
                    fallbackDrawnFashionSpriteCount++;
                    int depthIndex = UsesRecessedFashionLayer(pair.Value) ? recessedDepthIndex++ : defaultDepthIndex++;
                    DrawFashionWearable(limb, pair.Value, depthIndex, spriteBatch, overrideColor);
                }
            }
            catch (Exception ex)
            {
                LogVirtualDrawError($"Failed to draw missing fashion sprites: {ex.GetType().Name}: {ex.Message}");
            }
            finally
            {
                if (limb != null)
                {
                    DrawnFashionSpritesByLimb.Remove(limb);
                }
            }
        }

        private static void DrawFashionWearable(Limb limb, WearableSprite wearable, int depthIndex, SpriteBatch spriteBatch, Color? overrideColor)
        {
            try
            {
                Color color = overrideColor.GetValueOrDefault(Color.White);
                color *= limb.Alpha;
                if (color.A <= 0) { return; }

                SpriteEffects spriteEffect = limb.Dir > 0.0f ? SpriteEffects.None : SpriteEffects.FlipHorizontally;
                if (limb.Params.MirrorHorizontally)
                {
                    spriteEffect = spriteEffect == SpriteEffects.None ? SpriteEffects.FlipHorizontally : SpriteEffects.None;
                }
                if (limb.Params.MirrorVertically)
                {
                    spriteEffect |= SpriteEffects.FlipVertically;
                }

                storedFashionDrawDepth++;
                try
                {
                    DrawWearableMethod.Invoke(
                        limb,
                        new object[]
                        {
                            wearable,
                            DrawDepthStep * depthIndex,
                            spriteBatch,
                            color,
                            color.A / 255.0f,
                            spriteEffect
                        });
                }
                finally
                {
                    storedFashionDrawDepth--;
                }
            }
            catch (Exception ex)
            {
                LogVirtualDrawError($"Failed to draw stored fashion sprite: {ex.GetType().Name}: {ex.Message}");
            }
        }

        internal static void KeepFashionEffectsAlive(AnimController animController)
        {
            KeepFashionAnimationsAlive(animController);
            KeepFashionSoundsAlive(animController);
        }

        internal static bool ShouldLoadTemporaryAnimation(AnimController animController, object animationInfo)
        {
            Character character = animController?.Character;
            if (character == null || !ActiveCharacters.Contains(character)) { return true; }

            bool hasFashionAnimations = FashionAnimationsByCharacter.TryGetValue(character, out List<object> animationInfos) &&
                                        animationInfos.Count > 0;
            if (hasFashionAnimations) { return true; }

            return !IsLargeEquipmentMovementAnimation(animationInfo);
        }

        private static void KeepFashionAnimationsAlive(AnimController animController)
        {
            Character character = animController?.Character;
            if (character == null || !ActiveCharacters.Contains(character)) { return; }
            if (!FashionAnimationsByCharacter.TryGetValue(character, out List<object> animationInfos) || animationInfos.Count == 0) { return; }
            if (TryLoadTemporaryAnimationMethod == null)
            {
                LogAnimationError("AnimController.TryLoadTemporaryAnimation method was not found.");
                return;
            }

            foreach (object animationInfo in animationInfos)
            {
                try
                {
                    TryLoadTemporaryAnimationMethod.Invoke(animController, new[] { animationInfo, false });
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
            if (character == null || !ActiveCharacters.Contains(character)) { return; }

            if (FashionSoundsByCharacter.TryGetValue(character, out List<FashionSoundEffect> statusSounds))
            {
                foreach (FashionSoundEffect fashionSound in statusSounds)
                {
                    if (fashionSound?.StatusEffect == null || !HasLoopingSound(fashionSound.StatusEffect)) { continue; }
                    TryPlaySpecificFashionSound(
                        character,
                        fashionSound.StatusEffect,
                        character,
                        character.CurrentHull,
                        character.WorldPosition);
                }
            }

            if (FashionComponentSoundsByCharacter.TryGetValue(character, out List<FashionComponentSound> componentSounds))
            {
                foreach (FashionComponentSound fashionSound in componentSounds)
                {
                    if (fashionSound?.Component == null || !HasLoopingComponentSound(fashionSound.Component, fashionSound.ActionType)) { continue; }
                    TryPlaySpecificFashionComponentSound(character, fashionSound.Component, fashionSound.ActionType, character);
                }
            }
        }

        private static bool HasFashionPayload(Character character)
        {
            if (character == null) { return false; }
            bool hasEmptyLook = EmptyFashionCharacters.Contains(character);
            bool hasSprites = FashionSpritesByCharacter.TryGetValue(character, out Dictionary<Tuple<WearableType, LimbType>, List<WearableSprite>> spritesBySlot) &&
                              spritesBySlot.Values.Sum(spriteList => spriteList.Count) > 0;
            bool hasAnimations = FashionAnimationsByCharacter.TryGetValue(character, out List<object> animationInfos) &&
                                 animationInfos.Count > 0;
            bool hasSounds = FashionSoundsByCharacter.TryGetValue(character, out List<FashionSoundEffect> soundEffects) &&
                             soundEffects.Count > 0;
            bool hasComponentSounds = FashionComponentSoundsByCharacter.TryGetValue(character, out List<FashionComponentSound> componentSounds) &&
                                      componentSounds.Count > 0;
            return hasEmptyLook || hasSprites || hasAnimations || hasSounds || hasComponentSounds;
        }

        private static int CaptureFashionAnimations(Character character, Item item)
        {
            if (character == null || item?.Components == null) { return 0; }
            if (AnimationsToTriggerField == null) { return 0; }

            if (!FashionAnimationsByCharacter.TryGetValue(character, out List<object> animationInfos))
            {
                animationInfos = new List<object>();
                FashionAnimationsByCharacter[character] = animationInfos;
            }

            int count = 0;
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
                        object boostedAnimationInfo = BoostFashionAnimationPriority(animationInfo);
                        if (boostedAnimationInfo == null || animationInfos.Contains(boostedAnimationInfo)) { continue; }
                        animationInfos.Add(boostedAnimationInfo);
                        count++;
                    }
                }
            }

            return count;
        }

        private static int CaptureFashionSounds(Character character, Item item)
        {
            if (character == null || item?.Components == null) { return 0; }
            if (SoundsField == null) { return 0; }

            if (!FashionSoundsByCharacter.TryGetValue(character, out List<FashionSoundEffect> soundEffects))
            {
                soundEffects = new List<FashionSoundEffect>();
                FashionSoundsByCharacter[character] = soundEffects;
            }

            int count = 0;
            foreach (ItemComponent component in item.Components)
            {
                if (component?.statusEffectLists == null) { continue; }
                if (!component.statusEffectLists.TryGetValue(ActionType.OnWearing, out List<StatusEffect> statusEffects)) { continue; }
                foreach (StatusEffect statusEffect in statusEffects)
                {
                    if (!HasSounds(statusEffect)) { continue; }
                    if (soundEffects.Any(soundEffect => ReferenceEquals(soundEffect.StatusEffect, statusEffect))) { continue; }

                    soundEffects.Add(new FashionSoundEffect(statusEffect));
                    count++;
                }
            }

            return count;
        }

        private static int CaptureFashionComponentSounds(Character character, Item item)
        {
            if (character == null || item?.Components == null || ComponentSoundsField == null) { return 0; }

            if (!FashionComponentSoundsByCharacter.TryGetValue(character, out List<FashionComponentSound> componentSounds))
            {
                componentSounds = new List<FashionComponentSound>();
                FashionComponentSoundsByCharacter[character] = componentSounds;
            }

            int count = 0;
            foreach (ItemComponent component in item.Components)
            {
                if (component == null || !HasComponentSounds(component)) { continue; }
                foreach (ActionType actionType in GetComponentSoundTypes(component))
                {
                    if (componentSounds.Any(sound => ReferenceEquals(sound.Component, component) && sound.ActionType == actionType)) { continue; }
                    componentSounds.Add(new FashionComponentSound(component, actionType));
                    count++;
                }
            }

            return count;
        }

        private static void RegisterSuppressedEquipmentSounds(Character character, Item item)
        {
            if (character == null || item?.Components == null || SoundsField == null) { return; }
            // When the saved look carries its own sounds we suppress every matching real
            // equipment sound and replace it. When the look is silent we still have to
            // silence looping real-equipment sounds (diving suits, exosuits, beeping
            // headsets); otherwise they keep beeping while the look hides the gear, which
            // mirrors how ShouldLoadTemporaryAnimation suppresses their movement animation.
            bool hasFashionSound = HasAnyFashionSound(character);
            if (!SuppressedEquipmentSoundsByCharacter.TryGetValue(character, out HashSet<StatusEffect> suppressedSounds))
            {
                suppressedSounds = new HashSet<StatusEffect>();
                SuppressedEquipmentSoundsByCharacter[character] = suppressedSounds;
            }

            foreach (ItemComponent component in item.Components)
            {
                if (component?.statusEffectLists == null) { continue; }
                if (!component.statusEffectLists.TryGetValue(ActionType.OnWearing, out List<StatusEffect> statusEffects)) { continue; }
                foreach (StatusEffect statusEffect in statusEffects)
                {
                    if (!HasSounds(statusEffect)) { continue; }
                    if (IsFashionStatusSound(character, statusEffect)) { continue; }
                    if (!hasFashionSound && !HasLoopingSound(statusEffect)) { continue; }
                    suppressedSounds.Add(statusEffect);
                    SuppressedEquipmentSoundOwners[statusEffect] = character;
                }
            }
        }

        private static void RegisterSuppressedEquipmentComponentSounds(Character character, Item item)
        {
            if (character == null || item?.Components == null || ComponentSoundsField == null) { return; }
            // Same rule as the status-effect sounds above: a silent saved look still has to
            // silence looping real-equipment item sounds so cosmetic gear stops beeping.
            bool hasFashionSound = HasAnyFashionSound(character);
            if (!SuppressedEquipmentComponentSoundsByCharacter.TryGetValue(character, out HashSet<ItemComponent> suppressedComponents))
            {
                suppressedComponents = new HashSet<ItemComponent>();
                SuppressedEquipmentComponentSoundsByCharacter[character] = suppressedComponents;
            }

            foreach (ItemComponent component in item.Components)
            {
                if (component == null || !HasComponentSounds(component)) { continue; }
                if (IsFashionComponentSound(character, component)) { continue; }
                if (!hasFashionSound && !HasAnyLoopingComponentSound(component)) { continue; }
                suppressedComponents.Add(component);
                SuppressedEquipmentComponentSoundOwners[component] = character;
            }
        }

        private static void ClearSuppressedEquipmentSounds(Character character)
        {
            if (character == null) { return; }
            if (SuppressedEquipmentSoundsByCharacter.TryGetValue(character, out HashSet<StatusEffect> suppressedSounds))
            {
                foreach (StatusEffect statusEffect in suppressedSounds.ToList())
                {
                    SuppressedEquipmentSoundOwners.Remove(statusEffect);
                }
                SuppressedEquipmentSoundsByCharacter.Remove(character);
            }
        }

        private static void ClearSuppressedEquipmentComponentSounds(Character character)
        {
            if (character == null) { return; }
            if (SuppressedEquipmentComponentSoundsByCharacter.TryGetValue(character, out HashSet<ItemComponent> suppressedComponents))
            {
                foreach (ItemComponent component in suppressedComponents.ToList())
                {
                    SuppressedEquipmentComponentSoundOwners.Remove(component);
                }
                SuppressedEquipmentComponentSoundsByCharacter.Remove(character);
            }
        }

        internal static bool ShouldPlayOriginalStatusEffectSound(StatusEffect statusEffect, Entity entity, Hull hull, Vector2 worldPosition)
        {
            if (statusEffect == null) { return true; }
            if (!SuppressedEquipmentSoundOwners.TryGetValue(statusEffect, out Character character)) { return true; }
            if (character == null || !ActiveCharacters.Contains(character)) { return true; }
            if (!HasAnyFashionSound(character))
            {
                return false;
            }
            if (HasLoopingSound(statusEffect))
            {
                // Looping equipment sounds retrigger every update; force-restarting a
                // one-shot fashion sound for each retrigger produces continuous beeping.
                // Looping fashion sounds are kept alive separately by KeepFashionSoundsAlive.
                return false;
            }

            bool played = FashionSoundsByCharacter.TryGetValue(character, out List<FashionSoundEffect> fashionSounds) &&
                          TryPlayReplacementFashionSound(character, fashionSounds, entity, hull, worldPosition);
            if (!played && FashionComponentSoundsByCharacter.TryGetValue(character, out List<FashionComponentSound> componentSounds))
            {
                played = TryPlayReplacementFashionComponentSound(character, componentSounds, ActionType.OnWearing, character);
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
            if (!SuppressedEquipmentComponentSoundOwners.TryGetValue(component, out Character character)) { return true; }
            if (character == null || !ActiveCharacters.Contains(character)) { return true; }
            if (user != null && character != user) { return true; }
            if (!HasAnyFashionSound(character))
            {
                return false;
            }
            if (HasLoopingComponentSound(component, actionType))
            {
                // Same as looping status-effect sounds: never replay one-shot fashion
                // sounds for every retrigger of a looping equipment sound.
                return false;
            }

            bool played = FashionComponentSoundsByCharacter.TryGetValue(character, out List<FashionComponentSound> fashionSounds) &&
                          TryPlayReplacementFashionComponentSound(character, fashionSounds, actionType, user ?? character);
            if (!played && FashionSoundsByCharacter.TryGetValue(character, out List<FashionSoundEffect> statusSounds))
            {
                played = TryPlayReplacementFashionSound(
                    character,
                    statusSounds,
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
            if (character == null) { return false; }
            bool hasStatusSounds = FashionSoundsByCharacter.TryGetValue(character, out List<FashionSoundEffect> statusSounds) &&
                                   statusSounds.Count > 0;
            bool hasComponentSounds = FashionComponentSoundsByCharacter.TryGetValue(character, out List<FashionComponentSound> componentSounds) &&
                                      componentSounds.Count > 0;
            return hasStatusSounds || hasComponentSounds;
        }

        private static bool IsFashionStatusSound(Character character, StatusEffect statusEffect)
        {
            return character != null &&
                   statusEffect != null &&
                   FashionSoundsByCharacter.TryGetValue(character, out List<FashionSoundEffect> statusSounds) &&
                   statusSounds.Any(sound => ReferenceEquals(sound.StatusEffect, statusEffect));
        }

        private static bool IsFashionComponentSound(Character character, ItemComponent component)
        {
            return character != null &&
                   component != null &&
                   FashionComponentSoundsByCharacter.TryGetValue(character, out List<FashionComponentSound> componentSounds) &&
                   componentSounds.Any(sound => ReferenceEquals(sound.Component, component));
        }

        private static bool TryPlayReplacementFashionSound(
            Character character,
            List<FashionSoundEffect> fashionSounds,
            Entity entity,
            Hull hull,
            Vector2 worldPosition)
        {
            if (character == null || fashionSounds == null || fashionSounds.Count == 0 || PlaySoundMethod == null)
            {
                return false;
            }

            int cursor = FashionSoundCursorByCharacter.TryGetValue(character, out int storedCursor) ? storedCursor : 0;
            for (int offset = 0; offset < fashionSounds.Count; offset++)
            {
                int index = (cursor + offset) % fashionSounds.Count;
                FashionSoundEffect fashionSound = fashionSounds[index];
                if (fashionSound?.StatusEffect == null) { continue; }

                FashionSoundCursorByCharacter[character] = (index + 1) % fashionSounds.Count;
                return TryPlaySpecificFashionSound(
                    character,
                    fashionSound.StatusEffect,
                    entity,
                    hull,
                    worldPosition,
                    forceRestart: true);
            }

            return false;
        }

        private static bool TryPlaySpecificFashionSound(
            Character character,
            StatusEffect statusEffect,
            Entity entity,
            Hull hull,
            Vector2 worldPosition,
            bool forceRestart = false)
        {
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

                PlaySoundMethod.Invoke(
                    statusEffect,
                    new object[]
                    {
                        entity ?? character,
                        hull ?? character.CurrentHull,
                        worldPosition
                    });
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
            Character character,
            List<FashionComponentSound> fashionSounds,
            ActionType actionType,
            Character user)
        {
            if (character == null || fashionSounds == null || fashionSounds.Count == 0) { return false; }

            int cursor = FashionComponentSoundCursorByCharacter.TryGetValue(character, out int storedCursor) ? storedCursor : 0;
            for (int pass = 0; pass < 2; pass++)
            {
                for (int offset = 0; offset < fashionSounds.Count; offset++)
                {
                    int index = (cursor + offset) % fashionSounds.Count;
                    FashionComponentSound fashionSound = fashionSounds[index];
                    if (fashionSound?.Component == null) { continue; }
                    if (pass == 0 && fashionSound.ActionType != actionType) { continue; }

                    FashionComponentSoundCursorByCharacter[character] = (index + 1) % fashionSounds.Count;
                    return TryPlaySpecificFashionComponentSound(
                        character,
                        fashionSound.Component,
                        fashionSound.ActionType,
                        user ?? character);
                }
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

        private static bool HasAnyLoopingComponentSound(ItemComponent component)
        {
            if (component == null) { return false; }
            foreach (ActionType actionType in GetComponentSoundTypes(component))
            {
                if (HasLoopingComponentSound(component, actionType)) { return true; }
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

        private static IEnumerable<KeyValuePair<Tuple<WearableType, LimbType>, WearableSprite>> EnumerateFashionSpritesForLimb(
            Dictionary<Tuple<WearableType, LimbType>, List<WearableSprite>> spritesBySlot,
            LimbType limbType)
        {
            return spritesBySlot
                .Where(pair =>
                    pair.Value != null &&
                    (pair.Key.Item2 == limbType || pair.Key.Item2 == LimbType.None))
                .SelectMany(pair => pair.Value
                    .Where(sprite => SpriteBelongsToLimb(sprite, pair.Key.Item2, limbType))
                    .Select(sprite => new KeyValuePair<Tuple<WearableType, LimbType>, WearableSprite>(pair.Key, sprite)))
                .OrderBy(pair => GetFashionLayerSortKey(pair.Value))
                .ThenByDescending(pair => pair.Value.Sprite?.Depth ?? 0.0f);
        }

        private static void SortWearablesForDraw(List<WearableSprite> wearingItems)
        {
            if (wearingItems == null) { return; }
            List<WearableSprite> sortedWearables = wearingItems
                .Select((wearable, index) => new { Wearable = wearable, Index = index })
                .OrderBy(entry => GetFashionLayerSortKey(entry.Wearable))
                .ThenByDescending(entry => entry.Wearable?.Sprite?.Depth ?? 0.0f)
                .ThenBy(entry => entry.Index)
                .Select(entry => entry.Wearable)
                .ToList();

            wearingItems.Clear();
            wearingItems.AddRange(sortedWearables);
        }

        private static int GetFashionLayerSortKey(WearableSprite sprite)
        {
            if (sprite == null) { return 0; }
            if (sprite.WearableComponent?.AllowedSlots == null) { return 1; }
            if (SlotContains(sprite, InvSlotType.Bag)) { return 2; }
            if (SlotContains(sprite, InvSlotType.HealthInterface)) { return 3; }
            if (SlotContains(sprite, InvSlotType.InnerClothes)) { return 4; }
            if (IsHeadSlotSprite(sprite)) { return 5; }
            if (SlotContains(sprite, InvSlotType.OuterClothes)) { return 6; }
            return 5;
        }

        private static bool UsesRecessedFashionLayer(WearableSprite sprite)
        {
            return SlotContains(sprite, InvSlotType.Bag) ||
                   SlotContains(sprite, InvSlotType.HealthInterface);
        }

        private static string GetFashionLayerName(WearableSprite sprite)
        {
            if (sprite == null) { return "nil"; }
            if (SlotContains(sprite, InvSlotType.Bag)) { return "bag-recessed"; }
            if (SlotContains(sprite, InvSlotType.HealthInterface)) { return "health-recessed"; }
            if (SlotContains(sprite, InvSlotType.InnerClothes)) { return "inner"; }
            if (IsHeadSlotSprite(sprite)) { return "head"; }
            if (SlotContains(sprite, InvSlotType.OuterClothes)) { return "outer"; }
            return "default";
        }

        private static bool IsHeadSlotSprite(WearableSprite sprite)
        {
            return SlotContains(sprite, InvSlotType.Head) ||
                   SlotContains(sprite, InvSlotType.Headset);
        }

        private static bool IsHeadVisualSprite(WearableSprite sprite)
        {
            return IsHeadSlotSprite(sprite) ||
                   sprite?.Limb == LimbType.Head;
        }

        private static bool SlotContains(WearableSprite sprite, InvSlotType slot)
        {
            return sprite?.WearableComponent?.AllowedSlots != null &&
                   sprite.WearableComponent.AllowedSlots.Contains(slot);
        }

        private static bool ShouldFallbackDrawMissingFashionSprite(WearableSprite sprite, LimbType limbType)
        {
            if (sprite == null) { return false; }
            if (sprite.Limb != LimbType.None)
            {
                return sprite.Limb == limbType;
            }
            return GetFallbackAnchorLimb(sprite) == limbType;
        }

        private static bool SpriteBelongsToLimb(WearableSprite sprite, LimbType spriteLimb, LimbType limbType)
        {
            if (sprite == null) { return false; }
            if (spriteLimb != LimbType.None) { return spriteLimb == limbType; }
            return GetFallbackAnchorLimb(sprite) == limbType;
        }

        private static LimbType GetFallbackAnchorLimb(WearableSprite sprite)
        {
            Wearable wearable = sprite?.WearableComponent;
            if (wearable?.AllowedSlots == null) { return LimbType.None; }
            if (wearable.AllowedSlots.Contains(InvSlotType.Head) ||
                wearable.AllowedSlots.Contains(InvSlotType.Headset))
            {
                return LimbType.Head;
            }
            if (wearable.AllowedSlots.Contains(InvSlotType.InnerClothes) ||
                wearable.AllowedSlots.Contains(InvSlotType.OuterClothes) ||
                wearable.AllowedSlots.Contains(InvSlotType.Bag) ||
                wearable.AllowedSlots.Contains(InvSlotType.HealthInterface))
            {
                return LimbType.Torso;
            }
            return LimbType.None;
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
                    priority + FashionAnimationPriorityBoost,
                    expectedSpeciesProperty.GetValue(animationInfo)
                });
            }
            catch (Exception ex)
            {
                LogAnimationError($"Failed to boost fashion animation priority: {ex.GetType().Name}: {ex.Message}");
                return animationInfo;
            }
        }

        private static bool IsLargeEquipmentMovementAnimation(object animationInfo)
        {
            if (animationInfo == null) { return false; }
            Type animationInfoType = animationInfo.GetType();
            try
            {
                PropertyInfo typeProperty = animationInfoType.GetProperty("Type");
                PropertyInfo fileProperty = animationInfoType.GetProperty("File");
                string animationType = typeProperty?.GetValue(animationInfo)?.ToString();
                if (!string.Equals(animationType, "Walk", StringComparison.OrdinalIgnoreCase) &&
                    !string.Equals(animationType, "Run", StringComparison.OrdinalIgnoreCase))
                {
                    return false;
                }

                string file = fileProperty?.GetValue(animationInfo)?.ToString() ?? string.Empty;
                return file.IndexOf("Exosuit", StringComparison.OrdinalIgnoreCase) >= 0 ||
                       file.IndexOf("DivingSuit", StringComparison.OrdinalIgnoreCase) >= 0;
            }
            catch (Exception ex)
            {
                LogAnimationError($"Failed to inspect temporary animation: {ex.GetType().Name}: {ex.Message}");
                return false;
            }
        }

        private static void LogVirtualDrawError(string message)
        {
            if (virtualDrawErrorLogCount >= 6) { return; }
            virtualDrawErrorLogCount++;
            LuaCsLogger.Log($"[Baro Wardrobe Switcher] {message}");
        }

        private static void LogAnimationError(string message)
        {
            if (animationOverrideErrorLogCount >= 6) { return; }
            animationOverrideErrorLogCount++;
            LuaCsLogger.Log($"[Baro Wardrobe Switcher] {message}");
        }

        private static void LogSoundError(string message)
        {
            if (soundOverrideErrorLogCount >= 6) { return; }
            soundOverrideErrorLogCount++;
            LuaCsLogger.Log($"[Baro Wardrobe Switcher] {message}");
        }

        internal static MethodInfo FindLimbDrawMethod()
        {
            return FindLimbDrawMethods().FirstOrDefault();
        }

        private static IEnumerable<MethodInfo> FindLimbDrawMethods()
        {
            return AccessTools.GetDeclaredMethods(typeof(Limb))
                .Where(method =>
                    method.Name == "Draw" &&
                    method.GetParameters().Any(parameter => parameter.ParameterType == typeof(SpriteBatch)));
        }

        private static string DescribeMethod(MethodInfo method)
        {
            if (method == null) { return "null"; }
            string parameters = string.Join(",", method.GetParameters().Select(parameter => parameter.ParameterType.Name));
            return method.Name + "(" + parameters + ")";
        }

        private static bool IsEquipmentSprite(WearableSprite sprite)
        {
            return sprite != null && sprite.Type == WearableType.Item;
        }

        private static HashSet<InvSlotType> ParseSlotCsv(string slotsCsv)
        {
            HashSet<InvSlotType> slots = new HashSet<InvSlotType>();
            if (string.IsNullOrWhiteSpace(slotsCsv)) { return slots; }

            foreach (string part in slotsCsv.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries))
            {
                string slotName = part.Trim();
                if (Enum.TryParse(slotName, true, out InvSlotType slotType))
                {
                    slots.Add(slotType);
                }
            }
            return slots;
        }

        private static bool ShouldHideOriginalForEmptySavedSlot(Character character, WearableSprite original)
        {
            if (character == null || original?.WearableComponent?.AllowedSlots == null) { return false; }
            if (!EmptyFashionSlotsByCharacter.TryGetValue(character, out HashSet<InvSlotType> emptySlots) || emptySlots.Count == 0)
            {
                return false;
            }

            return original.WearableComponent.AllowedSlots.Any(slot => emptySlots.Contains(slot));
        }

        private static void CaptureFashionHiddenWearableTypes(Character character, WearableSprite sprite)
        {
            if (character == null || sprite?.HideWearablesOfType == null || sprite.HideWearablesOfType.Count == 0) { return; }
            foreach (WearableType hiddenType in sprite.HideWearablesOfType)
            {
                if (!FashionHideableAttachmentTypes.Contains(hiddenType)) { continue; }
                if (!FashionHiddenWearableTypesByCharacter.TryGetValue(character, out HashSet<WearableType> hiddenTypes))
                {
                    hiddenTypes = new HashSet<WearableType>();
                    FashionHiddenWearableTypesByCharacter[character] = hiddenTypes;
                }
                hiddenTypes.Add(hiddenType);
            }
        }

        private static bool ShouldHideAttachmentForFashion(Character character, WearableSprite original)
        {
            if (character == null || original == null) { return false; }
            if (FashionHiddenWearableTypesByCharacter.TryGetValue(character, out HashSet<WearableType> hiddenTypes) &&
                hiddenTypes.Contains(original.Type))
            {
                return true;
            }
            return ForceHideHairCharacters.Contains(character) &&
                   HairAttachmentTypes.Contains(original.Type);
        }

        private static string DescribeFashionHiddenTypes(Character character)
        {
            if (character == null ||
                !FashionHiddenWearableTypesByCharacter.TryGetValue(character, out HashSet<WearableType> hiddenTypes) ||
                hiddenTypes.Count == 0)
            {
                return "none";
            }
            return string.Join(",", hiddenTypes.Select(type => type.ToString()).OrderBy(name => name));
        }

        private static bool ShouldHideOriginalForSavedSlot(Character character, WearableSprite original)
        {
            if (character == null || original?.WearableComponent?.AllowedSlots == null) { return false; }
            if (!SavedFashionSlotsByCharacter.TryGetValue(character, out HashSet<InvSlotType> savedSlots) || savedSlots.Count == 0)
            {
                return false;
            }

            return original.WearableComponent.AllowedSlots.Any(slot => savedSlots.Contains(slot));
        }

        private static string DescribeWearableSlots(WearableSprite sprite)
        {
            if (sprite?.WearableComponent?.AllowedSlots == null) { return "none"; }
            return string.Join(",", sprite.WearableComponent.AllowedSlots.Select(slot => slot.ToString()).OrderBy(slot => slot));
        }

        private static string DescribeSavedSlots(Character character)
        {
            return DescribeSlotSet(SavedFashionSlotsByCharacter, character);
        }

        private static string DescribeEmptySlots(Character character)
        {
            return DescribeSlotSet(EmptyFashionSlotsByCharacter, character);
        }

        private static string DescribeSlotSet(Dictionary<Character, HashSet<InvSlotType>> slotsByCharacter, Character character)
        {
            if (character == null ||
                !slotsByCharacter.TryGetValue(character, out HashSet<InvSlotType> slots) ||
                slots == null ||
                slots.Count == 0)
            {
                return "none";
            }
            return string.Join(",", slots.Select(slot => slot.ToString()).OrderBy(slot => slot));
        }

        private static WearableSprite CreateFashionSpriteClone(Character character, WearableSprite original)
        {
            WearableSprite clone = original;
            try
            {
                clone = MemberwiseCloneMethod?.Invoke(original, null) as WearableSprite ?? original;
            }
            catch (Exception ex)
            {
                LuaCsLogger.Log($"[Baro Wardrobe Switcher] Failed to clone fashion sprite, using original: {ex.GetType().Name}: {ex.Message}");
            }

            if (ReferenceEquals(clone, original))
            {
                SaveOriginalMask(character, clone);
            }
            ClearWearableAttachmentMask(clone);
            if (IsHeadVisualSprite(clone))
            {
                ClearHeadWearableMask(clone);
            }
            return clone;
        }

        private static int SanitizeEquippedItemMasks(Character character, Wearable wearable)
        {
            int count = 0;
            foreach (WearableSprite sprite in wearable.wearableSprites.Where(sprite => IsEquipmentSprite(sprite)))
            {
                SaveOriginalMask(character, sprite);
                ClearMask(sprite);
                count++;
            }
            return count;
        }

        private static void SaveOriginalMask(Character character, WearableSprite sprite)
        {
            if (character == null || sprite == null) { return; }
            if (!OriginalSpriteMasksByCharacter.TryGetValue(character, out Dictionary<WearableSprite, SpriteMaskState> masks))
            {
                masks = new Dictionary<WearableSprite, SpriteMaskState>();
                OriginalSpriteMasksByCharacter[character] = masks;
            }
            if (masks.ContainsKey(sprite)) { return; }
            masks[sprite] = new SpriteMaskState(sprite);
        }

        private static void ClearMask(WearableSprite sprite)
        {
            if (sprite == null) { return; }
            sprite.HideLimb = false;
            sprite.HideWearablesOfType = new List<WearableType>();
            sprite.ObscureOtherWearables = WearableSprite.ObscuringMode.None;
            sprite.CanBeHiddenByOtherWearables = false;
        }

        private static void ClearWearableAttachmentMask(WearableSprite sprite)
        {
            if (sprite == null) { return; }
            sprite.HideWearablesOfType = new List<WearableType>();
            sprite.ObscureOtherWearables = WearableSprite.ObscuringMode.None;
            sprite.CanBeHiddenByOtherWearables = false;
        }

        private static void ClearHeadWearableMask(WearableSprite sprite)
        {
            if (sprite == null) { return; }
            sprite.HideLimb = false;
        }

        private static void RestoreAllSpriteMasks()
        {
            foreach (Character character in OriginalSpriteMasksByCharacter.Keys.ToList())
            {
                RestoreSpriteMasks(character);
            }
            OriginalSpriteMasksByCharacter.Clear();
        }

        private static void RestoreSpriteMasks(Character character)
        {
            if (character == null) { return; }
            if (!OriginalSpriteMasksByCharacter.TryGetValue(character, out Dictionary<WearableSprite, SpriteMaskState> masks))
            {
                return;
            }
            foreach (KeyValuePair<WearableSprite, SpriteMaskState> pair in masks.ToList())
            {
                pair.Value.Restore(pair.Key);
            }
            OriginalSpriteMasksByCharacter.Remove(character);
        }

        private static bool IsCharacterStale(Character character)
        {
            if (character == null) { return true; }
            if (CharacterRemovedProperty == null) { return false; }
            try
            {
                object removed = CharacterRemovedProperty.GetValue(character);
                return removed is bool removedValue && removedValue;
            }
            catch
            {
                return false;
            }
        }

        private static void RefreshWearables(Character character)
        {
            if (character == null) { return; }
            try
            {
                OnWearablesChangedMethod?.Invoke(character, null);
            }
            catch (Exception ex)
            {
                LuaCsLogger.Log($"[Baro Wardrobe Switcher] Failed to refresh wearables: {ex.GetType().Name}: {ex.Message}");
            }
        }

        internal static bool TryGetFashionSprite(
            Character character,
            WearableType type,
            LimbType limbType,
            HashSet<WearableSprite> drawnSprites,
            out WearableSprite sprite)
        {
            sprite = null;
            if (character == null) { return false; }
            if (!FashionSpritesByCharacter.TryGetValue(character, out Dictionary<Tuple<WearableType, LimbType>, List<WearableSprite>> spritesBySlot))
            {
                return false;
            }
            foreach (WearableSprite candidate in EnumerateFashionSpriteCandidates(spritesBySlot, type, limbType))
            {
                if (candidate == null) { continue; }
                if (drawnSprites != null && drawnSprites.Contains(candidate)) { continue; }
                sprite = candidate;
                return true;
            }
            return false;
        }

        private static bool FashionSpriteAlreadyDrawn(
            Character character,
            WearableType type,
            LimbType limbType,
            HashSet<WearableSprite> drawnSprites)
        {
            if (character == null || drawnSprites == null || drawnSprites.Count == 0) { return false; }
            if (!FashionSpritesByCharacter.TryGetValue(character, out Dictionary<Tuple<WearableType, LimbType>, List<WearableSprite>> spritesBySlot))
            {
                return false;
            }
            return EnumerateFashionSpriteCandidates(spritesBySlot, type, limbType)
                .Any(sprite => sprite != null && drawnSprites.Contains(sprite));
        }

        private static IEnumerable<WearableSprite> EnumerateFashionSpriteCandidates(
            Dictionary<Tuple<WearableType, LimbType>, List<WearableSprite>> spritesBySlot,
            WearableType type,
            LimbType limbType)
        {
            if (spritesBySlot == null) { yield break; }

            if (spritesBySlot.TryGetValue(Tuple.Create(type, limbType), out List<WearableSprite> exactSprites) && exactSprites != null)
            {
                foreach (WearableSprite sprite in exactSprites)
                {
                    yield return sprite;
                }
            }

            if (limbType == LimbType.None) { yield break; }
            if (!spritesBySlot.TryGetValue(Tuple.Create(type, LimbType.None), out List<WearableSprite> wildcardSprites) || wildcardSprites == null)
            {
                yield break;
            }
            foreach (WearableSprite sprite in wildcardSprites)
            {
                yield return sprite;
            }
        }

        private static string DescribeFashionSprites(Character character)
        {
            if (character == null) { return "character=nil"; }
            if (!FashionSpritesByCharacter.TryGetValue(character, out Dictionary<Tuple<WearableType, LimbType>, List<WearableSprite>> spritesBySlot) ||
                spritesBySlot.Count == 0)
            {
                return "none";
            }
            return string.Join(";",
                spritesBySlot
                    .OrderBy(pair => pair.Key.Item2.ToString())
                    .ThenBy(pair => pair.Key.Item1.ToString())
                    .Select(pair => pair.Key.Item2 + "/" + pair.Key.Item1 + "=" + (pair.Value?.Count ?? 0)));
        }

        private static string DescribeFashionSpriteLayers(Character character)
        {
            if (character == null) { return "character=nil"; }
            if (!FashionSpritesByCharacter.TryGetValue(character, out Dictionary<Tuple<WearableType, LimbType>, List<WearableSprite>> spritesBySlot) ||
                spritesBySlot.Count == 0)
            {
                return "none";
            }
            return string.Join(";",
                spritesBySlot.Values
                    .Where(spriteList => spriteList != null)
                    .SelectMany(spriteList => spriteList.Where(sprite => sprite != null).Select(GetFashionLayerName))
                    .GroupBy(layer => layer)
                    .OrderBy(group => group.Key)
                    .Select(group => group.Key + "=" + group.Count()));
        }

        private sealed class FashionSoundEffect
        {
            public FashionSoundEffect(StatusEffect statusEffect)
            {
                StatusEffect = statusEffect;
            }

            public StatusEffect StatusEffect { get; }
        }

        private sealed class FashionComponentSound
        {
            public FashionComponentSound(ItemComponent component, ActionType actionType)
            {
                Component = component;
                ActionType = actionType;
            }

            public ItemComponent Component { get; }
            public ActionType ActionType { get; }
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

        private sealed class SpriteMaskState
        {
            private readonly bool hideLimb;
            private readonly List<WearableType> hideWearablesOfType;
            private readonly WearableSprite.ObscuringMode obscureOtherWearables;
            private readonly bool canBeHiddenByOtherWearables;

            public SpriteMaskState(WearableSprite sprite)
            {
                hideLimb = sprite.HideLimb;
                hideWearablesOfType = sprite.HideWearablesOfType == null
                    ? null
                    : new List<WearableType>(sprite.HideWearablesOfType);
                obscureOtherWearables = sprite.ObscureOtherWearables;
                canBeHiddenByOtherWearables = sprite.CanBeHiddenByOtherWearables;
            }

            public void Restore(WearableSprite sprite)
            {
                if (sprite == null) { return; }
                sprite.HideLimb = hideLimb;
                sprite.HideWearablesOfType = hideWearablesOfType == null
                    ? null
                    : new List<WearableType>(hideWearablesOfType);
                sprite.ObscureOtherWearables = obscureOtherWearables;
                sprite.CanBeHiddenByOtherWearables = canBeHiddenByOtherWearables;
            }
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

    internal static class LimbDrawPatch
    {
        private static void Prefix(Limb __instance)
        {
            VisualOverride.BeginLimbDraw(__instance);
        }

        private static void Postfix(Limb __instance, object[] __args)
        {
            SpriteBatch spriteBatch = null;
            Color? overrideColor = null;
            foreach (object arg in __args ?? Array.Empty<object>())
            {
                if (spriteBatch == null && arg is SpriteBatch batch)
                {
                    spriteBatch = batch;
                }
                if (!overrideColor.HasValue && arg is Color color)
                {
                    overrideColor = color;
                }
            }
            VisualOverride.DrawMissingFashionSprites(__instance, spriteBatch, overrideColor);
        }

        private static Exception Finalizer(Limb __instance, Exception __exception)
        {
            return VisualOverride.EndLimbDraw(__instance, __exception);
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
        private static bool Prefix(AnimController __instance, object __0)
        {
            return VisualOverride.ShouldLoadTemporaryAnimation(__instance, __0);
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
}
