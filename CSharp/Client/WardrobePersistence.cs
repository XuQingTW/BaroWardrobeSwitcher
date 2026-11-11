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
    public static partial class WardrobePersistence
    {
        public const string Version = "0.5.10";
        // ClientLook.json 格式版本，需與 Lua Core.PERSISTENCE_VERSION 及遷移程式對應。
        private const int PersistenceVersion = 5;
        private const string ModFolderName = "BaroWardrobeSwitcher";
        private const string ClientLookFileName = "ClientLook.json";
        private const string VisibilityAuto = "auto";
        private const string VisibilityHide = "hide";
        private const string VisibilityShow = "show";
        // 與 Lua Core.SLOT_KEYS 使用相同名稱；新增欄位須同步解析、驗證與渲染支援。
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
                ClientLookDocument document = ParseClientLook(ParseParts(encodedLook));
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
                        Slots = CreateEmptySlots(),
                        Colors = CreateEmptyColors()
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
            if (version == 4)
            {
                LegacyClientLookV4Document legacy =
                    JsonSerializer.Deserialize<LegacyClientLookV4Document>(json, JsonOptions);
                ClientLookDocument migratedDocument = new ClientLookDocument
                {
                    Version = PersistenceVersion,
                    Captured = legacy.Captured,
                    UseFashionMovementAnimations = legacy.UseFashionMovementAnimations,
                    UseFashionFootstepSounds = false,
                    AttachmentVisibility = legacy.AttachmentVisibility,
                    Slots = legacy.Slots,
                    Colors = legacy.Colors
                };
                ValidateDocument(migratedDocument);
                migratedFromVersion = 4;
                return migratedDocument;
            }
            if (version == 3)
            {
                LegacyClientLookV3Document legacy =
                    JsonSerializer.Deserialize<LegacyClientLookV3Document>(json, JsonOptions);
                ClientLookDocument migratedDocument = new ClientLookDocument
                {
                    Version = PersistenceVersion,
                    Captured = legacy.Captured,
                    AttachmentVisibility = legacy.AttachmentVisibility,
                    Slots = legacy.Slots,
                    Colors = CreateEmptyColors()
                };
                ValidateDocument(migratedDocument);
                migratedFromVersion = 3;
                return migratedDocument;
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
                    Slots = legacy.Slots,
                    Colors = CreateEmptyColors()
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

        // 先寫同目錄臨時檔並 flush，再替換正式檔／保留備份，避免直接截斷原存檔。
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

        private static ClientLookDocument ParseClientLook(Dictionary<string, string> parts)
        {
            ClientLookDocument document = new ClientLookDocument
            {
                Version = PersistenceVersion,
                Captured = GetBoolean(parts, "captured"),
                UseFashionMovementAnimations =
                    GetBooleanOrDefault(parts, "fashionMovement", defaultValue: true),
                UseFashionFootstepSounds =
                    GetBooleanOrDefault(parts, "fashionFootstep", defaultValue: false),
                AttachmentVisibility = ParseAttachmentVisibility(parts),
                Slots = ParseSlots(parts),
                Colors = ParseColors(parts)
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
                "fashionMovement=" +
                    document.UseFashionMovementAnimations.ToString().ToLowerInvariant(),
                "fashionFootstep=" +
                    document.UseFashionFootstepSounds.ToString().ToLowerInvariant(),
                "visibilityHair=" + document.AttachmentVisibility.Hair,
                "visibilityBeard=" + document.AttachmentVisibility.Beard,
                "visibilityMoustache=" + document.AttachmentVisibility.Moustache,
                "visibilityFaceAttachment=" + document.AttachmentVisibility.FaceAttachment
            };
            AppendEncodedSlots(parts, document.Slots);
            AppendEncodedColors(parts, document.Colors);
            return string.Join("|", parts);
        }

        private static void AppendEncodedSlots(List<string> parts, Dictionary<string, string> slots)
        {
            if (parts == null || slots == null) { return; }
            foreach (string slotKey in SlotKeys)
            {
                if (!slots.TryGetValue(slotKey, out string identifier) || string.IsNullOrWhiteSpace(identifier)) { continue; }
                // Display names and runtime item ids are intentionally not persisted in
                // schema v5. The Lua facade still receives the legacy comma separator.
                parts.Add(slotKey + "=" + Escape(identifier) + ",");
            }
        }

        private static void AppendEncodedColors(
            List<string> parts,
            Dictionary<string, uint?> colors)
        {
            if (parts == null || colors == null) { return; }
            foreach (string slotKey in SlotKeys)
            {
                if (colors.TryGetValue(slotKey, out uint? color) && color.HasValue)
                {
                    parts.Add(slotKey + "Color=" + color.Value);
                }
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

        private static Dictionary<string, uint?> ParseColors(Dictionary<string, string> parts)
        {
            Dictionary<string, uint?> colors = CreateEmptyColors();
            foreach (string slotKey in SlotKeys)
            {
                string field = slotKey + "Color";
                if (!parts.TryGetValue(field, out string encodedValue)) { continue; }
                if (!uint.TryParse(encodedValue, out uint color))
                {
                    throw new InvalidDataException("Encoded wardrobe color is invalid for slot " + slotKey + ".");
                }
                colors[slotKey] = color;
            }
            return colors;
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

        private static bool GetBooleanOrDefault(
            Dictionary<string, string> parts,
            string key,
            bool defaultValue)
        {
            if (parts == null || !parts.TryGetValue(key, out string value))
            {
                return defaultValue;
            }
            if (bool.TryParse(value, out bool parsed)) { return parsed; }
            throw new InvalidDataException("Encoded wardrobe " + key + " boolean is invalid.");
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
                Slots = slots,
                Colors = CreateEmptyColors()
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

        private static Dictionary<string, uint?> CreateEmptyColors()
        {
            Dictionary<string, uint?> colors = new Dictionary<string, uint?>(StringComparer.Ordinal);
            foreach (string key in SlotKeys)
            {
                colors[key] = null;
            }
            return colors;
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
                    throw new InvalidDataException("Unknown wardrobe slot: " + key + ".");
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
            document.Colors ??= CreateEmptyColors();
            foreach (string key in document.Colors.Keys.ToList())
            {
                if (!SlotKeys.Contains(key, StringComparer.Ordinal))
                {
                    throw new InvalidDataException("Unknown wardrobe color slot: " + key + ".");
                }
                if (document.Colors[key].HasValue &&
                    string.IsNullOrWhiteSpace(document.Slots[key]))
                {
                    throw new InvalidDataException("Wardrobe color has no item for slot " + key + ".");
                }
            }
            foreach (string key in SlotKeys)
            {
                if (!document.Colors.ContainsKey(key)) { document.Colors[key] = null; }
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
            [JsonPropertyName("useFashionMovementAnimations")]
            public bool UseFashionMovementAnimations { get; set; } = true;
            [JsonPropertyName("useFashionFootstepSounds")]
            public bool UseFashionFootstepSounds { get; set; }
            [JsonRequired]
            [JsonPropertyName("attachmentVisibility")]
            public AttachmentVisibilityDocument AttachmentVisibility { get; set; }
            [JsonRequired]
            [JsonPropertyName("slots")]
            public Dictionary<string, string> Slots { get; set; }
            [JsonRequired]
            [JsonPropertyName("colors")]
            public Dictionary<string, uint?> Colors { get; set; }

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

        private sealed class LegacyClientLookV4Document
        {
            [JsonRequired]
            [JsonPropertyName("schemaVersion")]
            public int Version { get; set; }
            [JsonRequired]
            [JsonPropertyName("captured")]
            public bool Captured { get; set; }
            [JsonPropertyName("useFashionMovementAnimations")]
            public bool UseFashionMovementAnimations { get; set; } = true;
            [JsonRequired]
            [JsonPropertyName("attachmentVisibility")]
            public AttachmentVisibilityDocument AttachmentVisibility { get; set; }
            [JsonRequired]
            [JsonPropertyName("slots")]
            public Dictionary<string, string> Slots { get; set; }
            [JsonRequired]
            [JsonPropertyName("colors")]
            public Dictionary<string, uint?> Colors { get; set; }
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

        private sealed class LegacyClientLookV3Document
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
    }

}
