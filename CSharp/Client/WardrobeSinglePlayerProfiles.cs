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
                    SinglePlayerProfilesDocument migrated = MigrateSinglePlayerProfilesV1(json);
                    ValidateSinglePlayerProfiles(migrated);
                    File.Copy(path, path + ".v1.bak", overwrite: true);
                    WriteSinglePlayerProfiles(migrated);
                    LogPersistenceInfo(
                        "Migrated single-player wardrobe profiles from schema v1 to schema v2.");
                    return migrated;
                }
                if (version != SinglePlayerProfilesVersion)
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
            [JsonRequired]
            [JsonPropertyName("schemaVersion")]
            public int Version { get; set; }

            [JsonRequired]
            [JsonPropertyName("transferToUnconfiguredCharacter")]
            public bool TransferToUnconfiguredCharacter { get; set; }

            [JsonRequired]
            [JsonPropertyName("importedLegacyCampaigns")]
            public List<string> ImportedLegacyCampaigns { get; set; }

            [JsonRequired]
            [JsonPropertyName("profiles")]
            public List<SinglePlayerProfile> Profiles { get; set; }
        }

        private sealed class SinglePlayerProfile
        {
            [JsonRequired]
            [JsonPropertyName("campaignHash")]
            public string CampaignHash { get; set; }

            [JsonRequired]
            [JsonPropertyName("characterHash")]
            public string CharacterHash { get; set; }

            [JsonRequired]
            [JsonPropertyName("displayName")]
            public string DisplayName { get; set; }

            [JsonRequired]
            [JsonPropertyName("autoApply")]
            public bool AutoApply { get; set; }

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

        private sealed class LegacySinglePlayerProfilesDocument
        {
            [JsonRequired]
            [JsonPropertyName("schemaVersion")]
            public int Version { get; set; }

            [JsonRequired]
            [JsonPropertyName("transferToUnconfiguredCharacter")]
            public bool TransferToUnconfiguredCharacter { get; set; }

            [JsonRequired]
            [JsonPropertyName("importedLegacyCampaigns")]
            public List<string> ImportedLegacyCampaigns { get; set; }

            [JsonRequired]
            [JsonPropertyName("profiles")]
            public List<LegacySinglePlayerProfile> Profiles { get; set; }
        }

        private sealed class LegacySinglePlayerProfile
        {
            [JsonRequired]
            [JsonPropertyName("campaignHash")]
            public string CampaignHash { get; set; }

            [JsonRequired]
            [JsonPropertyName("characterHash")]
            public string CharacterHash { get; set; }

            [JsonRequired]
            [JsonPropertyName("displayName")]
            public string DisplayName { get; set; }

            [JsonRequired]
            [JsonPropertyName("autoApply")]
            public bool AutoApply { get; set; }

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
}
