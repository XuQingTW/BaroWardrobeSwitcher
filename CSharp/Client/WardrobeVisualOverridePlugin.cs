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
using HarmonyLib;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using LuaCsLogger = BaroWardrobeSwitcher.WardrobeFileLogger;

namespace BaroWardrobeSwitcher
{
    /// <summary>
    /// Keeps routine wardrobe diagnostics out of the in-game console while retaining
    /// them in a dedicated UTF-8 log beside the saved wardrobe data.
    /// </summary>
    public static class WardrobeFileLogger
    {
        private const string LogFileName = "WardrobeClient.log";
        private static readonly object SyncRoot = new object();

        public static string GetPath()
        {
            return Path.Combine(WardrobePersistence.GetStorageDirectory(), LogFileName);
        }

        public static bool Write(string level, string message)
        {
            try
            {
                string path = GetPath();
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                string line =
                    "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] " +
                    "[" + (string.IsNullOrWhiteSpace(level) ? "INFO" : level) + "] " +
                    (message ?? string.Empty) + Environment.NewLine;
                lock (SyncRoot)
                {
                    File.AppendAllText(path, line, Encoding.UTF8);
                }
                return true;
            }
            catch
            {
                // Logging must never interrupt rendering, persistence or shutdown.
                return false;
            }
        }

        public static void Log(string message) => Write("INFO", message);

    }

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

    public static partial class WardrobePersistence
    {
        public const string Version = "0.5.2";
        private const int PersistenceVersion = 3;
        private const string ModFolderName = "BaroWardrobeSwitcher";
        private const string ClientLookFileName = "ClientLook.json";
        private const string VisibilityAuto = "auto";
        private const string VisibilityHide = "hide";
        private const string VisibilityShow = "show";
        internal const string TestStorageRootAppContextKey =
            "BaroWardrobeSwitcher.PersistenceProbe.StorageRoot";
        internal const string TestFailurePointAppContextKey =
            "BaroWardrobeSwitcher.PersistenceProbe.FailurePoint";
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
            WriteIndented = true,
            PropertyNameCaseInsensitive = false,
            UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
        };
        private static string lastError = string.Empty;

        public static string GetVersion()
        {
            return Version;
        }

        public static string GetLastError()
        {
            return lastError ?? string.Empty;
        }

        public static string GetStorageDirectory()
        {
            string testStorageRoot = GetPersistenceProbeStorageRoot();
            if (testStorageRoot != null) { return testStorageRoot; }

            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrWhiteSpace(localAppData))
            {
                throw new InvalidOperationException(
                    "LocalApplicationData is unavailable; client wardrobe persistence is disabled for this session.");
            }
            return Path.Combine(
                localAppData,
                "Daedalic Entertainment GmbH",
                "Barotrauma",
                "ModData",
                ModFolderName);
        }

        public static string GetClientLookPath()
        {
            return Path.Combine(GetStorageDirectory(), ClientLookFileName);
        }

        public static string LoadClientLook()
        {
            ClearLastError();
            try
            {
                string path = GetClientLookPath();
                if (!File.Exists(path)) { return string.Empty; }
                ClientLookDocument document = ReadClientDocument(path, out int migratedFromVersion);
                if (migratedFromVersion > 0)
                {
                    string backupPath = path + ".v" + migratedFromVersion + ".bak";
                    File.Copy(path, backupPath, overwrite: true);
                    WriteJson(path, document);
                    LogPersistenceInfo(
                        "Migrated client wardrobe persistence from schema v" +
                        migratedFromVersion +
                        " to schema v" +
                        PersistenceVersion +
                        ".");
                }
                if (document == null || !HasAnySlot(document.Slots) && !document.Captured)
                {
                    return string.Empty;
                }
                return EncodeClientLook(document);
            }
            catch (JsonException ex)
            {
                QuarantineCorruptFile(GetClientLookPath(), ex);
                return string.Empty;
            }
            catch (InvalidDataException ex)
            {
                QuarantineCorruptFile(GetClientLookPath(), ex);
                return string.Empty;
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to load client look", ex);
                return string.Empty;
            }
        }

        public static bool ClientLookFileExists()
        {
            ClearLastError();
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
            ClearLastError();
            try
            {
                ClientLookDocument document = ParseClientLook(encodedLook);
                if (document == null || !HasAnySlot(document.Slots) && !document.Captured)
                {
                    return ClearClientLook();
                }
                ValidateDocument(document);
                WriteJson(GetClientLookPath(), document);
                return true;
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to save client look", ex);
                return false;
            }
        }

        public static bool SaveMigratedClientLook(string encodedLook, string legacyPath)
        {
            if (!SaveClientLook(encodedLook)) { return false; }
            try
            {
                if (string.IsNullOrWhiteSpace(legacyPath) || !File.Exists(legacyPath)) { return true; }
                if (!string.Equals(
                        Path.GetFileName(legacyPath),
                        "PersistentClientLook.txt",
                        StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidDataException("Refusing to archive an unexpected legacy persistence file.");
                }

                string backupPath = legacyPath + ".v1.bak";
                File.Copy(legacyPath, backupPath, overwrite: true);
                File.Delete(legacyPath);
                LogPersistenceInfo(
                    "Migrated PersistentClientLook.txt to schema v" +
                    PersistenceVersion +
                    " and retained " +
                    Path.GetFileName(backupPath) + ".");
                return true;
            }
            catch (Exception ex)
            {
                LogPersistenceError(
                    "Saved schema v" +
                    PersistenceVersion +
                    " but failed to archive legacy client look",
                    ex);
                return false;
            }
        }

        public static bool QuarantineLegacyClientLook(string legacyPath)
        {
            ClearLastError();
            try
            {
                if (string.IsNullOrWhiteSpace(legacyPath) || !File.Exists(legacyPath)) { return true; }
                if (!string.Equals(
                        Path.GetFileName(legacyPath),
                        "PersistentClientLook.txt",
                        StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidDataException("Refusing to quarantine an unexpected legacy persistence file.");
                }

                string quarantinePath = legacyPath + "." +
                                        DateTime.UtcNow.ToString("yyyyMMddTHHmmssfffZ") +
                                        ".corrupt";
                File.Move(legacyPath, quarantinePath);
                LogPersistenceInfo(
                    "Quarantined unreadable legacy client wardrobe persistence as " +
                    Path.GetFileName(quarantinePath) + ".");
                return true;
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to quarantine legacy client look", ex);
                return false;
            }
        }

        public static bool ClearClientLook()
        {
            ClearLastError();
            try
            {
                WriteJson(
                    GetClientLookPath(),
                    new ClientLookDocument
                    {
                        Version = PersistenceVersion,
                        Captured = false,
                        AttachmentVisibility = CreateAttachmentVisibility(false),
                        Slots = CreateEmptySlots()
                    });
                return true;
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to clear client look", ex);
                return false;
            }
        }

        private static ClientLookDocument ReadClientDocument(string path, out int migratedFromVersion)
        {
            string json = File.ReadAllText(path, Encoding.UTF8);
            using JsonDocument parsed = JsonDocument.Parse(json);
            JsonElement root = parsed.RootElement;
            int version = ReadSchemaVersion(root);
            if (version == PersistenceVersion)
            {
                migratedFromVersion = 0;
                ClientLookDocument current = JsonSerializer.Deserialize<ClientLookDocument>(json, JsonOptions);
                ValidateDocument(current);
                return current;
            }
            if (version == 2)
            {
                LegacyClientLookV2Document legacy =
                    JsonSerializer.Deserialize<LegacyClientLookV2Document>(json, JsonOptions);
                ClientLookDocument migratedDocument = new ClientLookDocument
                {
                    Version = PersistenceVersion,
                    Captured = legacy.Captured,
                    AttachmentVisibility = CreateAttachmentVisibility(legacy.HideHair),
                    Slots = legacy.Slots
                };
                ValidateDocument(migratedDocument);
                migratedFromVersion = 2;
                return migratedDocument;
            }
            if (version == 0 || version == 1)
            {
                ClientLookDocument migratedDocument = MigrateLegacyDocument(root);
                ValidateDocument(migratedDocument);
                migratedFromVersion = 1;
                return migratedDocument;
            }
            throw new InvalidDataException("Unsupported client wardrobe persistence schema: " + version);
        }

        private static void WriteJson<T>(string path, T value)
        {
            string directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            string tempPath = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            string backupPath = path + ".bak";
            string json = JsonSerializer.Serialize(value, JsonOptions);
            try
            {
                using (FileStream stream = new FileStream(tempPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                using (StreamWriter writer = new StreamWriter(stream, new UTF8Encoding(false)))
                {
                    writer.Write(json);
                    writer.Flush();
                    stream.Flush(true);
                }
                ThrowPersistenceProbeFailure("BeforeReplace");
                if (File.Exists(path))
                {
                    try
                    {
                        File.Replace(tempPath, path, backupPath, ignoreMetadataErrors: true);
                    }
                    catch (Exception exception) when (exception is PlatformNotSupportedException || exception is IOException)
                    {
                        ReplaceWithPortableFallback(tempPath, path, backupPath);
                    }
                }
                else
                {
                    File.Move(tempPath, path);
                }
            }
            finally
            {
                if (File.Exists(tempPath))
                {
                    try { File.Delete(tempPath); } catch { }
                }
            }
        }

        private static ClientLookDocument ParseClientLook(string encodedLook)
        {
            Dictionary<string, string> parts = ParseParts(encodedLook);
            ClientLookDocument document = new ClientLookDocument
            {
                Version = PersistenceVersion,
                Captured = GetBoolean(parts, "captured"),
                AttachmentVisibility = ParseAttachmentVisibility(parts),
                Slots = ParseSlots(parts)
            };
            return document;
        }

        private static string EncodeClientLook(ClientLookDocument document)
        {
            List<string> parts = new List<string>
            {
                "captured=" + document.Captured.ToString().ToLowerInvariant(),
                // Activation is runtime state, not persistence. A successfully loaded
                // captured look is returned to Lua as auto-apply intent.
                "active=false",
                "auto=" + document.Captured.ToString().ToLowerInvariant(),
                "hidehair=" + LegacyHideHair(document.AttachmentVisibility).ToString().ToLowerInvariant(),
                "visibilityHair=" + document.AttachmentVisibility.Hair,
                "visibilityBeard=" + document.AttachmentVisibility.Beard,
                "visibilityMoustache=" + document.AttachmentVisibility.Moustache,
                "visibilityFaceAttachment=" + document.AttachmentVisibility.FaceAttachment
            };
            AppendEncodedSlots(parts, document.Slots);
            return string.Join("|", parts);
        }

        private static void AppendEncodedSlots(List<string> parts, Dictionary<string, string> slots)
        {
            if (parts == null || slots == null) { return; }
            foreach (string slotKey in SlotKeys)
            {
                if (!slots.TryGetValue(slotKey, out string identifier) || string.IsNullOrWhiteSpace(identifier)) { continue; }
                // Display names and runtime item ids are intentionally not persisted in
                // schema v3. The Lua facade still receives the legacy comma separator.
                parts.Add(slotKey + "=" + Escape(identifier) + ",");
            }
        }

        private static Dictionary<string, string> ParseSlots(Dictionary<string, string> parts)
        {
            Dictionary<string, string> slots = CreateEmptySlots();
            foreach (string slotKey in SlotKeys)
            {
                if (!parts.TryGetValue(slotKey, out string encodedValue)) { continue; }
                int commaIndex = encodedValue.IndexOf(',');
                string identifier = Unescape(commaIndex < 0 ? encodedValue : encodedValue.Substring(0, commaIndex));
                if (string.IsNullOrWhiteSpace(identifier)) { continue; }
                slots[slotKey] = identifier;
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

        private static bool GetBoolean(Dictionary<string, string> parts, string key)
        {
            return parts != null &&
                   parts.TryGetValue(key, out string value) &&
                   string.Equals(value, "true", StringComparison.OrdinalIgnoreCase);
        }

        private static AttachmentVisibilityDocument ParseAttachmentVisibility(
            Dictionary<string, string> parts)
        {
            string[] keys =
            {
                "visibilityHair",
                "visibilityBeard",
                "visibilityMoustache",
                "visibilityFaceAttachment"
            };
            bool hasAny = keys.Any(key => parts.ContainsKey(key));
            if (!hasAny)
            {
                return CreateAttachmentVisibility(GetBoolean(parts, "hidehair"));
            }
            if (keys.Any(key => !parts.ContainsKey(key)))
            {
                throw new InvalidDataException(
                    "Encoded attachment visibility must include all four layers.");
            }

            var visibility = new AttachmentVisibilityDocument
            {
                Hair = parts["visibilityHair"],
                Beard = parts["visibilityBeard"],
                Moustache = parts["visibilityMoustache"],
                FaceAttachment = parts["visibilityFaceAttachment"]
            };
            ValidateAttachmentVisibility(visibility);
            return visibility;
        }

        private static AttachmentVisibilityDocument CreateAttachmentVisibility(bool hideHair)
        {
            return new AttachmentVisibilityDocument
            {
                Hair = hideHair ? VisibilityHide : VisibilityAuto,
                Beard = hideHair ? VisibilityHide : VisibilityAuto,
                Moustache = hideHair ? VisibilityHide : VisibilityAuto,
                FaceAttachment = VisibilityAuto
            };
        }

        private static AttachmentVisibilityDocument CopyAttachmentVisibility(
            AttachmentVisibilityDocument source)
        {
            ValidateAttachmentVisibility(source);
            return new AttachmentVisibilityDocument
            {
                Hair = source.Hair,
                Beard = source.Beard,
                Moustache = source.Moustache,
                FaceAttachment = source.FaceAttachment
            };
        }

        private static bool LegacyHideHair(AttachmentVisibilityDocument visibility)
        {
            return visibility != null &&
                   string.Equals(visibility.Hair, VisibilityHide, StringComparison.Ordinal) &&
                   string.Equals(visibility.Beard, VisibilityHide, StringComparison.Ordinal) &&
                   string.Equals(visibility.Moustache, VisibilityHide, StringComparison.Ordinal);
        }

        private static bool IsVisibilityState(string value)
        {
            return string.Equals(value, VisibilityAuto, StringComparison.Ordinal) ||
                   string.Equals(value, VisibilityHide, StringComparison.Ordinal) ||
                   string.Equals(value, VisibilityShow, StringComparison.Ordinal);
        }

        private static void ValidateAttachmentVisibility(AttachmentVisibilityDocument visibility)
        {
            if (visibility == null ||
                !IsVisibilityState(visibility.Hair) ||
                !IsVisibilityState(visibility.Beard) ||
                !IsVisibilityState(visibility.Moustache) ||
                !IsVisibilityState(visibility.FaceAttachment))
            {
                throw new InvalidDataException("Attachment visibility is invalid.");
            }
        }

        private static AttachmentVisibilityDocument ReadLegacyAttachmentVisibility(JsonElement root)
        {
            if (TryGetPropertyIgnoreCase(
                    root,
                    "attachmentVisibility",
                    out JsonElement visibilityElement))
            {
                if (visibilityElement.ValueKind != JsonValueKind.Object)
                {
                    throw new InvalidDataException("Legacy attachment visibility is invalid.");
                }
                var visibility = new AttachmentVisibilityDocument();
                if (!TryGetPropertyIgnoreCase(
                        visibilityElement,
                        "Hair",
                        out JsonElement hair) ||
                    !TryGetPropertyIgnoreCase(
                        visibilityElement,
                        "Beard",
                        out JsonElement beard) ||
                    !TryGetPropertyIgnoreCase(
                        visibilityElement,
                        "Moustache",
                        out JsonElement moustache) ||
                    !TryGetPropertyIgnoreCase(
                        visibilityElement,
                        "FaceAttachment",
                        out JsonElement face) ||
                    hair.ValueKind != JsonValueKind.String ||
                    beard.ValueKind != JsonValueKind.String ||
                    moustache.ValueKind != JsonValueKind.String ||
                    face.ValueKind != JsonValueKind.String)
                {
                    throw new InvalidDataException("Legacy attachment visibility is incomplete.");
                }
                visibility.Hair = hair.GetString();
                visibility.Beard = beard.GetString();
                visibility.Moustache = moustache.GetString();
                visibility.FaceAttachment = face.GetString();
                ValidateAttachmentVisibility(visibility);
                return visibility;
            }
            return CreateAttachmentVisibility(ReadBoolean(root, "hideHair"));
        }

        private static bool HasAnySlot(Dictionary<string, string> slots)
        {
            return slots != null &&
                   slots.Values.Any(identifier => !string.IsNullOrWhiteSpace(identifier));
        }

        private static int ReadSchemaVersion(JsonElement root)
        {
            if (root.ValueKind != JsonValueKind.Object)
            {
                throw new InvalidDataException("Client wardrobe persistence root is not an object.");
            }
            foreach (JsonProperty property in root.EnumerateObject())
            {
                if (!string.Equals(property.Name, "schemaVersion", StringComparison.OrdinalIgnoreCase) &&
                    !string.Equals(property.Name, "version", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }
                if (property.Value.ValueKind == JsonValueKind.Number && property.Value.TryGetInt32(out int version))
                {
                    return version;
                }
                throw new InvalidDataException("Client wardrobe persistence schema version is invalid.");
            }
            return 0;
        }

        private static ClientLookDocument MigrateLegacyDocument(JsonElement root)
        {
            if (root.ValueKind != JsonValueKind.Object)
            {
                throw new InvalidDataException("Legacy client wardrobe document is empty.");
            }

            Dictionary<string, string> slots = CreateEmptySlots();
            if (TryGetPropertyIgnoreCase(root, "slots", out JsonElement legacySlots))
            {
                if (legacySlots.ValueKind != JsonValueKind.Object)
                {
                    throw new InvalidDataException("Legacy client wardrobe slots are invalid.");
                }
                foreach (JsonProperty slot in legacySlots.EnumerateObject())
                {
                    string canonicalKey = SlotKeys.FirstOrDefault(
                        key => string.Equals(key, slot.Name, StringComparison.OrdinalIgnoreCase));
                    if (canonicalKey == null) { continue; }
                    string identifier = ReadLegacyIdentifier(slot.Value);
                    if (!string.IsNullOrWhiteSpace(identifier)) { slots[canonicalKey] = identifier; }
                }
            }

            bool captured = ReadBoolean(root, "captured") ||
                            ReadBoolean(root, "active") ||
                            ReadBoolean(root, "autoApply") ||
                            ReadBoolean(root, "auto") ||
                            HasAnySlot(slots);
            return new ClientLookDocument
            {
                Version = PersistenceVersion,
                Captured = captured,
                AttachmentVisibility = ReadLegacyAttachmentVisibility(root),
                Slots = slots
            };
        }

        private static string ReadLegacyIdentifier(JsonElement value)
        {
            if (value.ValueKind == JsonValueKind.Null) { return null; }
            if (value.ValueKind == JsonValueKind.String) { return value.GetString(); }
            if (value.ValueKind == JsonValueKind.Object &&
                TryGetPropertyIgnoreCase(value, "identifier", out JsonElement identifier) &&
                (identifier.ValueKind == JsonValueKind.String || identifier.ValueKind == JsonValueKind.Null))
            {
                return identifier.ValueKind == JsonValueKind.Null ? null : identifier.GetString();
            }
            throw new InvalidDataException("Legacy client wardrobe slot identifier is invalid.");
        }

        private static bool ReadBoolean(JsonElement root, string name)
        {
            if (!TryGetPropertyIgnoreCase(root, name, out JsonElement value)) { return false; }
            if (value.ValueKind == JsonValueKind.True) { return true; }
            if (value.ValueKind == JsonValueKind.False || value.ValueKind == JsonValueKind.Null) { return false; }
            return value.ValueKind == JsonValueKind.String &&
                   bool.TryParse(value.GetString(), out bool parsed) &&
                   parsed;
        }

        private static bool TryGetPropertyIgnoreCase(JsonElement root, string name, out JsonElement value)
        {
            foreach (JsonProperty property in root.EnumerateObject())
            {
                if (string.Equals(property.Name, name, StringComparison.OrdinalIgnoreCase))
                {
                    value = property.Value;
                    return true;
                }
            }
            value = default;
            return false;
        }

        private static Dictionary<string, string> CreateEmptySlots()
        {
            Dictionary<string, string> slots = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (string key in SlotKeys)
            {
                slots[key] = null;
            }
            return slots;
        }

        private static void ValidateDocument(ClientLookDocument document)
        {
            if (document == null) { throw new InvalidDataException("Client wardrobe document is empty."); }
            if (document.Version != PersistenceVersion)
            {
                throw new InvalidDataException("Client wardrobe schema mismatch: " + document.Version);
            }
            ValidateAttachmentVisibility(document.AttachmentVisibility);
            document.Slots ??= CreateEmptySlots();
            foreach (string key in document.Slots.Keys.ToList())
            {
                if (!SlotKeys.Contains(key, StringComparer.Ordinal))
                {
                    document.Slots.Remove(key);
                    continue;
                }
                string identifier = document.Slots[key]?.Trim();
                if (string.IsNullOrWhiteSpace(identifier))
                {
                    document.Slots[key] = null;
                    continue;
                }
                if (Encoding.UTF8.GetByteCount(identifier) > 256)
                {
                    throw new InvalidDataException("Wardrobe identifier exceeds 256 UTF-8 bytes for slot " + key + ".");
                }
                document.Slots[key] = identifier;
            }
            foreach (string key in SlotKeys)
            {
                if (!document.Slots.ContainsKey(key)) { document.Slots[key] = null; }
            }
        }

        private static string GetPersistenceProbeStorageRoot()
        {
            object configuredRoot = AppContext.GetData(TestStorageRootAppContextKey);
            if (configuredRoot == null) { return null; }
            EnsurePersistenceProbeHost();
            if (!(configuredRoot is string root) || string.IsNullOrWhiteSpace(root))
            {
                throw new InvalidOperationException("Persistence probe storage root is invalid.");
            }
            return Path.GetFullPath(root);
        }

        private static void ThrowPersistenceProbeFailure(string point)
        {
            object configuredPoint = AppContext.GetData(TestFailurePointAppContextKey);
            if (configuredPoint == null) { return; }
            EnsurePersistenceProbeHost();
            if (configuredPoint is string failurePoint &&
                string.Equals(failurePoint, point, StringComparison.Ordinal))
            {
                throw new IOException("Injected persistence probe failure at " + point + ".");
            }
        }

        private static void EnsurePersistenceProbeHost()
        {
            string entryAssemblyName = Assembly.GetEntryAssembly()?.GetName().Name;
            if (!string.Equals(entryAssemblyName, "PersistenceProbe", StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "Persistence test seams are disabled outside the PersistenceProbe executable.");
            }
        }

        private static void ReplaceWithPortableFallback(string tempPath, string path, string backupPath)
        {
            if (File.Exists(path))
            {
                File.Copy(path, backupPath, overwrite: true);
            }
            File.Move(tempPath, path, overwrite: true);
        }

        private static void QuarantineCorruptFile(string path, Exception reason)
        {
            try
            {
                if (!File.Exists(path)) { return; }
                string quarantinePath = path + "." + DateTime.UtcNow.ToString("yyyyMMddTHHmmssfffZ") + ".corrupt";
                File.Move(path, quarantinePath);
                LogPersistenceInfo(
                    "Quarantined unreadable client wardrobe persistence as " +
                    Path.GetFileName(quarantinePath) + ": " + reason.GetType().Name + ": " + reason.Message);
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to quarantine unreadable client wardrobe persistence", ex);
            }
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
            lastError = message + ": " + ex.GetType().Name + ": " + ex.Message;
            LogPersistenceInfo(lastError);
        }

        private static void ClearLastError()
        {
            lastError = string.Empty;
        }

        private static void LogPersistenceInfo(string message)
        {
            try
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] " + message);
            }
            catch
            {
                // Persistence must not depend on the game logger being initialized. This
                // also keeps the isolated PersistenceProbe free of game startup state.
            }
        }

        private sealed class ClientLookDocument
        {
            [JsonRequired]
            [JsonPropertyName("schemaVersion")]
            public int Version { get; set; }
            [JsonRequired]
            [JsonPropertyName("captured")]
            public bool Captured { get; set; }
            [JsonRequired]
            [JsonPropertyName("attachmentVisibility")]
            public AttachmentVisibilityDocument AttachmentVisibility { get; set; }
            [JsonRequired]
            [JsonPropertyName("slots")]
            public Dictionary<string, string> Slots { get; set; }

        }

        private sealed class AttachmentVisibilityDocument
        {
            [JsonRequired]
            [JsonPropertyName("Hair")]
            public string Hair { get; set; }
            [JsonRequired]
            [JsonPropertyName("Beard")]
            public string Beard { get; set; }
            [JsonRequired]
            [JsonPropertyName("Moustache")]
            public string Moustache { get; set; }
            [JsonRequired]
            [JsonPropertyName("FaceAttachment")]
            public string FaceAttachment { get; set; }
        }

        private sealed class LegacyClientLookV2Document
        {
            [JsonRequired]
            [JsonPropertyName("schemaVersion")]
            public int Version { get; set; }
            [JsonRequired]
            [JsonPropertyName("captured")]
            public bool Captured { get; set; }
            [JsonRequired]
            [JsonPropertyName("hideHair")]
            public bool HideHair { get; set; }
            [JsonRequired]
            [JsonPropertyName("slots")]
            public Dictionary<string, string> Slots { get; set; }
        }
    }

    public static class VisualOverride
    {

        public const string Version = "0.5.2";

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
                                  ",itemSound=" + HasCapability("itemSound") + ")";

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
                   ", sprites=" + spriteCount +
                   ", animations=" + animationCount +
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
                session.IsActive = false;
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
                session.SuppressedEquipmentSounds.Clear();
                session.SuppressedEquipmentComponentSounds.Clear();
                session.IsActive = false;
                session.ForceHideAttachmentMask = 0;
                session.ForceShowAttachmentMask = 0;
                session.EmptySlots.Clear();
                session.SavedSlots.Clear();
            }
            fallbackDrawnFashionSpriteCount = 0;
            RefreshWearables(character);
        }

        public static void ClearCharacter(Character character)
        {
            if (character == null) { return; }
            if (RenderSessions.TryGetValue(character, out RenderSession session))
            {
                session.Dispose();
                RenderSessions.Remove(character);
            }
            RefreshWearables(character);
        }

        public static void PruneStaleCharacters()
        {
            List<Character> characters = RenderSessions.Keys.Where(IsCharacterStale).ToList();

            foreach (Character character in characters)
            {
                if (RenderSessions.TryGetValue(character, out RenderSession session))
                {
                    session.Dispose();
                    RenderSessions.Remove(character);
                }
            }
        }

        private static RenderSession GetOrCreateSession(Character character)
        {
            if (character == null) { return null; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session))
            {
                session = new RenderSession(character);
                RenderSessions[character] = session;
            }
            return session;
        }

        private static RenderSession GetCaptureSession(Character character)
        {
            return GetOrCreateSession(character)?.CaptureTarget;
        }

        public static bool BeginFashionTransaction(Character character)
        {
            if (character == null || !HasCapability("renderer")) { return false; }
            try
            {
                GetOrCreateSession(character).BeginPendingCapture();
                return true;
            }
            catch (Exception ex)
            {
                LuaCsLogger.Log(
                    "[Baro Wardrobe Switcher] Failed to begin fashion capture transaction: " +
                    ex.GetType().Name + ": " + ex.Message);
                return false;
            }
        }

        public static bool CommitFashionTransaction(Character character)
        {
            if (character == null || !RenderSessions.TryGetValue(character, out RenderSession current)) { return false; }
            RenderSession staged = current.DetachPendingCapture();
            if (staged == null) { return false; }

            string error = null;
            if (!staged.Validate(out error) || !HasFashionPayload(staged))
            {
                staged.Dispose();
                LuaCsLogger.Log(
                    "[Baro Wardrobe Switcher] Fashion capture transaction rejected; previous session preserved: " +
                    (error ?? "staged session contains no fashion payload") + ".");
                return false;
            }

            staged.MarkCommitted();
            RenderSessions[character] = staged;
            current.Dispose();
            LuaCsLogger.Log("[Baro Wardrobe Switcher] Fashion capture transaction committed atomically.");
            return true;
        }

        public static bool CanReuseCapturedFashion(Character character)
        {
            if (character == null || !HasCapability("renderer")) { return false; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session) ||
                !session.IsCommitted ||
                session.HasPendingCapture ||
                !HasFashionPayload(session))
            {
                return false;
            }
            return session.Validate(out _);
        }

        public static bool AbortFashionTransaction(Character character)
        {
            if (character == null || !RenderSessions.TryGetValue(character, out RenderSession current)) { return false; }
            bool aborted = current.AbortPendingCapture();
            if (aborted)
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] Fashion capture transaction aborted; previous session preserved.");
            }
            return aborted;
        }

        public static int CaptureFashionItem(Character character, Item item)
        {
            return CaptureFashionItemCore(character, item, takeOwnership: false, out _);
        }

        private static int CaptureFashionItemCore(
            Character character,
            Item item,
            bool takeOwnership,
            out bool capturedSuccessfully)
        {
            capturedSuccessfully = false;
            if (character == null || item == null || !HasCapability("renderer")) { return 0; }

            RenderSession session = GetCaptureSession(character);
            session.EmptyLook = false;
            session.IsActive = false;
            Wearable wearable = item.GetComponent<Wearable>();
            if (wearable == null)
            {
                string failure = "Fashion item has no Wearable component: " +
                                 (item.Prefab?.Identifier.ToString() ?? item.Name.ToString());
                session.MarkInvalid(failure);
                LuaCsLogger.Log("[Baro Wardrobe Switcher] " + failure + ". Activation refused.");
                return 0;
            }
            List<FashionSpriteDescriptor> stagedDescriptors = new List<FashionSpriteDescriptor>();
            if (wearable?.wearableSprites != null)
            {
                foreach (WearableSprite source in wearable.wearableSprites.Where(sprite => sprite != null && IsEquipmentSprite(sprite)))
                {
                    bool preserveMasks = FashionEffectPolicy.ShouldPreserveSealedSuitMasks(item);
                    if (!FashionSpriteDescriptor.TryCreate(
                            character,
                            item,
                            source,
                            preserveMasks,
                            out FashionSpriteDescriptor descriptor,
                            out string error))
                    {
                        foreach (FashionSpriteDescriptor staged in stagedDescriptors) { staged.Dispose(); }
                        string failure = "Failed to create initialized fashion sprite for " +
                                         (item.Prefab?.Identifier.ToString() ?? item.Name.ToString()) + ": " + error;
                        session.MarkInvalid(failure);
                        LuaCsLogger.Log("[Baro Wardrobe Switcher] " + failure + ". Activation refused.");
                        return 0;
                    }
                    stagedDescriptors.Add(descriptor);
                }
            }

            int animationCount;
            int soundCount;
            int itemSoundCount;
            try
            {
                animationCount = CaptureFashionAnimations(session, item);
                soundCount = CaptureFashionSounds(session, item);
                itemSoundCount = CaptureFashionComponentSounds(session, item);

                foreach (FashionSpriteDescriptor descriptor in stagedDescriptors)
                {
                    session.Add(descriptor);
                    LuaCsLogger.Log(
                        "[Baro Wardrobe Switcher] Captured fashion sprite source: identifier=" +
                        descriptor.SourceIdentifier +
                        ", contentPackage=" +
                        descriptor.SourceContentPackage +
                        ", resolvedSpritePath=" +
                        descriptor.ResolvedSpritePath +
                        ".");
                }
                foreach (WearableSprite source in wearable?.wearableSprites?.Where(sprite => sprite != null && IsEquipmentSprite(sprite)) ?? Enumerable.Empty<WearableSprite>())
                {
                    // Capture attachment hiding intent from the source before descriptor
                    // mask sanitization removes it.
                    CaptureFashionHiddenWearableTypes(session, source);
                }
                if (takeOwnership)
                {
                    session.AddOwnedTemporaryItem(item);
                }
            }
            catch (Exception ex)
            {
                foreach (FashionSpriteDescriptor staged in stagedDescriptors) { staged.Dispose(); }
                string failure = "Fashion capture transaction failed: " + ex.GetType().Name + ": " + ex.Message;
                session.MarkInvalid(failure);
                LuaCsLogger.Log("[Baro Wardrobe Switcher] " + failure + ". Activation refused.");
                return 0;
            }
            int count = stagedDescriptors.Count;
            drawOverrideLogCount = 0;
            LuaCsLogger.Log($"[Baro Wardrobe Switcher] Captured {count} wearable sprites, {animationCount} animation triggers, {soundCount} status sound triggers, and {itemSoundCount} item sound components from fashion item: {item.Name}.");
            capturedSuccessfully = true;
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
                    string failure = "Could not find fashion prefab by identifier: " + identifier;
                    GetCaptureSession(character).MarkInvalid(failure);
                    LuaCsLogger.Log("[Baro Wardrobe Switcher] " + failure + ". Activation refused.");
                    return 0;
                }

                Item tempItem = null;
                try
                {
                    tempItem = new Item(prefab, Vector2.Zero, null, 0, false);
                    // The fallback item must keep its components alive for captured
                    // animations and sounds, but it must never reserve a client-side
                    // entity ID. A server spawn can legitimately reuse that ID.
                    tempItem.FreeID();
                    int captured = CaptureFashionItemCore(character, tempItem, takeOwnership: true, out bool succeeded);
                    if (!succeeded) { return 0; }
                    // Ownership was transferred to the render session. It must outlive
                    // descriptors and captured effects and is removed by session.Dispose.
                    tempItem = null;
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
                string failure = $"Fashion prefab fallback failed for {identifier}: {ex.GetType().Name}: {ex.Message}";
                GetCaptureSession(character).MarkInvalid(failure);
                LuaCsLogger.Log("[Baro Wardrobe Switcher] " + failure + ". Activation refused.");
                return 0;
            }
        }

        public static bool CaptureEmptyFashion(Character character)
        {
            if (character == null || !HasCapability("renderer")) { return false; }
            RenderSession session = GetCaptureSession(character);
            session.EmptyLook = true;
            session.IsActive = false;
            drawOverrideLogCount = 0;
            LuaCsLogger.Log("[Baro Wardrobe Switcher] Captured empty fashion look.");
            return true;
        }

        public static bool SetFashionSlots(Character character, string savedSlotsCsv, string emptySlotsCsv)
        {
            if (character == null) { return false; }
            RenderSession session = GetCaptureSession(character);
            session.SavedSlots = ParseSlotCsv(savedSlotsCsv);
            session.EmptySlots = ParseSlotCsv(emptySlotsCsv);
            LuaCsLogger.Log(
                "[Baro Wardrobe Switcher] Fashion slot mask: saved=" +
                DescribeSavedSlots(character) +
                ", empty=" +
                DescribeEmptySlots(character) +
                ".");
            return true;
        }

        public static bool SetAttachmentVisibility(
            Character character,
            int forceHideMask,
            int forceShowMask)
        {
            if (character == null) { return false; }
            if ((forceHideMask & ~AttachmentVisibilityMask) != 0 ||
                (forceShowMask & ~AttachmentVisibilityMask) != 0 ||
                (forceHideMask & forceShowMask) != 0)
            {
                LuaCsLogger.Log(
                    "[Baro Wardrobe Switcher] Rejected invalid attachment visibility masks: hide=0x" +
                    forceHideMask.ToString("X2") +
                    ", show=0x" +
                    forceShowMask.ToString("X2") +
                    ".");
                return false;
            }

            RenderSession session = GetCaptureSession(character);
            bool changed =
                session.ForceHideAttachmentMask != forceHideMask ||
                session.ForceShowAttachmentMask != forceShowMask;
            session.ForceHideAttachmentMask = forceHideMask;
            session.ForceShowAttachmentMask = forceShowMask;
            if (changed)
            {
                LuaCsLogger.Log(
                    "[Baro Wardrobe Switcher] Fashion attachment visibility set: hide=0x" +
                    forceHideMask.ToString("X2") +
                    ", show=0x" +
                    forceShowMask.ToString("X2") +
                    ".");
            }
            return true;
        }

        // Compatibility wrapper for v0.5.1 Lua and third-party integrations.
        public static bool SetHideHair(Character character, bool hideHair)
        {
            return SetAttachmentVisibility(
                character,
                hideHair
                    ? AttachmentHairBit | AttachmentBeardBit | AttachmentMoustacheBit
                    : 0,
                0);
        }

        public static bool ApplyFashionItemVisual(Character character, Item item, bool carrier)
        {
            if (character == null || item == null || !HasCapability("renderer")) { return false; }
            if (!HasFashionPayload(character))
            {
                return false;
            }

            if (HasCapability("statusSound")) { RegisterSuppressedEquipmentSounds(character, item); }
            if (HasCapability("itemSound")) { RegisterSuppressedEquipmentComponentSounds(character, item); }

            Wearable wearable = item.GetComponent<Wearable>();
            if (wearable?.wearableSprites == null || wearable.wearableSprites.Length == 0)
            {
                return ActivateFashionVisual(character);
            }

            bool activated = ActivateFashionVisual(character);
            if (carrier)
            {
                int capturedSprites = GetOrCreateSession(character).SpriteCount;
                LuaCsLogger.Log($"[Baro Wardrobe Switcher] Enabled draw-only fashion override through carrier: {item.Name}, capturedSprites={capturedSprites}.");
            }
            drawOverrideLogCount = 0;
            return activated;
        }

        public static bool ActivateFashionVisual(Character character)
        {
            if (character == null || !HasCapability("renderer") || !HasFashionPayload(character)) { return false; }
            string error = "render session missing";
            if (!RenderSessions.TryGetValue(character, out RenderSession session) || !session.Validate(out error))
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] Fashion activation refused: " + (error ?? "render session missing") + ".");
                return false;
            }
            session.IsActive = true;
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
            if (limb.character == null ||
                !HasCapability("renderer") ||
                !RenderSessions.TryGetValue(limb.character, out RenderSession session) ||
                !session.IsActive ||
                !session.TryGetDrawContext(limb, out object context) ||
                !(context is LimbRenderTransaction transaction) ||
                !transaction.IsOwner)
            {
                return false;
            }
            // This item's left-breast sprite uses LimbType.None, which is also used by
            // rotating appendages in the same ragdoll. Keep the visual on the actual
            // LeftBoobs limb without changing None handling for any other content.
            if (!IsFashionSpriteCompatibleWithLimb(session, original, limb))
            {
                transaction.DrawnSprites.Add(original);
                skipOriginal = true;
                return true;
            }
            if (transaction.IsDrawingStoredFashion) { return false; }
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
            HashSet<WearableSprite> drawnSprites = transaction.DrawnSprites;
            if (transaction.InjectedSprites.Contains(original))
            {
                // Fail closed at the actual draw boundary. A stale dictionary key or
                // interrupted render transaction must never draw one limb's sprite on
                // another physical limb.
                if (!SpriteBelongsToLimb(original, limb.type))
                {
                    skipOriginal = true;
                    return true;
                }
                drawnSprites.Add(original);
                drawOverrideHitCount++;
                return false;
            }
            bool hideOriginalForEmptySavedSlot = ShouldHideOriginalForEmptySavedSlot(limb.character, original);
            // Empty is an explicit appearance choice. Resolve it before looking for
            // a same-type fashion sprite that may belong to a different saved slot.
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
            bool hideOriginalForSavedSlot = ShouldHideOriginalForSavedSlot(limb.character, original);
            if (!TryGetFashionSprite(limb.character, original.Type, limb.type, drawnSprites, out WearableSprite fashionSprite))
            {
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

        internal static LimbRenderTransaction BeginLimbDraw(Limb limb)
        {
            LimbRenderTransaction transaction = new LimbRenderTransaction(limb);
            try
            {
                if (limb?.character == null ||
                    !HasCapability("renderer") ||
                    !RenderSessions.TryGetValue(limb.character, out RenderSession session) ||
                    !session.IsActive ||
                    !session.Validate(out string validationError))
                {
                    return transaction;
                }
                if (!session.TryEnterDraw(limb, transaction))
                {
                    return transaction;
                }
                transaction.Begin(session);
                return transaction;
            }
            catch (Exception ex)
            {
                LogVirtualDrawError($"Failed to begin fashion limb draw: {ex.GetType().Name}: {ex.Message}");
                try
                {
                    transaction.Cleanup();
                }
                catch (Exception cleanupException)
                {
                    LogVirtualDrawError(
                        "Fashion limb draw begin failed and cleanup also failed: " +
                        cleanupException.GetType().Name + ": " + cleanupException.Message);
                }
                if (limb?.character != null && RenderSessions.TryGetValue(limb.character, out RenderSession session))
                {
                    session.MarkInvalid("render transaction failed: " + ex.GetType().Name + ": " + ex.Message);
                }
                return transaction;
            }
        }

        internal static Exception EndLimbDraw(Limb limb, LimbRenderTransaction transaction, Exception exception = null)
        {
            Exception cleanupException = null;
            try
            {
                transaction?.Cleanup();
            }
            catch (Exception ex)
            {
                cleanupException = ex;
                LogVirtualDrawError($"Failed to end fashion limb draw: {ex.GetType().Name}: {ex.Message}");
            }
            // Harmony finalizers suppress an exception only when they return null. The
            // original draw exception always wins and is returned by reference unchanged;
            // a cleanup failure is propagated only when there was no draw failure.
            return exception ?? cleanupException;
        }

        internal static void DrawMissingFashionSprites(
            Limb limb,
            LimbRenderTransaction transaction,
            SpriteBatch spriteBatch,
            Color? overrideColor)
        {
            if (limb?.character == null || spriteBatch == null || transaction == null || !transaction.IsOwner) { return; }
            try
            {
                if (!RenderSessions.TryGetValue(limb.character, out RenderSession session) ||
                    !session.IsActive ||
                    session.SpritesBySlot.Count == 0)
                {
                    return;
                }
                if (DrawWearableMethod == null)
                {
                    LogVirtualDrawError("Limb.DrawWearable method was not found.");
                    return;
                }

                HashSet<WearableSprite> drawnSprites = transaction.DrawnSprites;

                int defaultDepthIndex = Math.Max((limb.WearingItems?.Count ?? 0) + DefaultFallbackDepthPadding, DefaultFallbackDepthPadding);
                int recessedDepthIndex = RecessedFallbackDepthStart;
                foreach (FashionSpriteDescriptor descriptor in EnumerateFashionSpritesForLimb(session.SpritesBySlot, limb.type))
                {
                    WearableSprite sprite = descriptor.Sprite;
                    if (drawnSprites.Contains(sprite)) { continue; }

                    drawnSprites.Add(sprite);
                    fallbackDrawnFashionSpriteCount++;
                    int depthIndex = UsesRecessedFashionLayer(descriptor) ? recessedDepthIndex++ : defaultDepthIndex++;
                    DrawFashionWearable(limb, transaction, sprite, depthIndex, spriteBatch, overrideColor);
                }
            }
            catch (Exception ex)
            {
                LogVirtualDrawError($"Failed to draw missing fashion sprites: {ex.GetType().Name}: {ex.Message}");
                throw;
            }
        }

        private static void DrawFashionWearable(
            Limb limb,
            LimbRenderTransaction transaction,
            WearableSprite wearable,
            int depthIndex,
            SpriteBatch spriteBatch,
            Color? overrideColor)
        {
            if (!SpriteBelongsToLimb(wearable, limb.type)) { return; }
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

            transaction.EnterStoredFashionDraw();
            try
            {
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
                catch (TargetInvocationException ex) when (ex.InnerException != null)
                {
                    ExceptionDispatchInfo.Capture(ex.InnerException).Throw();
                    throw;
                }
            }
            finally
            {
                transaction.ExitStoredFashionDraw();
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
            if (!IsCharacterActive(character) || !HasCapability("animation")) { return true; }
            bool hasFashionAnimations = RenderSessions.TryGetValue(character, out RenderSession session) &&
                                        session.FashionAnimations.Count > 0;
            if (hasFashionAnimations) { return true; }

            return !FashionEffectPolicy.IsLargeEquipmentMovementAnimation(animationInfo);
        }

        private static void KeepFashionAnimationsAlive(AnimController animController)
        {
            Character character = animController?.Character;
            if (!IsCharacterActive(character) || !HasCapability("animation")) { return; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session) || session.FashionAnimations.Count == 0) { return; }
            if (TryLoadTemporaryAnimationMethod == null)
            {
                LogAnimationError("AnimController.TryLoadTemporaryAnimation method was not found.");
                return;
            }

            foreach (object animationInfo in session.FashionAnimations)
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
            if (!IsCharacterActive(character)) { return; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session)) { return; }

            foreach (StatusEffect fashionSound in session.FashionSounds)
            {
                if (fashionSound == null || !HasLoopingSound(fashionSound)) { continue; }
                TryPlaySpecificFashionSound(
                    character,
                    fashionSound,
                    character,
                    character.CurrentHull,
                    character.WorldPosition);
            }

            foreach ((ItemComponent Component, ActionType ActionType) fashionSound in session.FashionComponentSounds)
            {
                if (fashionSound.Component == null || !HasLoopingComponentSound(fashionSound.Component, fashionSound.ActionType)) { continue; }
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

        private static bool IsCharacterActive(Character character)
        {
            return character != null &&
                   RenderSessions.TryGetValue(character, out RenderSession session) &&
                   session.IsActive &&
                   session.IsValid;
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
                    IEnumerable animations = AnimationsToTriggerField.GetValue(statusEffect) as IEnumerable;
                    if (animations == null) { continue; }
                    foreach (object animationInfo in animations)
                    {
                        if (!FashionEffectPolicy.ShouldCaptureAnimation(item, animationInfo)) { continue; }
                        object boostedAnimationInfo = BoostFashionAnimationPriority(animationInfo);
                        if (boostedAnimationInfo == null || animationInfos.Contains(boostedAnimationInfo)) { continue; }
                        animationInfos.Add(boostedAnimationInfo);
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
                    if (!FashionEffectPolicy.ShouldCaptureStatusSound(statusEffect)) { continue; }
                    if (soundEffects.Any(soundEffect => ReferenceEquals(soundEffect, statusEffect))) { continue; }

                    soundEffects.Add(statusEffect);
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
                    count++;
                }
            }

            return count;
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
                    if (FashionEffectPolicy.IsFunctionalEquipmentAlarm(statusEffect))
                    {
                        session.SuppressedEquipmentSounds.Remove(statusEffect);
                        continue;
                    }
                    if (!hasFashionSound && !HasLoopingSound(statusEffect)) { continue; }
                    session.SuppressedEquipmentSounds.Add(statusEffect);
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
                if (!hasFashionSound && !HasAnyLoopingComponentSound(component)) { continue; }
                session.SuppressedEquipmentComponentSounds.Add(component);
            }
        }

        internal static bool ShouldPlayOriginalStatusEffectSound(StatusEffect statusEffect, Entity entity, Hull hull, Vector2 worldPosition)
        {
            if (statusEffect == null) { return true; }
            RenderSession session = RenderSessions.Values.FirstOrDefault(
                candidate => candidate.SuppressedEquipmentSounds.Contains(statusEffect));
            Character character = session?.Character;
            if (character == null) { return true; }
            if (!IsCharacterActive(character) || !HasCapability("statusSound")) { return true; }
            if (FashionEffectPolicy.IsFunctionalEquipmentAlarm(statusEffect))
            {
                session.SuppressedEquipmentSounds.Remove(statusEffect);
                return true;
            }
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
            RenderSession session = RenderSessions.Values.FirstOrDefault(
                candidate => candidate.SuppressedEquipmentComponentSounds.Contains(component));
            Character character = session?.Character;
            if (character == null) { return true; }
            if (!IsCharacterActive(character) || !HasCapability("itemSound")) { return true; }
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
                    character,
                    fashionSound,
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
            RenderSession session,
            List<(ItemComponent Component, ActionType ActionType)> fashionSounds,
            ActionType actionType,
            Character user)
        {
            Character character = session?.Character;
            if (character == null || fashionSounds == null || fashionSounds.Count == 0) { return false; }

            int cursor = session.FashionComponentSoundCursor;
            for (int pass = 0; pass < 2; pass++)
            {
                for (int offset = 0; offset < fashionSounds.Count; offset++)
                {
                    int index = (cursor + offset) % fashionSounds.Count;
                    (ItemComponent Component, ActionType ActionType) fashionSound = fashionSounds[index];
                    if (fashionSound.Component == null) { continue; }
                    if (pass == 0 && fashionSound.ActionType != actionType) { continue; }

                    session.FashionComponentSoundCursor = (index + 1) % fashionSounds.Count;
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

        private static IEnumerable<FashionSpriteDescriptor> EnumerateFashionSpritesForLimb(
            Dictionary<Tuple<WearableType, LimbType>, List<FashionSpriteDescriptor>> spritesBySlot,
            LimbType limbType)
        {
            return spritesBySlot
                .Where(pair =>
                    pair.Value != null &&
                    (pair.Key.Item2 == limbType || pair.Key.Item2 == LimbType.None))
                .SelectMany(pair => pair.Value
                    .Where(descriptor => descriptor?.Sprite != null && SpriteBelongsToLimb(descriptor.Sprite, limbType)))
                .OrderBy(GetFashionLayerSortKey)
                .ThenByDescending(descriptor => descriptor.Sprite?.Sprite?.Depth ?? 0.0f);
        }

        private static void SortWearablesForDraw(List<WearableSprite> wearingItems)
        {
            if (wearingItems == null) { return; }
            List<WearableSprite> sortedWearables = wearingItems
                .OrderBy(GetFashionLayerSortKey)
                .ThenByDescending(wearable => wearable?.Sprite?.Depth ?? 0.0f)
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

        private static int GetFashionLayerSortKey(FashionSpriteDescriptor descriptor)
        {
            if (descriptor == null) { return 0; }
            if (descriptor.AllowedSlots.Contains(InvSlotType.Bag)) { return 2; }
            if (descriptor.AllowedSlots.Contains(InvSlotType.HealthInterface)) { return 3; }
            if (descriptor.AllowedSlots.Contains(InvSlotType.InnerClothes)) { return 4; }
            if (descriptor.AllowedSlots.Contains(InvSlotType.Head) || descriptor.AllowedSlots.Contains(InvSlotType.Headset)) { return 5; }
            if (descriptor.AllowedSlots.Contains(InvSlotType.OuterClothes)) { return 6; }
            return 5;
        }

        private static bool UsesRecessedFashionLayer(FashionSpriteDescriptor descriptor)
        {
            return descriptor != null &&
                   (descriptor.AllowedSlots.Contains(InvSlotType.Bag) ||
                    descriptor.AllowedSlots.Contains(InvSlotType.HealthInterface));
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

        private static bool SlotContains(WearableSprite sprite, InvSlotType slot)
        {
            return sprite?.WearableComponent?.AllowedSlots != null &&
                   sprite.WearableComponent.AllowedSlots.Contains(slot);
        }

        private static bool SpriteBelongsToLimb(WearableSprite sprite, LimbType limbType)
        {
            if (sprite == null) { return false; }
            // The initialized sprite limb is authoritative. An explicit None is a
            // real custom-ragdoll binding; only a legacy unbound None uses a slot anchor.
            if (sprite.Limb != LimbType.None || HasExplicitLimbBinding(sprite))
            {
                return sprite.Limb == limbType;
            }
            return GetFallbackAnchorLimb(sprite) == limbType;
        }

        private static bool HasExplicitLimbBinding(WearableSprite sprite)
        {
            return sprite?.SourceElement?.GetAttribute("limb") != null;
        }

        private static bool IsFashionSpriteCompatibleWithLimb(
            RenderSession session,
            WearableSprite sprite,
            Limb limb)
        {
            if (session == null || sprite == null || limb == null || sprite.Limb != LimbType.None ||
                !session.TryGetDescriptor(sprite, out FashionSpriteDescriptor descriptor) ||
                !string.Equals(descriptor.SourceIdentifier, "sexy_exosuit_plus", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }

            string path = (descriptor.ResolvedSpritePath ?? string.Empty).Replace('\\', '/');
            string name = sprite.SourceElement?.GetAttribute("name")?.Value ?? string.Empty;
            if (path.IndexOf("/3156077899/", StringComparison.OrdinalIgnoreCase) < 0 ||
                !path.EndsWith("/exo_milker2.png", StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(name, "automilker LeftBreast", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }

            return limb.type == LimbType.None && limb.Params?.ID == 17;
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
            if (!RenderSessions.TryGetValue(character, out RenderSession session) || session.EmptySlots.Count == 0)
            {
                return false;
            }

            return original.WearableComponent.AllowedSlots.Any(slot => session.EmptySlots.Contains(slot));
        }

        private static void CaptureFashionHiddenWearableTypes(RenderSession session, WearableSprite sprite)
        {
            if (session == null || sprite?.HideWearablesOfType == null || sprite.HideWearablesOfType.Count == 0) { return; }
            foreach (WearableType hiddenType in sprite.HideWearablesOfType)
            {
                if (!FashionHideableAttachmentTypes.Contains(hiddenType)) { continue; }
                session.HiddenWearableTypes.Add(hiddenType);
            }
        }

        private static bool ShouldHideAttachmentForFashion(Character character, WearableSprite original)
        {
            if (character == null || original == null) { return false; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session) ||
                !AttachmentBits.TryGetValue(original.Type, out int attachmentBit))
            {
                return false;
            }
            if ((session.ForceShowAttachmentMask & attachmentBit) != 0)
            {
                return false;
            }
            if ((session.ForceHideAttachmentMask & attachmentBit) != 0)
            {
                return true;
            }
            return session.HiddenWearableTypes.Contains(original.Type);
        }

        private static string DescribeFashionHiddenTypes(Character character)
        {
            if (character == null ||
                !RenderSessions.TryGetValue(character, out RenderSession session) ||
                session.HiddenWearableTypes.Count == 0)
            {
                return "none";
            }
            return string.Join(",", session.HiddenWearableTypes.Select(type => type.ToString()).OrderBy(name => name));
        }

        private static bool ShouldHideOriginalForSavedSlot(Character character, WearableSprite original)
        {
            if (character == null || original?.WearableComponent?.AllowedSlots == null) { return false; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session) || session.SavedSlots.Count == 0)
            {
                return false;
            }

            return original.WearableComponent.AllowedSlots.Any(slot => session.SavedSlots.Contains(slot));
        }

        private static string DescribeWearableSlots(WearableSprite sprite)
        {
            if (sprite?.WearableComponent?.AllowedSlots == null) { return "none"; }
            return string.Join(",", sprite.WearableComponent.AllowedSlots.Select(slot => slot.ToString()).OrderBy(slot => slot));
        }

        private static string DescribeSavedSlots(Character character)
        {
            return RenderSessions.TryGetValue(character, out RenderSession session)
                ? DescribeSlotSet(session.SavedSlots)
                : "none";
        }

        private static string DescribeEmptySlots(Character character)
        {
            return RenderSessions.TryGetValue(character, out RenderSession session)
                ? DescribeSlotSet(session.EmptySlots)
                : "none";
        }

        private static string DescribeSlotSet(HashSet<InvSlotType> slots)
        {
            if (slots == null || slots.Count == 0)
            {
                return "none";
            }
            return string.Join(",", slots.Select(slot => slot.ToString()).OrderBy(slot => slot));
        }

        private static void ClearMask(WearableSprite sprite)
        {
            if (sprite == null) { return; }
            sprite.HideLimb = false;
            sprite.HideWearablesOfType = new List<WearableType>();
            sprite.ObscureOtherWearables = WearableSprite.ObscuringMode.None;
            sprite.CanBeHiddenByOtherWearables = false;
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
            if (!RenderSessions.TryGetValue(character, out RenderSession session))
            {
                return false;
            }
            foreach (FashionSpriteDescriptor descriptor in EnumerateFashionSpriteCandidates(session.SpritesBySlot, type, limbType))
            {
                WearableSprite candidate = descriptor?.Sprite;
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
            if (!RenderSessions.TryGetValue(character, out RenderSession session))
            {
                return false;
            }
            return EnumerateFashionSpriteCandidates(session.SpritesBySlot, type, limbType)
                .Any(descriptor => descriptor?.Sprite != null && drawnSprites.Contains(descriptor.Sprite));
        }

        private static IEnumerable<FashionSpriteDescriptor> EnumerateFashionSpriteCandidates(
            Dictionary<Tuple<WearableType, LimbType>, List<FashionSpriteDescriptor>> spritesBySlot,
            WearableType type,
            LimbType limbType)
        {
            if (spritesBySlot == null) { yield break; }

            if (spritesBySlot.TryGetValue(Tuple.Create(type, limbType), out List<FashionSpriteDescriptor> exactSprites) && exactSprites != null)
            {
                foreach (FashionSpriteDescriptor descriptor in exactSprites)
                {
                    if (descriptor?.Sprite != null && SpriteBelongsToLimb(descriptor.Sprite, limbType))
                    {
                        yield return descriptor;
                    }
                }
            }

            if (limbType == LimbType.None) { yield break; }
            if (!spritesBySlot.TryGetValue(Tuple.Create(type, LimbType.None), out List<FashionSpriteDescriptor> wildcardSprites) || wildcardSprites == null)
            {
                yield break;
            }
            foreach (FashionSpriteDescriptor descriptor in wildcardSprites)
            {
                if (descriptor?.Sprite != null && SpriteBelongsToLimb(descriptor.Sprite, limbType))
                {
                    yield return descriptor;
                }
            }
        }

        private static string DescribeFashionSprites(Character character)
        {
            if (character == null) { return "character=nil"; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session) ||
                session.SpritesBySlot.Count == 0)
            {
                return "none";
            }
            return string.Join(";",
                session.SpritesBySlot
                    .OrderBy(pair => pair.Key.Item2.ToString())
                    .ThenBy(pair => pair.Key.Item1.ToString())
                    .Select(pair => pair.Key.Item2 + "/" + pair.Key.Item1 + "=" + (pair.Value?.Count ?? 0)));
        }

        private static string DescribeFashionSpriteLayers(Character character)
        {
            if (character == null) { return "character=nil"; }
            if (!RenderSessions.TryGetValue(character, out RenderSession session) ||
                session.SpritesBySlot.Count == 0)
            {
                return "none";
            }
            return string.Join(";",
                session.SpritesBySlot.Values
                    .Where(spriteList => spriteList != null)
                    .SelectMany(spriteList => spriteList.Where(descriptor => descriptor?.Sprite != null).Select(descriptor => GetFashionLayerName(descriptor.Sprite)))
                    .GroupBy(layer => layer)
                    .OrderBy(group => group.Key)
                    .Select(group => group.Key + "=" + group.Count()));
        }

        private static string DescribeFashionSpriteSources(Character character)
        {
            if (character == null ||
                !RenderSessions.TryGetValue(character, out RenderSession session) ||
                session.SpriteCount == 0)
            {
                return "none";
            }
            return string.Join(";",
                session.Descriptors
                    .Where(descriptor => descriptor != null)
                    .OrderBy(descriptor => descriptor.SourceIdentifier)
                    .ThenBy(descriptor => descriptor.ResolvedSpritePath)
                    .Select(descriptor =>
                        descriptor.SourceIdentifier +
                        "@" +
                        descriptor.SourceContentPackage +
                        "=" +
                        descriptor.ResolvedSpritePath));
        }

        internal sealed class LimbRenderTransaction
        {
            private readonly Limb limb;
            private readonly Dictionary<WearableSprite, SpriteMaskState> originalMasks =
                new Dictionary<WearableSprite, SpriteMaskState>();
            private List<WearableSprite> originalOrder;
            private RenderSession session;
            private bool cleaned;
            private int storedFashionDrawDepth;

            public LimbRenderTransaction(Limb limb)
            {
                this.limb = limb;
            }

            public bool IsOwner { get; private set; }

            public bool IsDrawingStoredFashion => storedFashionDrawDepth > 0;

            public HashSet<WearableSprite> DrawnSprites { get; } = new HashSet<WearableSprite>();

            public List<WearableSprite> InjectedSprites { get; } = new List<WearableSprite>();

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
                if (wearingItems == null) { return; }

                originalOrder = new List<WearableSprite>(wearingItems);
                foreach (WearableSprite equipmentSprite in originalOrder
                             .Where(sprite => IsEquipmentSprite(sprite) && !session.TryGetDescriptor(sprite, out _)))
                {
                    originalMasks[equipmentSprite] = new SpriteMaskState(equipmentSprite);
                    ClearMask(equipmentSprite);
                }

                List<FashionSpriteDescriptor> descriptors = EnumerateFashionSpritesForLimb(session.SpritesBySlot, limb.type)
                    .Where(descriptor => !wearingItems.Contains(descriptor.Sprite))
                    .Distinct()
                    .ToList();
                foreach (FashionSpriteDescriptor descriptor in descriptors)
                {
                    if (!descriptor.IsValid(out string error))
                    {
                        throw new InvalidOperationException("invalid fashion descriptor: " + error);
                    }
                }
                foreach (FashionSpriteDescriptor descriptor in descriptors)
                {
                    wearingItems.Add(descriptor.Sprite);
                    InjectedSprites.Add(descriptor.Sprite);
                }
                SortWearablesForDraw(wearingItems);
                lastInjectedSpriteCount = InjectedSprites.Count;
            }

            public void Cleanup()
            {
                if (cleaned) { return; }
                cleaned = true;
                List<Exception> cleanupErrors = new List<Exception>();
                try
                {
                    List<WearableSprite> wearingItems = limb?.WearingItems;
                    if (IsOwner && wearingItems != null)
                    {
                        wearingItems.Clear();
                        if (originalOrder != null)
                        {
                            wearingItems.AddRange(originalOrder);
                        }
                    }
                }
                catch (Exception ex)
                {
                    cleanupErrors.Add(new InvalidOperationException("Failed to restore Limb.WearingItems snapshot.", ex));
                }

                foreach (KeyValuePair<WearableSprite, SpriteMaskState> pair in originalMasks)
                {
                    try
                    {
                        pair.Value.Restore(pair.Key);
                    }
                    catch (Exception ex)
                    {
                        cleanupErrors.Add(new InvalidOperationException("Failed to restore wearable mask snapshot.", ex));
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
                        cleanupErrors.Add(new InvalidOperationException("Failed to release render transaction ownership.", ex));
                    }
                }

                originalMasks.Clear();
                InjectedSprites.Clear();
                DrawnSprites.Clear();
                storedFashionDrawDepth = 0;
                IsOwner = false;

                if (cleanupErrors.Count == 1) { throw cleanupErrors[0]; }
                if (cleanupErrors.Count > 1)
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
        private static void Prefix(Limb __instance, out VisualOverride.LimbRenderTransaction __state)
        {
            __state = VisualOverride.BeginLimbDraw(__instance);
        }

        private static void Postfix(
            Limb __instance,
            SpriteBatch spriteBatch,
            Camera cam,
            Color? overrideColor,
            bool disableDeformations,
            VisualOverride.LimbRenderTransaction __state)
        {
            VisualOverride.DrawMissingFashionSprites(__instance, __state, spriteBatch, overrideColor);
        }

        private static Exception Finalizer(
            Limb __instance,
            Exception __exception,
            VisualOverride.LimbRenderTransaction __state)
        {
            return VisualOverride.EndLimbDraw(__instance, __state, __exception);
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
