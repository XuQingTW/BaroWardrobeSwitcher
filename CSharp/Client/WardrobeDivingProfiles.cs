using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace BaroWardrobeSwitcher
{
    // 潛水外觀的存檔分檔；共用解析、雜湊與安全寫檔方法在其他 WardrobePersistence partial 中。
    public static partial class WardrobePersistence
    {
        // 這是 DivingProfiles.json 自己的格式版本，不跟隨模組版本自動增加。
        private const int DivingProfilesVersion = 1;
        private const string DivingProfilesFileName = "DivingProfiles.json";
        private const int MaximumDivingProfiles = 512;

        public static string GetDivingProfilesPath()
        {
            return Path.Combine(GetStorageDirectory(), DivingProfilesFileName);
        }

        public static string LoadDivingProfile(string profileKey)
        {
            ClearLastError();
            try
            {
                string profileHash = HashRequiredKey(profileKey, nameof(profileKey));
                DivingProfile profile = ReadDivingProfiles().Profiles.FirstOrDefault(
                    candidate => string.Equals(candidate.ProfileHash, profileHash, StringComparison.Ordinal));
                return profile == null ? string.Empty : EncodeDivingProfile(profile);
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to load diving appearance profile", ex);
                return string.Empty;
            }
        }

        // mode：0 關閉、1 潛水服、2 自訂，對應 Lua Helpers.DIVING_MODE_*。
        // encodedLook 是 Lua 橋接字串；存檔時解析成欄位，profileKey 則雜湊後保存。
        public static bool SaveDivingProfile(string profileKey, int mode, string encodedLook)
        {
            ClearLastError();
            try
            {
                if (mode < 0 || mode > 2)
                {
                    throw new InvalidDataException("Diving appearance mode is invalid.");
                }

                string profileHash = HashRequiredKey(profileKey, nameof(profileKey));
                ClientLookDocument look = ParseClientLook(encodedLook);
                ValidateDocument(look);
                DivingProfilesDocument document = ReadDivingProfiles();
                DivingProfile profile = document.Profiles.FirstOrDefault(
                    candidate => string.Equals(candidate.ProfileHash, profileHash, StringComparison.Ordinal));

                // 關閉且沒有捕捉紀錄才刪除；單純切到關閉仍可保留已存的自訂外觀。
                if (mode == 0 && !look.Captured && !HasAnySlot(look.Slots))
                {
                    if (profile != null) { document.Profiles.Remove(profile); }
                    WriteDivingProfiles(document);
                    return true;
                }

                if (profile == null)
                {
                    if (document.Profiles.Count >= MaximumDivingProfiles)
                    {
                        throw new InvalidDataException("Diving appearance profile limit has been reached.");
                    }
                    profile = new DivingProfile { ProfileHash = profileHash };
                    document.Profiles.Add(profile);
                }

                profile.Mode = mode;
                profile.Captured = look.Captured;
                profile.Slots = CopySlots(look.Slots);
                profile.Colors = CopyColors(look.Colors);
                WriteDivingProfiles(document);
                return true;
            }
            catch (Exception ex)
            {
                LogPersistenceError("Failed to save diving appearance profile", ex);
                return false;
            }
        }

        // 缺檔建立空資料；格式損壞則隔離原檔，再回傳空資料供後續使用。
        private static DivingProfilesDocument ReadDivingProfiles()
        {
            string path = GetDivingProfilesPath();
            if (!File.Exists(path)) { return CreateEmptyDivingProfiles(); }
            try
            {
                string json = File.ReadAllText(path);
                using JsonDocument parsed = JsonDocument.Parse(json);
                if (ReadSchemaVersion(parsed.RootElement) != DivingProfilesVersion)
                {
                    throw new InvalidDataException("Diving appearance profile document is not canonical.");
                }
                DivingProfilesDocument document =
                    JsonSerializer.Deserialize<DivingProfilesDocument>(json, JsonOptions);
                ValidateDivingProfiles(document);
                return document;
            }
            catch (JsonException ex)
            {
                QuarantineCorruptFile(path, ex);
                return CreateEmptyDivingProfiles();
            }
            catch (InvalidDataException ex)
            {
                QuarantineCorruptFile(path, ex);
                return CreateEmptyDivingProfiles();
            }
        }

        private static void WriteDivingProfiles(DivingProfilesDocument document)
        {
            ValidateDivingProfiles(document);
            document.Profiles = document.Profiles
                .OrderBy(profile => profile.ProfileHash, StringComparer.Ordinal)
                .ToList();
            WriteJson(GetDivingProfilesPath(), document);
        }

        private static DivingProfilesDocument CreateEmptyDivingProfiles()
        {
            return new DivingProfilesDocument
            {
                Version = DivingProfilesVersion,
                Profiles = new List<DivingProfile>()
            };
        }

        private static void ValidateDivingProfiles(DivingProfilesDocument document)
        {
            if (document == null ||
                document.Version != DivingProfilesVersion ||
                document.Profiles == null ||
                document.Profiles.Count > MaximumDivingProfiles)
            {
                throw new InvalidDataException("Diving appearance profile schema is invalid.");
            }

            var hashes = new HashSet<string>(StringComparer.Ordinal);
            foreach (DivingProfile profile in document.Profiles)
            {
                if (profile == null) { throw new InvalidDataException("Diving appearance profile is empty."); }
                ValidateHash(profile.ProfileHash, "diving profile");
                if (!hashes.Add(profile.ProfileHash))
                {
                    throw new InvalidDataException("Diving appearance profile hash is duplicated.");
                }
                if (profile.Mode < 0 || profile.Mode > 2)
                {
                    throw new InvalidDataException("Diving appearance mode is invalid.");
                }

                var look = new ClientLookDocument
                {
                    Version = PersistenceVersion,
                    Captured = profile.Captured,
                    AttachmentVisibility = CreateAttachmentVisibility(false),
                    Slots = profile.Slots,
                    Colors = profile.Colors
                };
                ValidateDocument(look);
                profile.Slots = CopySlots(look.Slots);
                profile.Colors = CopyColors(look.Colors);
            }
        }

        private static string EncodeDivingProfile(DivingProfile profile)
        {
            var parts = new List<string>
            {
                "mode=" + profile.Mode,
                "captured=" + profile.Captured.ToString().ToLowerInvariant()
            };
            AppendEncodedSlots(parts, profile.Slots);
            AppendEncodedColors(parts, profile.Colors);
            return string.Join("|", parts);
        }

        private sealed class DivingProfilesDocument
        {
            [JsonRequired]
            [JsonPropertyName("schemaVersion")]
            public int Version { get; set; }

            [JsonRequired]
            [JsonPropertyName("profiles")]
            public List<DivingProfile> Profiles { get; set; }
        }

        private sealed class DivingProfile
        {
            [JsonRequired]
            [JsonPropertyName("profileHash")]
            public string ProfileHash { get; set; }

            [JsonRequired]
            [JsonPropertyName("mode")]
            public int Mode { get; set; }

            [JsonRequired]
            [JsonPropertyName("captured")]
            public bool Captured { get; set; }

            [JsonRequired]
            [JsonPropertyName("slots")]
            public Dictionary<string, string> Slots { get; set; }

            [JsonRequired]
            [JsonPropertyName("colors")]
            public Dictionary<string, uint?> Colors { get; set; }
        }
    }
}
