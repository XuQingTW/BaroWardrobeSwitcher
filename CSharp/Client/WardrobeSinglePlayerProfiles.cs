using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace BaroWardrobeSwitcher
{
    /// <summary>
    /// Stores one look per campaign/character identity. Raw save paths and stable
    /// character keys are hashed; display names are descriptive and never identity.
    /// </summary>
    public static partial class WardrobePersistence
    {
        private const int SinglePlayerProfilesVersion = 2;
        private const string SinglePlayerProfilesFileName = "SinglePlayerProfiles.json";
        private const int MaximumSinglePlayerProfiles = 512;
        private const int MaximumDisplayNameBytes = 512;

        public static string GetSinglePlayerProfilesPath()
        {
            return Path.Combine(GetStorageDirectory(), SinglePlayerProfilesFileName);
        }

        public static bool GetSinglePlayerTransferEnabled()
        {
            ClearLastError();
            try
            {
                return ReadSinglePlayerProfiles().TransferToUnconfiguredCharacter;
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to load single-player wardrobe settings", ex);
                return false;
            }
        }

        public static bool SetSinglePlayerTransferEnabled(bool enabled)
        {
            ClearLastError();
            try
            {
                SinglePlayerProfilesDocument document = ReadSinglePlayerProfiles();
                document.TransferToUnconfiguredCharacter = enabled;
                WriteSinglePlayerProfiles(document);
                return true;
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to save single-player wardrobe settings", ex);
                return false;
            }
        }

        public static string LoadSinglePlayerProfile(string campaignKey, string characterKey)
        {
            ClearLastError();
            try
            {
                string campaignHash = HashRequiredKey(campaignKey, nameof(campaignKey));
                string characterHash = HashRequiredKey(characterKey, nameof(characterKey));
                SinglePlayerProfile profile = ReadSinglePlayerProfiles().Profiles.FirstOrDefault(
                    candidate =>
                        string.Equals(candidate.CampaignHash, campaignHash, StringComparison.Ordinal) &&
                        string.Equals(candidate.CharacterHash, characterHash, StringComparison.Ordinal));
                return profile == null ? string.Empty : EncodeSinglePlayerProfile(profile);
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to load single-player wardrobe profile", ex);
                return string.Empty;
            }
        }

        public static bool SaveSinglePlayerProfile(
            string campaignKey,
            string characterKey,
            string displayName,
            string encodedLook)
        {
            ClearLastError();
            try
            {
                string campaignHash = HashRequiredKey(campaignKey, nameof(campaignKey));
                string characterHash = HashRequiredKey(characterKey, nameof(characterKey));
                string safeDisplayName = ValidateDisplayName(displayName);
                Dictionary<string, string> parts = ParseParts(encodedLook);
                ClientLookDocument look = ParseClientLook(encodedLook);
                ValidateDocument(look);
                if (!HasAnySlot(look.Slots) && !look.Captured)
                {
                    return DeleteSinglePlayerProfile(campaignKey, characterKey);
                }

                SinglePlayerProfilesDocument document = ReadSinglePlayerProfiles();
                SinglePlayerProfile existing = document.Profiles.FirstOrDefault(
                    candidate =>
                        string.Equals(candidate.CampaignHash, campaignHash, StringComparison.Ordinal) &&
                        string.Equals(candidate.CharacterHash, characterHash, StringComparison.Ordinal));
                if (existing == null)
                {
                    if (document.Profiles.Count >= MaximumSinglePlayerProfiles)
                    {
                        throw new InvalidDataException(
                            "Single-player wardrobe profile limit has been reached.");
                    }
                    existing = new SinglePlayerProfile
                    {
                        CampaignHash = campaignHash,
                        CharacterHash = characterHash
                    };
                    document.Profiles.Add(existing);
                }

                existing.DisplayName = safeDisplayName;
                existing.AutoApply = GetBoolean(parts, "auto") || GetBoolean(parts, "active");
                existing.Captured = look.Captured;
                existing.AttachmentVisibility =
                    CopyAttachmentVisibility(look.AttachmentVisibility);
                existing.Slots = CopySlots(look.Slots);
                WriteSinglePlayerProfiles(document);
                return true;
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to save single-player wardrobe profile", ex);
                return false;
            }
        }

        public static bool DeleteSinglePlayerProfile(string campaignKey, string characterKey)
        {
            ClearLastError();
            try
            {
                string campaignHash = HashRequiredKey(campaignKey, nameof(campaignKey));
                string characterHash = HashRequiredKey(characterKey, nameof(characterKey));
                SinglePlayerProfilesDocument document = ReadSinglePlayerProfiles();
                document.Profiles.RemoveAll(
                    candidate =>
                        string.Equals(candidate.CampaignHash, campaignHash, StringComparison.Ordinal) &&
                        string.Equals(candidate.CharacterHash, characterHash, StringComparison.Ordinal));
                WriteSinglePlayerProfiles(document);
                return true;
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to delete single-player wardrobe profile", ex);
                return false;
            }
        }

        // Import is recorded per campaign even when no legacy look exists. Without
        // that tombstone, every profile load would repeatedly probe the old file.
        public static bool TryImportLegacyClientLook(
            string campaignKey,
            string characterKey,
            string displayName)
        {
            ClearLastError();
            try
            {
                string campaignHash = HashRequiredKey(campaignKey, nameof(campaignKey));
                string characterHash = HashRequiredKey(characterKey, nameof(characterKey));
                string safeDisplayName = ValidateDisplayName(displayName);
                SinglePlayerProfilesDocument profiles = ReadSinglePlayerProfiles();
                if (profiles.ImportedLegacyCampaigns.Contains(campaignHash, StringComparer.Ordinal))
                {
                    return false;
                }

                profiles.ImportedLegacyCampaigns.Add(campaignHash);
                bool profileExists = profiles.Profiles.Any(
                    candidate =>
                        string.Equals(candidate.CampaignHash, campaignHash, StringComparison.Ordinal) &&
                        string.Equals(candidate.CharacterHash, characterHash, StringComparison.Ordinal));
                bool imported = false;
                if (!profileExists)
                {
                    ClientLookDocument legacyLook = ReadLegacyClientLookForImport();
                    if (legacyLook != null && (legacyLook.Captured || HasAnySlot(legacyLook.Slots)))
                    {
                        if (profiles.Profiles.Count >= MaximumSinglePlayerProfiles)
                        {
                            throw new InvalidDataException(
                                "Single-player wardrobe profile limit has been reached.");
                        }
                        profiles.Profiles.Add(new SinglePlayerProfile
                        {
                            CampaignHash = campaignHash,
                            CharacterHash = characterHash,
                            DisplayName = safeDisplayName,
                            // A captured legacy look is not consent to replace new-campaign equipment.
                            AutoApply = false,
                            Captured = legacyLook.Captured,
                            AttachmentVisibility =
                                CopyAttachmentVisibility(legacyLook.AttachmentVisibility),
                            Slots = CopySlots(legacyLook.Slots)
                        });
                        imported = true;
                    }
                }

                WriteSinglePlayerProfiles(profiles);
                return imported;
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to import legacy single-player wardrobe look", ex);
                return false;
            }
        }

        private static ClientLookDocument ReadLegacyClientLookForImport()
        {
            string path = GetClientLookPath();
            if (!File.Exists(path)) { return null; }
            try
            {
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
                return document;
            }
            catch (JsonException ex)
            {
                QuarantineCorruptFile(path, ex);
                return null;
            }
            catch (InvalidDataException ex)
            {
                QuarantineCorruptFile(path, ex);
                return null;
            }
        }

        // Only canonical documents enter memory. Older supported schemas migrate
        // once; malformed or unexpected shapes are quarantined and fail closed.
        private static SinglePlayerProfilesDocument ReadSinglePlayerProfiles()
        {
            string path = GetSinglePlayerProfilesPath();
            if (!File.Exists(path)) { return CreateEmptySinglePlayerProfiles(); }
            try
            {
                string json = File.ReadAllText(path, Encoding.UTF8);
                using JsonDocument parsed = JsonDocument.Parse(json);
                int version = ReadSchemaVersion(parsed.RootElement);
                if (version == 1)
                {
                    if (!IsCanonicalSinglePlayerProfilesV1(parsed.RootElement))
                    {
                        throw new InvalidDataException(
                            "Single-player wardrobe profile schema v1 is not canonical.");
                    }
                    SinglePlayerProfilesDocument migrated = MigrateSinglePlayerProfilesV1(json);
                    ValidateSinglePlayerProfiles(migrated);
                    File.Copy(path, path + ".v1.bak", overwrite: true);
                    WriteSinglePlayerProfiles(migrated);
                    LogPersistenceInfo(
                        "Migrated single-player wardrobe profiles from schema v1 to schema v2.");
                    return migrated;
                }
                if (version != SinglePlayerProfilesVersion ||
                    !IsCanonicalSinglePlayerProfilesDocument(parsed.RootElement))
                {
                    throw new InvalidDataException(
                        "Single-player wardrobe profile document is not canonical.");
                }
                SinglePlayerProfilesDocument document =
                    JsonSerializer.Deserialize<SinglePlayerProfilesDocument>(json, JsonOptions);
                ValidateSinglePlayerProfiles(document);
                return document;
            }
            catch (JsonException ex)
            {
                QuarantineCorruptFile(path, ex);
                return CreateEmptySinglePlayerProfiles();
            }
            catch (InvalidDataException ex)
            {
                QuarantineCorruptFile(path, ex);
                return CreateEmptySinglePlayerProfiles();
            }
        }

        // Stable ordering makes files deterministic and keeps equivalent updates
        // from producing noisy rewrites.
        private static void WriteSinglePlayerProfiles(SinglePlayerProfilesDocument document)
        {
            ValidateSinglePlayerProfiles(document);
            document.ImportedLegacyCampaigns = document.ImportedLegacyCampaigns
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToList();
            document.Profiles = document.Profiles
                .OrderBy(profile => profile.CampaignHash, StringComparer.Ordinal)
                .ThenBy(profile => profile.CharacterHash, StringComparer.Ordinal)
                .ToList();
            WriteJson(GetSinglePlayerProfilesPath(), document);
        }

        private static SinglePlayerProfilesDocument MigrateSinglePlayerProfilesV1(string json)
        {
            LegacySinglePlayerProfilesDocument legacy =
                JsonSerializer.Deserialize<LegacySinglePlayerProfilesDocument>(json, JsonOptions);
            if (legacy == null || legacy.Version != 1)
            {
                throw new InvalidDataException(
                    "Single-player wardrobe profile schema v1 is invalid.");
            }

            return new SinglePlayerProfilesDocument
            {
                Version = SinglePlayerProfilesVersion,
                TransferToUnconfiguredCharacter = legacy.TransferToUnconfiguredCharacter,
                ImportedLegacyCampaigns =
                    legacy.ImportedLegacyCampaigns ?? new List<string>(),
                Profiles = (legacy.Profiles ?? new List<LegacySinglePlayerProfile>())
                    .Select(profile => new SinglePlayerProfile
                    {
                        CampaignHash = profile.CampaignHash,
                        CharacterHash = profile.CharacterHash,
                        DisplayName = profile.DisplayName,
                        AutoApply = profile.AutoApply,
                        Captured = profile.Captured,
                        AttachmentVisibility =
                            CreateAttachmentVisibility(profile.HideHair),
                        Slots = CopySlots(profile.Slots)
                    })
                    .ToList()
            };
        }

        private static SinglePlayerProfilesDocument CreateEmptySinglePlayerProfiles()
        {
            return new SinglePlayerProfilesDocument
            {
                Version = SinglePlayerProfilesVersion,
                TransferToUnconfiguredCharacter = false,
                ImportedLegacyCampaigns = new List<string>(),
                Profiles = new List<SinglePlayerProfile>()
            };
        }

        private static void ValidateSinglePlayerProfiles(SinglePlayerProfilesDocument document)
        {
            if (document == null ||
                document.Version != SinglePlayerProfilesVersion ||
                document.ImportedLegacyCampaigns == null ||
                document.Profiles == null)
            {
                throw new InvalidDataException("Single-player wardrobe profile schema is invalid.");
            }
            if (document.Profiles.Count > MaximumSinglePlayerProfiles)
            {
                throw new InvalidDataException("Single-player wardrobe profile limit has been exceeded.");
            }

            var imported = new HashSet<string>(StringComparer.Ordinal);
            foreach (string campaignHash in document.ImportedLegacyCampaigns)
            {
                ValidateHash(campaignHash, "imported campaign");
                if (!imported.Add(campaignHash))
                {
                    throw new InvalidDataException(
                        "Single-player wardrobe profile document contains a duplicate imported campaign.");
                }
            }

            var profileKeys = new HashSet<string>(StringComparer.Ordinal);
            foreach (SinglePlayerProfile profile in document.Profiles)
            {
                if (profile == null)
                {
                    throw new InvalidDataException(
                        "Single-player wardrobe profile document contains an empty profile.");
                }
                ValidateHash(profile.CampaignHash, "profile campaign");
                ValidateHash(profile.CharacterHash, "profile character");
                profile.DisplayName = ValidateDisplayName(profile.DisplayName);
                string key = profile.CampaignHash + ":" + profile.CharacterHash;
                if (!profileKeys.Add(key))
                {
                    throw new InvalidDataException(
                        "Single-player wardrobe profile document contains a duplicate profile.");
                }

                var look = new ClientLookDocument
                {
                    Version = PersistenceVersion,
                    Captured = profile.Captured,
                    AttachmentVisibility =
                        CopyAttachmentVisibility(profile.AttachmentVisibility),
                    Slots = profile.Slots
                };
                ValidateDocument(look);
                if (!look.Captured && !HasAnySlot(look.Slots))
                {
                    throw new InvalidDataException(
                        "Single-player wardrobe profile has no captured look.");
                }
                profile.AttachmentVisibility =
                    CopyAttachmentVisibility(look.AttachmentVisibility);
                profile.Slots = CopySlots(look.Slots);
            }
        }

        private static bool IsCanonicalSinglePlayerProfilesDocument(JsonElement root)
        {
            if (root.ValueKind != JsonValueKind.Object) { return false; }
            var expected = new HashSet<string>(StringComparer.Ordinal)
            {
                "schemaVersion",
                "transferToUnconfiguredCharacter",
                "importedLegacyCampaigns",
                "profiles"
            };
            foreach (JsonProperty property in root.EnumerateObject())
            {
                if (!expected.Remove(property.Name)) { return false; }
            }
            if (expected.Count != 0 ||
                !root.TryGetProperty("schemaVersion", out JsonElement version) ||
                version.ValueKind != JsonValueKind.Number ||
                !version.TryGetInt32(out int schemaVersion) ||
                schemaVersion != SinglePlayerProfilesVersion ||
                !root.TryGetProperty(
                    "transferToUnconfiguredCharacter",
                    out JsonElement transfer) ||
                !IsBooleanKind(transfer) ||
                !root.TryGetProperty("importedLegacyCampaigns", out JsonElement imported) ||
                imported.ValueKind != JsonValueKind.Array ||
                imported.EnumerateArray().Any(value => value.ValueKind != JsonValueKind.String) ||
                !root.TryGetProperty("profiles", out JsonElement profiles) ||
                profiles.ValueKind != JsonValueKind.Array)
            {
                return false;
            }

            foreach (JsonElement profile in profiles.EnumerateArray())
            {
                if (!IsCanonicalSinglePlayerProfile(profile)) { return false; }
            }
            return true;
        }

        private static bool IsCanonicalSinglePlayerProfilesV1(JsonElement root)
        {
            if (root.ValueKind != JsonValueKind.Object) { return false; }
            var expected = new HashSet<string>(StringComparer.Ordinal)
            {
                "schemaVersion",
                "transferToUnconfiguredCharacter",
                "importedLegacyCampaigns",
                "profiles"
            };
            foreach (JsonProperty property in root.EnumerateObject())
            {
                if (!expected.Remove(property.Name)) { return false; }
            }
            if (expected.Count != 0 ||
                !root.TryGetProperty("schemaVersion", out JsonElement version) ||
                version.ValueKind != JsonValueKind.Number ||
                !version.TryGetInt32(out int schemaVersion) ||
                schemaVersion != 1 ||
                !root.TryGetProperty(
                    "transferToUnconfiguredCharacter",
                    out JsonElement transfer) ||
                !IsBooleanKind(transfer) ||
                !root.TryGetProperty("importedLegacyCampaigns", out JsonElement imported) ||
                imported.ValueKind != JsonValueKind.Array ||
                imported.EnumerateArray().Any(value => value.ValueKind != JsonValueKind.String) ||
                !root.TryGetProperty("profiles", out JsonElement profiles) ||
                profiles.ValueKind != JsonValueKind.Array)
            {
                return false;
            }

            foreach (JsonElement profile in profiles.EnumerateArray())
            {
                if (!IsCanonicalSinglePlayerProfileV1(profile)) { return false; }
            }
            return true;
        }

        private static bool IsCanonicalSinglePlayerProfileV1(JsonElement profile)
        {
            if (profile.ValueKind != JsonValueKind.Object) { return false; }
            var expected = new HashSet<string>(StringComparer.Ordinal)
            {
                "campaignHash",
                "characterHash",
                "displayName",
                "autoApply",
                "captured",
                "hideHair",
                "slots"
            };
            foreach (JsonProperty property in profile.EnumerateObject())
            {
                if (!expected.Remove(property.Name)) { return false; }
            }
            if (expected.Count != 0 ||
                !profile.TryGetProperty("campaignHash", out JsonElement campaignHash) ||
                campaignHash.ValueKind != JsonValueKind.String ||
                !profile.TryGetProperty("characterHash", out JsonElement characterHash) ||
                characterHash.ValueKind != JsonValueKind.String ||
                !profile.TryGetProperty("displayName", out JsonElement displayName) ||
                displayName.ValueKind != JsonValueKind.String ||
                !profile.TryGetProperty("autoApply", out JsonElement autoApply) ||
                !IsBooleanKind(autoApply) ||
                !profile.TryGetProperty("captured", out JsonElement captured) ||
                !IsBooleanKind(captured) ||
                !profile.TryGetProperty("hideHair", out JsonElement hideHair) ||
                !IsBooleanKind(hideHair) ||
                !profile.TryGetProperty("slots", out JsonElement slots) ||
                slots.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            var expectedSlots = new HashSet<string>(SlotKeys, StringComparer.Ordinal);
            foreach (JsonProperty slot in slots.EnumerateObject())
            {
                if (!expectedSlots.Remove(slot.Name) ||
                    slot.Value.ValueKind != JsonValueKind.String &&
                    slot.Value.ValueKind != JsonValueKind.Null)
                {
                    return false;
                }
            }
            return expectedSlots.Count == 0;
        }

        private static bool IsCanonicalSinglePlayerProfile(JsonElement profile)
        {
            if (profile.ValueKind != JsonValueKind.Object) { return false; }
            var expected = new HashSet<string>(StringComparer.Ordinal)
            {
                "campaignHash",
                "characterHash",
                "displayName",
                "autoApply",
                "captured",
                "attachmentVisibility",
                "slots"
            };
            foreach (JsonProperty property in profile.EnumerateObject())
            {
                if (!expected.Remove(property.Name)) { return false; }
            }
            if (expected.Count != 0 ||
                !profile.TryGetProperty("campaignHash", out JsonElement campaignHash) ||
                campaignHash.ValueKind != JsonValueKind.String ||
                !profile.TryGetProperty("characterHash", out JsonElement characterHash) ||
                characterHash.ValueKind != JsonValueKind.String ||
                !profile.TryGetProperty("displayName", out JsonElement displayName) ||
                displayName.ValueKind != JsonValueKind.String ||
                !profile.TryGetProperty("autoApply", out JsonElement autoApply) ||
                !IsBooleanKind(autoApply) ||
                !profile.TryGetProperty("captured", out JsonElement captured) ||
                !IsBooleanKind(captured) ||
                !profile.TryGetProperty(
                    "attachmentVisibility",
                    out JsonElement attachmentVisibility) ||
                !IsCanonicalAttachmentVisibility(attachmentVisibility) ||
                !profile.TryGetProperty("slots", out JsonElement slots) ||
                slots.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            var expectedSlots = new HashSet<string>(SlotKeys, StringComparer.Ordinal);
            foreach (JsonProperty slot in slots.EnumerateObject())
            {
                if (!expectedSlots.Remove(slot.Name) ||
                    slot.Value.ValueKind != JsonValueKind.String &&
                    slot.Value.ValueKind != JsonValueKind.Null)
                {
                    return false;
                }
            }
            return expectedSlots.Count == 0;
        }

        private static string EncodeSinglePlayerProfile(SinglePlayerProfile profile)
        {
            var parts = new List<string>
            {
                "captured=" + profile.Captured.ToString().ToLowerInvariant(),
                "active=false",
                "auto=" + profile.AutoApply.ToString().ToLowerInvariant(),
                "hidehair=" +
                    LegacyHideHair(profile.AttachmentVisibility).ToString().ToLowerInvariant(),
                "visibilityHair=" + profile.AttachmentVisibility.Hair,
                "visibilityBeard=" + profile.AttachmentVisibility.Beard,
                "visibilityMoustache=" + profile.AttachmentVisibility.Moustache,
                "visibilityFaceAttachment=" + profile.AttachmentVisibility.FaceAttachment
            };
            AppendEncodedSlots(parts, profile.Slots);
            return string.Join("|", parts);
        }

        private static Dictionary<string, string> CopySlots(Dictionary<string, string> source)
        {
            Dictionary<string, string> copy = CreateEmptySlots();
            if (source == null) { return copy; }
            foreach (string key in SlotKeys)
            {
                if (source.TryGetValue(key, out string value))
                {
                    copy[key] = value;
                }
            }
            return copy;
        }

        // Hashing keeps machine-specific campaign paths and composite character
        // fingerprints out of the persisted JSON while preserving exact matching.
        private static string HashRequiredKey(string value, string field)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                throw new InvalidDataException(field + " must not be empty.");
            }
            return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)))
                .ToLowerInvariant();
        }

        private static void ValidateHash(string value, string field)
        {
            if (value == null ||
                value.Length != 64 ||
                value.Any(character =>
                    !((character >= '0' && character <= '9') ||
                      (character >= 'a' && character <= 'f'))))
            {
                throw new InvalidDataException(field + " hash is invalid.");
            }
        }

        private static string ValidateDisplayName(string value)
        {
            string displayName = value ?? string.Empty;
            if (Encoding.UTF8.GetByteCount(displayName) > MaximumDisplayNameBytes)
            {
                throw new InvalidDataException(
                    "Single-player wardrobe profile display name is too long.");
            }
            return displayName;
        }

        private sealed class SinglePlayerProfilesDocument
        {
            [JsonPropertyName("schemaVersion")]
            public int Version { get; set; }

            [JsonPropertyName("transferToUnconfiguredCharacter")]
            public bool TransferToUnconfiguredCharacter { get; set; }

            [JsonPropertyName("importedLegacyCampaigns")]
            public List<string> ImportedLegacyCampaigns { get; set; }

            [JsonPropertyName("profiles")]
            public List<SinglePlayerProfile> Profiles { get; set; }
        }

        private sealed class SinglePlayerProfile
        {
            [JsonPropertyName("campaignHash")]
            public string CampaignHash { get; set; }

            [JsonPropertyName("characterHash")]
            public string CharacterHash { get; set; }

            [JsonPropertyName("displayName")]
            public string DisplayName { get; set; }

            [JsonPropertyName("autoApply")]
            public bool AutoApply { get; set; }

            [JsonPropertyName("captured")]
            public bool Captured { get; set; }

            [JsonPropertyName("attachmentVisibility")]
            public AttachmentVisibilityDocument AttachmentVisibility { get; set; }

            [JsonPropertyName("slots")]
            public Dictionary<string, string> Slots { get; set; }
        }

        private sealed class LegacySinglePlayerProfilesDocument
        {
            [JsonPropertyName("schemaVersion")]
            public int Version { get; set; }

            [JsonPropertyName("transferToUnconfiguredCharacter")]
            public bool TransferToUnconfiguredCharacter { get; set; }

            [JsonPropertyName("importedLegacyCampaigns")]
            public List<string> ImportedLegacyCampaigns { get; set; }

            [JsonPropertyName("profiles")]
            public List<LegacySinglePlayerProfile> Profiles { get; set; }
        }

        private sealed class LegacySinglePlayerProfile
        {
            [JsonPropertyName("campaignHash")]
            public string CampaignHash { get; set; }

            [JsonPropertyName("characterHash")]
            public string CharacterHash { get; set; }

            [JsonPropertyName("displayName")]
            public string DisplayName { get; set; }

            [JsonPropertyName("autoApply")]
            public bool AutoApply { get; set; }

            [JsonPropertyName("captured")]
            public bool Captured { get; set; }

            [JsonPropertyName("hideHair")]
            public bool HideHair { get; set; }

            [JsonPropertyName("slots")]
            public Dictionary<string, string> Slots { get; set; }
        }
    }
}
