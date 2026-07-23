using System.Reflection;
using System.Runtime.Loader;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

const string StorageRootKey = "BaroWardrobeSwitcher.PersistenceProbe.StorageRoot";
const string FailurePointKey = "BaroWardrobeSwitcher.PersistenceProbe.FailurePoint";
string[] SlotKeys = ["Head", "Headset", "InnerClothes", "OuterClothes", "Bag", "HealthInterface"];

if (args.Length != 3)
{
    Console.Error.WriteLine(
        "Usage: PersistenceProbe <BaroWardrobeSwitcher.dll> <BarotraumaInstallDir> <LuaCsPublicizedDir>");
    return 64;
}

string modAssemblyPath = Path.GetFullPath(args[0]);
string installDir = Path.GetFullPath(args[1]);
string publicizedDir = Path.GetFullPath(args[2]);
if (!File.Exists(modAssemblyPath))
{
    Console.Error.WriteLine("Mod assembly not found: " + modAssemblyPath);
    return 66;
}

string[] dependencyDirectories =
[
    Path.GetDirectoryName(modAssemblyPath) ?? string.Empty,
    publicizedDir,
    installDir
];
AssemblyLoadContext.Default.Resolving += (_, assemblyName) => ResolveAssembly(assemblyName, dependencyDirectories);

Assembly modAssembly = AssemblyLoadContext.Default.LoadFromAssemblyPath(modAssemblyPath);
Type persistence = modAssembly.GetType("BaroWardrobeSwitcher.WardrobePersistence", throwOnError: true)!;
Type fileLogger = modAssembly.GetType("BaroWardrobeSwitcher.WardrobeFileLogger", throwOnError: true)!;
MethodInfo saveClientLook = RequireMethod(persistence, "SaveClientLook", typeof(string));
MethodInfo saveMigratedClientLook = RequireMethod(
    persistence,
    "SaveMigratedClientLook",
    typeof(string),
    typeof(string));
MethodInfo clearClientLook = RequireMethod(persistence, "ClearClientLook");
MethodInfo loadClientLook = RequireMethod(persistence, "LoadClientLook");
MethodInfo getClientLookPath = RequireMethod(persistence, "GetClientLookPath");
MethodInfo getSinglePlayerProfilesPath = RequireMethod(persistence, "GetSinglePlayerProfilesPath");
MethodInfo getSinglePlayerTransferEnabled = RequireMethod(
    persistence,
    "GetSinglePlayerTransferEnabled");
MethodInfo setSinglePlayerTransferEnabled = RequireMethod(
    persistence,
    "SetSinglePlayerTransferEnabled",
    typeof(bool));
MethodInfo loadSinglePlayerProfile = RequireMethod(
    persistence,
    "LoadSinglePlayerProfile",
    typeof(string),
    typeof(string));
MethodInfo saveSinglePlayerProfile = RequireMethod(
    persistence,
    "SaveSinglePlayerProfile",
    typeof(string),
    typeof(string),
    typeof(string),
    typeof(string));
MethodInfo deleteSinglePlayerProfile = RequireMethod(
    persistence,
    "DeleteSinglePlayerProfile",
    typeof(string),
    typeof(string));
MethodInfo tryImportLegacyClientLook = RequireMethod(
    persistence,
    "TryImportLegacyClientLook",
    typeof(string),
    typeof(string),
    typeof(string));
MethodInfo getVersion = RequireMethod(persistence, "GetVersion");
MethodInfo getLastError = RequireMethod(persistence, "GetLastError");
MethodInfo getLogPath = RequireMethod(fileLogger, "GetPath");
MethodInfo writeLog = RequireMethod(fileLogger, "Write", typeof(string), typeof(string));

string tempBase = Path.GetFullPath(Path.GetTempPath());
string probeRoot = Path.Combine(tempBase, "BaroWardrobeSwitcher-PersistenceProbe-" + Guid.NewGuid().ToString("N"));
string normalizedProbeRoot = Path.GetFullPath(probeRoot);
string requiredPrefix = tempBase.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) +
                        Path.DirectorySeparatorChar;
if (!normalizedProbeRoot.StartsWith(requiredPrefix, StringComparison.OrdinalIgnoreCase))
{
    Console.Error.WriteLine("Refusing to create a persistence probe outside the system temp directory.");
    return 73;
}

Directory.CreateDirectory(normalizedProbeRoot);
List<string> failures = [];
try
{
    Run("canonical-v4-json", TestCanonicalV4, failures);
    Run("persistence-diagnostic-contract", TestDiagnosticContract, failures);
    Run("private-file-log", TestPrivateFileLog, failures);
    Run("utf8-identifier-limit", TestUtf8IdentifierLimit, failures);
    Run("v1-migration-and-backup", TestV1Migration, failures);
    Run("v2-migration-and-backup", TestV2Migration, failures);
    Run("v3-migration-and-backup", TestV3Migration, failures);
    Run("legacy-text-migration-and-backup", TestLegacyTextMigration, failures);
    Run("noncanonical-persistence-quarantine", TestNoncanonicalPersistenceQuarantine, failures);
    Run("atomic-replace-failure-preserves-old", TestAtomicFailure, failures);
    Run("atomic-clear-failure-preserves-old", TestAtomicClearFailure, failures);
    Run("single-player-transfer-default-and-round-trip", TestSinglePlayerTransfer, failures);
    Run("single-player-profile-isolation-and-delete", TestSinglePlayerProfileIsolation, failures);
    Run("single-player-v1-migration-and-backup", TestSinglePlayerV1Migration, failures);
    Run("single-player-v2-migration-and-backup", TestSinglePlayerV2Migration, failures);
    Run("single-player-legacy-import-once", TestSinglePlayerLegacyImport, failures);
    Run("single-player-corrupt-quarantine", TestSinglePlayerCorruptQuarantine, failures);
    Run("single-player-atomic-failure-preserves-old", TestSinglePlayerAtomicFailure, failures);
}
finally
{
    AppContext.SetData(StorageRootKey, null);
    AppContext.SetData(FailurePointKey, null);
    if (Directory.Exists(normalizedProbeRoot))
    {
        Directory.Delete(normalizedProbeRoot, recursive: true);
    }
}

if (failures.Count > 0)
{
    foreach (string failure in failures) { Console.Error.WriteLine("FAIL " + failure); }
    return 1;
}
return 0;

void TestCanonicalV4()
{
    string directory = NewCaseDirectory("canonical");
    Assert(Save(
            "schema=4|captured=true|active=true|auto=true|hidehair=false|" +
            "visibilityHair=show|visibilityBeard=hide|visibilityMoustache=auto|" +
            "visibilityFaceAttachment=show|Head=divinghelmet,Display Name|HeadColor=2131821311"),
        "SaveClientLook rejected a valid canonical look.");
    string path = CurrentPath();
    Assert(Path.GetDirectoryName(path) == directory, "Test storage seam did not select the requested temp directory.");
    ValidateCanonicalFile(
        path,
        "divinghelmet",
        expectedCaptured: true,
        expectedHideHair: false,
        expectedHair: "show",
        expectedBeard: "hide",
        expectedMoustache: "auto",
        expectedFaceAttachment: "show",
        expectedHeadColor: 2131821311);
    string loaded = Load();
    Assert(loaded.Contains("Head=divinghelmet,", StringComparison.Ordinal) &&
           loaded.Contains("HeadColor=2131821311", StringComparison.Ordinal) &&
           loaded.Contains("visibilityHair=show", StringComparison.Ordinal) &&
           loaded.Contains("visibilityFaceAttachment=show", StringComparison.Ordinal),
        "Canonical attachment visibility did not round-trip through LoadClientLook.");
    byte[] beforeInvalidColor = File.ReadAllBytes(path);
    Assert(!Save("captured=true|Head=helmet,|HeadColor=4294967296"),
        "An out-of-range encoded color was accepted.");
    Assert(!Save("captured=true|HeadColor=1"),
        "A color without a corresponding clothing slot was accepted.");
    Assert(beforeInvalidColor.AsSpan().SequenceEqual(File.ReadAllBytes(path)),
        "Rejected encoded colors changed the canonical client look.");
}

void TestPrivateFileLog()
{
    string directory = NewCaseDirectory("private-log");
    Assert((bool)(Invoke(writeLog, "DEBUG", "probe message") ?? false),
        "Wardrobe file logger rejected a diagnostic message.");
    string path = (string?)Invoke(getLogPath) ?? string.Empty;
    Assert(Path.GetDirectoryName(path) == directory,
        "Wardrobe file logger did not use the persistence storage directory.");
    Assert(Path.GetFileName(path) == "WardrobeClient.log",
        "Wardrobe file logger returned an unexpected filename.");
    string contents = File.ReadAllText(path, Encoding.UTF8);
    Assert(contents.Contains("[DEBUG]", StringComparison.Ordinal) &&
           contents.Contains("probe message", StringComparison.Ordinal),
        "Wardrobe file logger omitted the level or message.");
}

void TestDiagnosticContract()
{
    _ = NewCaseDirectory("diagnostic-contract");
    Assert(string.Equals((string?)Invoke(getVersion), "0.5.3", StringComparison.Ordinal),
        "WardrobePersistence did not report the current plugin version.");

    AppContext.SetData(FailurePointKey, "BeforeReplace");
    try
    {
        Assert(!Save("captured=true|hidehair=false|Head=diagnostichelmet,"),
            "Injected persistence failure should make SaveClientLook fail.");
    }
    finally
    {
        AppContext.SetData(FailurePointKey, null);
    }

    string failure = (string?)Invoke(getLastError) ?? string.Empty;
    Assert(failure.Contains("Injected persistence probe failure", StringComparison.Ordinal),
        "SaveClientLook did not expose its underlying persistence error.");
    Assert(Save("captured=true|hidehair=true|Head=recoveredhelmet,"),
        "Persistence did not recover after the injected failure.");
    Assert(string.IsNullOrEmpty((string?)Invoke(getLastError)),
        "A successful persistence operation did not clear the prior error.");
}

void TestUtf8IdentifierLimit()
{
    _ = NewCaseDirectory("utf8-limit");
    string exactly256Bytes = new('a', 256);
    Assert(Save("captured=true|hidehair=false|Head=" + exactly256Bytes + ","),
        "A 256-byte identifier should be accepted.");
    string path = CurrentPath();
    byte[] before = File.ReadAllBytes(path);

    string tooManyUtf8Bytes = new('é', 129);
    Assert(Encoding.UTF8.GetByteCount(tooManyUtf8Bytes) == 258, "Probe UTF-8 fixture is invalid.");
    Assert(!Save("captured=true|hidehair=false|Head=" + tooManyUtf8Bytes + ","),
        "An identifier over 256 UTF-8 bytes should be rejected.");
    Assert(before.AsSpan().SequenceEqual(File.ReadAllBytes(path)),
        "Rejected UTF-8 identifier changed the previously persisted look.");
}

void TestV1Migration()
{
    _ = NewCaseDirectory("v1-migration");
    string path = CurrentPath();
    string legacyJson = """
        {
          "Version": 1,
          "Captured": true,
          "Active": true,
          "AutoApply": true,
          "HideHair": true,
          "SessionKey": "legacy-session",
          "Slots": {
            "Head": { "Identifier": "legacyhelmet", "Name": "Legacy Helmet" }
          }
        }
        """;
    File.WriteAllText(path, legacyJson, new UTF8Encoding(false));

    string loaded = Load();
    Assert(loaded.Contains("Head=legacyhelmet,", StringComparison.Ordinal),
        "Migrated v1 identifier was not returned.");
    Assert(File.Exists(path + ".v1.bak"), "v1 migration did not retain ClientLook.json.v1.bak.");
    Assert(File.ReadAllText(path + ".v1.bak", Encoding.UTF8) == legacyJson,
        "v1 migration backup does not match the original document.");
    ValidateCanonicalFile(path, "legacyhelmet", expectedCaptured: true, expectedHideHair: true);
}

void TestV2Migration()
{
    _ = NewCaseDirectory("v2-migration");
    string path = CurrentPath();
    const string legacyJson = """
        {
          "schemaVersion": 2,
          "captured": true,
          "hideHair": false,
          "slots": {
            "Head": "v2helmet",
            "Headset": null,
            "InnerClothes": null,
            "OuterClothes": null,
            "Bag": null,
            "HealthInterface": null
          }
        }
        """;
    File.WriteAllText(path, legacyJson, new UTF8Encoding(false));

    string loaded = Load();
    Assert(loaded.Contains("Head=v2helmet,", StringComparison.Ordinal) &&
           loaded.Contains("visibilityHair=auto", StringComparison.Ordinal),
        "Migrated v2 look did not return the all-auto visibility policy.");
    Assert(File.Exists(path + ".v2.bak"),
        "v2 migration did not retain ClientLook.json.v2.bak.");
    Assert(File.ReadAllText(path + ".v2.bak", Encoding.UTF8) == legacyJson,
        "v2 migration backup does not match the original document.");
    ValidateCanonicalFile(path, "v2helmet", expectedCaptured: true, expectedHideHair: false);
}

void TestV3Migration()
{
    _ = NewCaseDirectory("v3-migration");
    string path = CurrentPath();
    const string legacyJson = """
        {
          "schemaVersion": 3,
          "captured": true,
          "attachmentVisibility": {
            "Hair": "show",
            "Beard": "hide",
            "Moustache": "auto",
            "FaceAttachment": "show"
          },
          "slots": {
            "Head": "v3helmet",
            "Headset": null,
            "InnerClothes": null,
            "OuterClothes": null,
            "Bag": null,
            "HealthInterface": null
          }
        }
        """;
    File.WriteAllText(path, legacyJson, new UTF8Encoding(false));

    string loaded = Load();
    Assert(loaded.Contains("Head=v3helmet,", StringComparison.Ordinal) &&
           !loaded.Contains("HeadColor=", StringComparison.Ordinal),
        "Migrated v3 look did not preserve missing-color semantics.");
    Assert(File.Exists(path + ".v3.bak"),
        "v3 migration did not retain ClientLook.json.v3.bak.");
    Assert(File.ReadAllText(path + ".v3.bak", Encoding.UTF8) == legacyJson,
        "v3 migration backup does not match the original document.");
    ValidateCanonicalFile(
        path,
        "v3helmet",
        expectedCaptured: true,
        expectedHideHair: false,
        expectedHair: "show",
        expectedBeard: "hide",
        expectedMoustache: "auto",
        expectedFaceAttachment: "show");
}

void TestLegacyTextMigration()
{
    string directory = NewCaseDirectory("legacy-text-migration");
    string legacyPath = Path.Combine(directory, "PersistentClientLook.txt");
    string legacyContents =
        "captured=true|active=false|auto=true|hidehair=true|Head=legacytxthelmet,Legacy Helmet";
    File.WriteAllText(legacyPath, legacyContents, new UTF8Encoding(false));

    bool migrated = (bool)(Invoke(
        saveMigratedClientLook,
        "captured=true|hidehair=true|Head=legacytxthelmet,Legacy Helmet",
        legacyPath) ?? false);
    Assert(migrated, "PersistentClientLook.txt migration failed.");
    Assert(!File.Exists(legacyPath), "Migrated legacy text primary was not retired.");
    Assert(File.Exists(legacyPath + ".v1.bak"), "Legacy text migration did not retain .v1.bak.");
    Assert(File.ReadAllText(legacyPath + ".v1.bak", Encoding.UTF8) == legacyContents,
        "Legacy text migration backup does not match the original document.");
    ValidateCanonicalFile(CurrentPath(), "legacytxthelmet", expectedCaptured: true, expectedHideHair: true);
}

void TestNoncanonicalPersistenceQuarantine()
{
    string validSlots =
        "\"Head\":null,\"Headset\":null,\"InnerClothes\":null," +
        "\"OuterClothes\":null,\"Bag\":null,\"HealthInterface\":null";
    Dictionary<string, string> cases = new(StringComparer.Ordinal)
    {
        ["missing-property"] = "{\"schemaVersion\":2,\"captured\":true,\"slots\":{" + validSlots + "}}",
        ["truncated-json"] = "{\"schemaVersion\":2,\"captured\":true,\"hideHair\":false,\"slots\":{" + validSlots,
        ["extra-property"] = "{\"schemaVersion\":2,\"captured\":true,\"hideHair\":false,\"active\":true,\"slots\":{" + validSlots + "}}",
        ["wrong-slot-type"] = "{\"schemaVersion\":2,\"captured\":true,\"hideHair\":false,\"slots\":{" +
                              "\"Head\":{\"Identifier\":\"bad\"},\"Headset\":null,\"InnerClothes\":null," +
                              "\"OuterClothes\":null,\"Bag\":null,\"HealthInterface\":null}}",
        ["v3-partial-visibility"] =
            "{\"schemaVersion\":3,\"captured\":true,\"attachmentVisibility\":{" +
            "\"Hair\":\"auto\",\"Beard\":\"auto\",\"Moustache\":\"auto\"},\"slots\":{" +
            validSlots + "}}",
        ["v3-overlapping-authority"] =
            "{\"schemaVersion\":3,\"captured\":true,\"hideHair\":false,\"attachmentVisibility\":{" +
            "\"Hair\":\"auto\",\"Beard\":\"auto\",\"Moustache\":\"auto\",\"FaceAttachment\":\"auto\"}," +
            "\"slots\":{" + validSlots + "}}",
        ["v4-missing-colors"] =
            "{\"schemaVersion\":4,\"captured\":true,\"attachmentVisibility\":{" +
            "\"Hair\":\"auto\",\"Beard\":\"auto\",\"Moustache\":\"auto\",\"FaceAttachment\":\"auto\"}," +
            "\"slots\":{" + validSlots + "}}",
        ["v4-orphan-color"] =
            "{\"schemaVersion\":4,\"captured\":true,\"attachmentVisibility\":{" +
            "\"Hair\":\"auto\",\"Beard\":\"auto\",\"Moustache\":\"auto\",\"FaceAttachment\":\"auto\"}," +
            "\"slots\":{" + validSlots + "},\"colors\":{\"Head\":1}}",
        ["v4-unknown-color-slot"] =
            "{\"schemaVersion\":4,\"captured\":true,\"attachmentVisibility\":{" +
            "\"Hair\":\"auto\",\"Beard\":\"auto\",\"Moustache\":\"auto\",\"FaceAttachment\":\"auto\"}," +
            "\"slots\":{" + validSlots + "},\"colors\":{\"Unknown\":1}}"
    };

    foreach ((string name, string json) in cases)
    {
        string directory = NewCaseDirectory("corrupt-" + name);
        string path = CurrentPath();
        File.WriteAllText(path, json, new UTF8Encoding(false));
        Assert(string.IsNullOrEmpty(Load()), name + " unexpectedly loaded.");
        Assert(!File.Exists(path), name + " was not quarantined.");
        Assert(Directory.GetFiles(directory, "ClientLook.json.*.corrupt").Length == 1,
            name + " did not create exactly one timestamped corrupt file.");
        Assert(!File.Exists(path + ".v1.bak"), name + " was incorrectly treated as a v1 migration.");
        Assert(!File.Exists(path + ".v2.bak"), name + " was incorrectly treated as a v2 migration.");
        Assert(!File.Exists(path + ".v3.bak"), name + " was incorrectly treated as a v3 migration.");
    }
}

void TestAtomicFailure()
{
    string directory = NewCaseDirectory("atomic-failure");
    Assert(Save("captured=true|hidehair=false|Head=originalhelmet,"), "Could not create atomic test baseline.");
    string path = CurrentPath();
    byte[] before = File.ReadAllBytes(path);

    AppContext.SetData(FailurePointKey, "BeforeReplace");
    try
    {
        Assert(!Save("captured=true|hidehair=true|Head=replacementhelmet,"),
            "Injected atomic replace failure should make SaveClientLook fail.");
    }
    finally
    {
        AppContext.SetData(FailurePointKey, null);
    }

    Assert(before.AsSpan().SequenceEqual(File.ReadAllBytes(path)),
        "Atomic replace failure changed the old ClientLook.json.");
    Assert(Directory.GetFiles(directory, "*.tmp").Length == 0,
        "Atomic replace failure left a temporary file behind.");
}

void TestAtomicClearFailure()
{
    string directory = NewCaseDirectory("atomic-clear-failure");
    Assert(Save("captured=true|hidehair=false|Head=keephelmet,"), "Could not create clear test baseline.");
    string path = CurrentPath();
    byte[] before = File.ReadAllBytes(path);

    AppContext.SetData(FailurePointKey, "BeforeReplace");
    try
    {
        Assert(!(bool)(Invoke(clearClientLook) ?? false),
            "Injected atomic replace failure should make ClearClientLook fail.");
    }
    finally
    {
        AppContext.SetData(FailurePointKey, null);
    }

    Assert(before.AsSpan().SequenceEqual(File.ReadAllBytes(path)),
        "Atomic clear failure changed the old ClientLook.json.");
    Assert(Directory.GetFiles(directory, "*.tmp").Length == 0,
        "Atomic clear failure left a temporary file behind.");
}

void TestSinglePlayerTransfer()
{
    _ = NewCaseDirectory("single-player-transfer");
    Assert(!GetSinglePlayerTransfer(),
        "Appearance transfer should default to disabled.");
    Assert(SetSinglePlayerTransfer(true),
        "Could not enable single-player appearance transfer.");
    Assert(GetSinglePlayerTransfer(),
        "Enabled single-player appearance transfer did not round-trip.");
    Assert(SetSinglePlayerTransfer(false),
        "Could not disable single-player appearance transfer.");
    Assert(!GetSinglePlayerTransfer(),
        "Disabled single-player appearance transfer did not round-trip.");

    using JsonDocument document = JsonDocument.Parse(
        File.ReadAllText(CurrentSinglePlayerProfilesPath(), Encoding.UTF8));
    ValidateSinglePlayerRoot(document.RootElement);
    Assert(document.RootElement.GetProperty("profiles").GetArrayLength() == 0,
        "Changing the transfer toggle unexpectedly created a character profile.");
}

void TestSinglePlayerProfileIsolation()
{
    _ = NewCaseDirectory("single-player-isolation");
    const string campaignA = @"campaign:C:\Saves\Alpha.save";
    const string campaignB = @"campaign:C:\Saves\Beta.save";
    const string characterA = "12:Alice|5:human|7:crewset|5:alice";
    const string characterB = "10:Bob Crew|5:human|7:crewset|3:bob";

    Assert(SaveProfile(
            campaignA,
            characterA,
            "Alice",
            "schema=4|captured=true|active=true|auto=true|hidehair=false|" +
            "visibilityHair=show|visibilityBeard=hide|visibilityMoustache=auto|" +
            "visibilityFaceAttachment=show|Head=alphahelmet,|HeadColor=2131821311"),
        "Could not save the first campaign profile.");
    Assert(SaveProfile(
            campaignA,
            characterB,
            "Bob",
            "captured=true|active=false|auto=false|hidehair=false|Head=bobhelmet,"),
        "Could not save the second character profile.");
    Assert(SaveProfile(
            campaignB,
            characterA,
            "Alice",
            "captured=true|active=false|auto=false|hidehair=false|Head=betahelmet,"),
        "Could not save the cross-campaign profile.");

    Assert(LoadProfile(campaignA, characterA).Contains("Head=alphahelmet,", StringComparison.Ordinal) &&
           LoadProfile(campaignA, characterA).Contains("HeadColor=2131821311", StringComparison.Ordinal) &&
           LoadProfile(campaignA, characterA).Contains("visibilityHair=show", StringComparison.Ordinal),
        "The first character profile did not round-trip.");
    Assert(LoadProfile(campaignA, characterB).Contains("Head=bobhelmet,", StringComparison.Ordinal),
        "The second character profile did not round-trip.");
    Assert(LoadProfile(campaignB, characterA).Contains("Head=betahelmet,", StringComparison.Ordinal),
        "The same character key was not isolated across campaigns.");
    Assert(LoadProfile(campaignA, characterB).Contains("auto=false", StringComparison.Ordinal),
        "An inactive saved profile did not remain inactive.");

    string path = CurrentSinglePlayerProfilesPath();
    string json = File.ReadAllText(path, Encoding.UTF8);
    Assert(!json.Contains(campaignA, StringComparison.Ordinal) &&
           !json.Contains(campaignB, StringComparison.Ordinal) &&
           !json.Contains(characterA, StringComparison.Ordinal) &&
           !json.Contains(characterB, StringComparison.Ordinal),
        "Raw campaign or character identity was written to disk.");

    using (JsonDocument document = JsonDocument.Parse(json))
    {
        JsonElement root = document.RootElement;
        ValidateSinglePlayerRoot(root);
        JsonElement[] profiles = root.GetProperty("profiles").EnumerateArray().ToArray();
        Assert(profiles.Length == 3, "Single-player profiles were not stored independently.");
        Assert(profiles.Any(profile =>
                profile.GetProperty("campaignHash").GetString() == HashKey(campaignA) &&
                profile.GetProperty("characterHash").GetString() == HashKey(characterA) &&
                profile.GetProperty("displayName").GetString() == "Alice" &&
                profile.GetProperty("autoApply").GetBoolean()),
            "The canonical profile document does not contain the expected hashed profile.");
        JsonElement alice = profiles.Single(profile =>
            profile.GetProperty("campaignHash").GetString() == HashKey(campaignA) &&
            profile.GetProperty("characterHash").GetString() == HashKey(characterA));
        ValidateAttachmentVisibility(
            alice.GetProperty("attachmentVisibility"),
            expectedHair: "show",
            expectedBeard: "hide",
            expectedMoustache: "auto",
            expectedFaceAttachment: "show");
        Assert(alice.GetProperty("colors").GetProperty("Head").GetUInt32() == 2131821311,
            "Single-player profile did not persist the custom clothing color.");
    }

    Assert(DeleteProfile(campaignA, characterA),
        "Could not delete one single-player profile.");
    Assert(string.IsNullOrEmpty(LoadProfile(campaignA, characterA)),
        "Deleted profile was still loadable.");
    Assert(LoadProfile(campaignA, characterB).Contains("Head=bobhelmet,", StringComparison.Ordinal),
        "Deleting one character profile removed another character.");
    Assert(LoadProfile(campaignB, characterA).Contains("Head=betahelmet,", StringComparison.Ordinal),
        "Deleting one character profile removed another campaign.");
}

void TestSinglePlayerV1Migration()
{
    _ = NewCaseDirectory("single-player-v1-migration");
    const string campaign = "campaign:profile-v1.save";
    const string character = "profile-v1-character";
    string path = CurrentSinglePlayerProfilesPath();
    string legacyJson = $$"""
        {
          "schemaVersion": 1,
          "transferToUnconfiguredCharacter": true,
          "importedLegacyCampaigns": [],
          "profiles": [
            {
              "campaignHash": "{{HashKey(campaign)}}",
              "characterHash": "{{HashKey(character)}}",
              "displayName": "Migrated Crew",
              "autoApply": true,
              "captured": true,
              "hideHair": true,
              "slots": {
                "Head": "profilev1helmet",
                "Headset": null,
                "InnerClothes": null,
                "OuterClothes": null,
                "Bag": null,
                "HealthInterface": null
              }
            }
          ]
        }
        """;
    File.WriteAllText(path, legacyJson, new UTF8Encoding(false));

    Assert(GetSinglePlayerTransfer(),
        "Migrated single-player transfer setting was not retained.");
    Assert(File.Exists(path + ".v1.bak"),
        "Single-player v1 migration did not retain .v1.bak.");
    Assert(File.ReadAllText(path + ".v1.bak", Encoding.UTF8) == legacyJson,
        "Single-player v1 backup does not match the original document.");
    string loaded = LoadProfile(campaign, character);
    Assert(loaded.Contains("Head=profilev1helmet,", StringComparison.Ordinal) &&
           loaded.Contains("visibilityHair=hide", StringComparison.Ordinal) &&
           loaded.Contains("visibilityFaceAttachment=auto", StringComparison.Ordinal),
        "Single-player v1 migration did not preserve the legacy visibility preset.");
    using JsonDocument migrated = JsonDocument.Parse(File.ReadAllText(path, Encoding.UTF8));
    ValidateSinglePlayerRoot(migrated.RootElement);
}

void TestSinglePlayerV2Migration()
{
    _ = NewCaseDirectory("single-player-v2-migration");
    const string campaign = "campaign:profile-v2.save";
    const string character = "profile-v2-character";
    string path = CurrentSinglePlayerProfilesPath();
    string legacyJson = $$"""
        {
          "schemaVersion": 2,
          "transferToUnconfiguredCharacter": false,
          "importedLegacyCampaigns": [],
          "profiles": [
            {
              "campaignHash": "{{HashKey(campaign)}}",
              "characterHash": "{{HashKey(character)}}",
              "displayName": "Migrated V2 Crew",
              "autoApply": true,
              "captured": true,
              "attachmentVisibility": {
                "Hair": "show",
                "Beard": "hide",
                "Moustache": "auto",
                "FaceAttachment": "show"
              },
              "slots": {
                "Head": "profilev2helmet",
                "Headset": null,
                "InnerClothes": null,
                "OuterClothes": null,
                "Bag": null,
                "HealthInterface": null
              }
            }
          ]
        }
        """;
    File.WriteAllText(path, legacyJson, new UTF8Encoding(false));

    string loaded = LoadProfile(campaign, character);
    Assert(loaded.Contains("Head=profilev2helmet,", StringComparison.Ordinal) &&
           loaded.Contains("visibilityHair=show", StringComparison.Ordinal) &&
           !loaded.Contains("HeadColor=", StringComparison.Ordinal),
        "Single-player v2 migration did not preserve missing-color semantics.");
    Assert(File.Exists(path + ".v2.bak"),
        "Single-player v2 migration did not retain .v2.bak.");
    Assert(File.ReadAllText(path + ".v2.bak", Encoding.UTF8) == legacyJson,
        "Single-player v2 backup does not match the original document.");
    using JsonDocument migrated = JsonDocument.Parse(File.ReadAllText(path, Encoding.UTF8));
    ValidateSinglePlayerRoot(migrated.RootElement);
}

void TestSinglePlayerLegacyImport()
{
    _ = NewCaseDirectory("single-player-legacy-import");
    string clientPath = CurrentPath();
    const string legacyJson = """
        {
          "Version": 1,
          "Captured": true,
          "Active": true,
          "AutoApply": true,
          "HideHair": true,
          "Slots": {
            "Head": { "Identifier": "legacyimporthelmet", "Name": "Legacy Import Helmet" }
          }
        }
        """;
    File.WriteAllText(clientPath, legacyJson, new UTF8Encoding(false));

    const string campaignA = "campaign:legacy-a.save";
    const string characterA = "legacy-character-a";
    Assert(ImportLegacy(campaignA, characterA, "Legacy Crew"),
        "Legacy ClientLook.json was not imported into the first controlled profile.");
    string imported = LoadProfile(campaignA, characterA);
    Assert(imported.Contains("Head=legacyimporthelmet,", StringComparison.Ordinal) &&
           imported.Contains("captured=true", StringComparison.Ordinal) &&
           imported.Contains("hidehair=true", StringComparison.Ordinal) &&
           imported.Contains("auto=false", StringComparison.Ordinal),
        "Imported legacy look did not preserve its appearance while remaining inactive.");
    Assert(File.Exists(clientPath),
        "Legacy import removed ClientLook.json used by multiplayer.");
    Assert(File.Exists(clientPath + ".v1.bak"),
        "Legacy import did not retain the original schema-v1 backup.");
    ValidateCanonicalFile(clientPath, "legacyimporthelmet", expectedCaptured: true, expectedHideHair: true);

    Assert(Save("captured=true|hidehair=false|Head=laterhelmet,"),
        "Could not replace the multiplayer ClientLook.json fixture.");
    Assert(!ImportLegacy(campaignA, "legacy-character-b", "Other Crew"),
        "The same campaign imported legacy ClientLook.json more than once.");
    Assert(string.IsNullOrEmpty(LoadProfile(campaignA, "legacy-character-b")),
        "A second character received the already-imported legacy look.");
    Assert(LoadProfile(campaignA, characterA).Contains(
            "Head=legacyimporthelmet,",
            StringComparison.Ordinal),
        "A repeated legacy import changed the original imported profile.");

    const string campaignB = "campaign:legacy-b.save";
    const string characterB = "legacy-character-existing";
    Assert(SaveProfile(
            campaignB,
            characterB,
            "Existing Crew",
            "captured=true|active=false|auto=false|hidehair=false|Head=existinghelmet,"),
        "Could not create an existing profile for the no-overwrite case.");
    Assert(!ImportLegacy(campaignB, characterB, "Existing Crew"),
        "Legacy import overwrote an existing profile.");
    Assert(LoadProfile(campaignB, characterB).Contains(
            "Head=existinghelmet,",
            StringComparison.Ordinal),
        "Existing profile changed during legacy import.");
    Assert(!ImportLegacy(campaignB, "legacy-character-c", "Third Crew"),
        "A campaign marked imported was imported again after an existing-profile skip.");
}

void TestSinglePlayerCorruptQuarantine()
{
    string directory = NewCaseDirectory("single-player-corrupt");
    string path = CurrentSinglePlayerProfilesPath();
    File.WriteAllText(
        path,
        """
        {
          "schemaVersion": 1,
          "transferToUnconfiguredCharacter": false,
          "importedLegacyCampaigns": [],
          "profiles": [],
          "unexpected": true
        }
        """,
        new UTF8Encoding(false));

    Assert(!GetSinglePlayerTransfer(),
        "A corrupt single-player profile document returned an enabled setting.");
    Assert(!File.Exists(path),
        "A corrupt single-player profile document was not quarantined.");
    Assert(Directory.GetFiles(directory, "SinglePlayerProfiles.json.*.corrupt").Length == 1,
        "Corrupt single-player persistence did not create exactly one quarantine file.");
    Assert(SaveProfile(
            "campaign:recovered.save",
            "recovered-character",
            "Recovered Crew",
            "captured=true|auto=false|hidehair=false|Head=recoveredhelmet,"),
        "Single-player persistence did not recover after quarantine.");
}

void TestSinglePlayerAtomicFailure()
{
    string directory = NewCaseDirectory("single-player-atomic-failure");
    const string campaign = "campaign:atomic.save";
    const string character = "atomic-character";
    Assert(SaveProfile(
            campaign,
            character,
            "Atomic Crew",
            "captured=true|auto=true|hidehair=false|Head=originalprofilehelmet,"),
        "Could not create the single-player atomic baseline.");
    string path = CurrentSinglePlayerProfilesPath();
    byte[] before = File.ReadAllBytes(path);

    AppContext.SetData(FailurePointKey, "BeforeReplace");
    try
    {
        Assert(!SaveProfile(
                campaign,
                character,
                "Atomic Crew",
                "captured=true|auto=true|hidehair=true|Head=replacementprofilehelmet,"),
            "Injected atomic failure should make SaveSinglePlayerProfile fail.");
    }
    finally
    {
        AppContext.SetData(FailurePointKey, null);
    }

    Assert(before.AsSpan().SequenceEqual(File.ReadAllBytes(path)),
        "Atomic failure changed the old SinglePlayerProfiles.json.");
    Assert(Directory.GetFiles(directory, "*.tmp").Length == 0,
        "Single-player atomic failure left a temporary file behind.");
    Assert(LoadProfile(campaign, character).Contains(
            "Head=originalprofilehelmet,",
            StringComparison.Ordinal),
        "The old single-player profile was not loadable after atomic failure.");
}

string NewCaseDirectory(string name)
{
    string directory = Path.Combine(normalizedProbeRoot, name);
    Directory.CreateDirectory(directory);
    AppContext.SetData(StorageRootKey, directory);
    AppContext.SetData(FailurePointKey, null);
    return directory;
}

bool Save(string encodedLook) => (bool)(Invoke(saveClientLook, encodedLook) ?? false);

string Load() => (string?)Invoke(loadClientLook) ?? string.Empty;

string CurrentPath() => (string?)Invoke(getClientLookPath) ?? throw new InvalidOperationException("No client path returned.");

string CurrentSinglePlayerProfilesPath() =>
    (string?)Invoke(getSinglePlayerProfilesPath) ??
    throw new InvalidOperationException("No single-player profiles path returned.");

bool GetSinglePlayerTransfer() =>
    (bool)(Invoke(getSinglePlayerTransferEnabled) ?? false);

bool SetSinglePlayerTransfer(bool enabled) =>
    (bool)(Invoke(setSinglePlayerTransferEnabled, enabled) ?? false);

bool SaveProfile(
    string campaignKey,
    string characterKey,
    string displayName,
    string encodedLook) =>
    (bool)(Invoke(
        saveSinglePlayerProfile,
        campaignKey,
        characterKey,
        displayName,
        encodedLook) ?? false);

string LoadProfile(string campaignKey, string characterKey) =>
    (string?)Invoke(loadSinglePlayerProfile, campaignKey, characterKey) ?? string.Empty;

bool DeleteProfile(string campaignKey, string characterKey) =>
    (bool)(Invoke(deleteSinglePlayerProfile, campaignKey, characterKey) ?? false);

bool ImportLegacy(string campaignKey, string characterKey, string displayName) =>
    (bool)(Invoke(
        tryImportLegacyClientLook,
        campaignKey,
        characterKey,
        displayName) ?? false);

string HashKey(string value) =>
    Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();

void ValidateSinglePlayerRoot(JsonElement root)
{
    string[] actualProperties = root.EnumerateObject().Select(property => property.Name).Order().ToArray();
    string[] expectedProperties =
    [
        "importedLegacyCampaigns",
        "profiles",
        "schemaVersion",
        "transferToUnconfiguredCharacter"
    ];
    Assert(actualProperties.SequenceEqual(expectedProperties, StringComparer.Ordinal),
        "Single-player schema contains missing or extra top-level properties.");
    Assert(root.GetProperty("schemaVersion").GetInt32() == 3,
        "Single-player schema version is not 3.");
    Assert(root.GetProperty("transferToUnconfiguredCharacter").ValueKind is
            JsonValueKind.True or JsonValueKind.False,
        "Single-player transfer setting is not a boolean.");
    Assert(root.GetProperty("importedLegacyCampaigns").ValueKind == JsonValueKind.Array,
        "Imported campaign scopes are not an array.");
    Assert(root.GetProperty("profiles").ValueKind == JsonValueKind.Array,
        "Single-player profiles are not an array.");

    foreach (JsonElement profile in root.GetProperty("profiles").EnumerateArray())
    {
        string[] actualProfileProperties =
            profile.EnumerateObject().Select(property => property.Name).Order().ToArray();
        string[] expectedProfileProperties =
        [
            "autoApply",
            "campaignHash",
            "captured",
            "characterHash",
            "colors",
            "displayName",
            "attachmentVisibility",
            "slots"
        ];
        Array.Sort(expectedProfileProperties, StringComparer.Ordinal);
        Assert(actualProfileProperties.SequenceEqual(expectedProfileProperties, StringComparer.Ordinal),
            "Single-player profile contains missing or extra properties.");
        Assert((profile.GetProperty("campaignHash").GetString() ?? string.Empty).Length == 64,
            "Campaign scope was not stored as SHA-256.");
        Assert((profile.GetProperty("characterHash").GetString() ?? string.Empty).Length == 64,
            "Character identity was not stored as SHA-256.");
        ValidateAttachmentVisibility(profile.GetProperty("attachmentVisibility"));
        string[] actualSlotKeys =
            profile.GetProperty("slots").EnumerateObject().Select(property => property.Name).Order().ToArray();
        Assert(actualSlotKeys.SequenceEqual(SlotKeys.Order(), StringComparer.Ordinal),
            "Single-player profile does not contain exactly the six canonical slots.");
        string[] actualColorKeys =
            profile.GetProperty("colors").EnumerateObject().Select(property => property.Name).Order().ToArray();
        Assert(actualColorKeys.SequenceEqual(SlotKeys.Order(), StringComparer.Ordinal),
            "Single-player profile does not contain exactly the six canonical color slots.");
    }
}

void ValidateAttachmentVisibility(
    JsonElement visibility,
    string? expectedHair = null,
    string? expectedBeard = null,
    string? expectedMoustache = null,
    string? expectedFaceAttachment = null)
{
    string[] actualProperties =
        visibility.EnumerateObject().Select(property => property.Name).Order().ToArray();
    string[] expectedProperties = ["Beard", "FaceAttachment", "Hair", "Moustache"];
    Assert(actualProperties.SequenceEqual(expectedProperties, StringComparer.Ordinal),
        "Attachment visibility does not contain exactly four canonical layers.");
    string hair = visibility.GetProperty("Hair").GetString() ?? string.Empty;
    string beard = visibility.GetProperty("Beard").GetString() ?? string.Empty;
    string moustache = visibility.GetProperty("Moustache").GetString() ?? string.Empty;
    string faceAttachment =
        visibility.GetProperty("FaceAttachment").GetString() ?? string.Empty;
    string[] validStates = ["auto", "hide", "show"];
    Assert(validStates.Contains(hair, StringComparer.Ordinal) &&
           validStates.Contains(beard, StringComparer.Ordinal) &&
           validStates.Contains(moustache, StringComparer.Ordinal) &&
           validStates.Contains(faceAttachment, StringComparer.Ordinal),
        "Attachment visibility contains an invalid state.");
    if (expectedHair is not null)
    {
        Assert(hair == expectedHair, "Hair visibility mismatch.");
    }
    if (expectedBeard is not null)
    {
        Assert(beard == expectedBeard, "Beard visibility mismatch.");
    }
    if (expectedMoustache is not null)
    {
        Assert(moustache == expectedMoustache, "Moustache visibility mismatch.");
    }
    if (expectedFaceAttachment is not null)
    {
        Assert(faceAttachment == expectedFaceAttachment,
            "Face-attachment visibility mismatch.");
    }
}

void ValidateCanonicalFile(
    string path,
    string expectedHead,
    bool expectedCaptured,
    bool expectedHideHair,
    string? expectedHair = null,
    string? expectedBeard = null,
    string? expectedMoustache = null,
    string expectedFaceAttachment = "auto",
    uint? expectedHeadColor = null)
{
    using JsonDocument document = JsonDocument.Parse(File.ReadAllText(path, Encoding.UTF8));
    JsonElement root = document.RootElement;
    string[] actualProperties = root.EnumerateObject().Select(property => property.Name).Order().ToArray();
    string[] expectedProperties = ["attachmentVisibility", "captured", "colors", "schemaVersion", "slots"];
    Array.Sort(expectedProperties, StringComparer.Ordinal);
    Assert(actualProperties.SequenceEqual(expectedProperties, StringComparer.Ordinal),
        "Schema v4 contains missing or extra top-level properties.");
    Assert(root.GetProperty("schemaVersion").GetInt32() == 4, "Schema version is not 4.");
    Assert(root.GetProperty("captured").GetBoolean() == expectedCaptured, "Captured intent mismatch.");
    Assert(!root.TryGetProperty("hideHair", out _),
        "Schema v4 must not persist authoritative hideHair.");
    string legacyState = expectedHideHair ? "hide" : "auto";
    ValidateAttachmentVisibility(
        root.GetProperty("attachmentVisibility"),
        expectedHair ?? legacyState,
        expectedBeard ?? legacyState,
        expectedMoustache ?? legacyState,
        expectedFaceAttachment);

    JsonElement slots = root.GetProperty("slots");
    string[] actualSlotKeys = slots.EnumerateObject().Select(property => property.Name).Order().ToArray();
    Assert(actualSlotKeys.SequenceEqual(SlotKeys.Order(), StringComparer.Ordinal),
        "Schema v4 does not contain exactly the six canonical slots.");
    Assert(slots.GetProperty("Head").ValueKind == JsonValueKind.String &&
           slots.GetProperty("Head").GetString() == expectedHead,
        "Head slot is not persisted as a stable identifier string.");
    foreach (string key in SlotKeys.Where(key => key != "Head"))
    {
        Assert(slots.GetProperty(key).ValueKind == JsonValueKind.Null,
            key + " should be persisted as null.");
    }

    JsonElement colors = root.GetProperty("colors");
    string[] actualColorKeys =
        colors.EnumerateObject().Select(property => property.Name).Order().ToArray();
    Assert(actualColorKeys.SequenceEqual(SlotKeys.Order(), StringComparer.Ordinal),
        "Schema v4 does not contain exactly the six canonical color slots.");
    foreach (string key in SlotKeys)
    {
        JsonElement color = colors.GetProperty(key);
        if (key == "Head" && expectedHeadColor.HasValue)
        {
            Assert(color.ValueKind == JsonValueKind.Number &&
                   color.GetUInt32() == expectedHeadColor.Value,
                "Head custom color did not round-trip.");
        }
        else
        {
            Assert(color.ValueKind == JsonValueKind.Null,
                key + " color should be persisted as null.");
        }
    }
}

object? Invoke(MethodInfo method, params object?[] parameters)
{
    try
    {
        return method.Invoke(null, parameters);
    }
    catch (TargetInvocationException ex) when (ex.InnerException != null)
    {
        throw new InvalidOperationException(
            method.Name + " threw " + ex.InnerException.GetType().Name + ": " + ex.InnerException.Message,
            ex.InnerException);
    }
}

static MethodInfo RequireMethod(Type type, string name, params Type[] parameters)
{
    return type.GetMethod(name, BindingFlags.Public | BindingFlags.Static, binder: null, parameters, modifiers: null) ??
           throw new MissingMethodException(type.FullName, name);
}

static Assembly? ResolveAssembly(AssemblyName assemblyName, IEnumerable<string> directories)
{
    foreach (string directory in directories)
    {
        string candidate = Path.Combine(directory, assemblyName.Name + ".dll");
        if (File.Exists(candidate)) { return AssemblyLoadContext.Default.LoadFromAssemblyPath(candidate); }

        if (string.Equals(assemblyName.Name, "MonoGame.Framework", StringComparison.Ordinal))
        {
            foreach (string fileName in new[]
                     {
                         "MonoGame.Framework.Windows.NetStandard.dll",
                         "MonoGame.Framework.Linux.NetStandard.dll",
                         "MonoGame.Framework.dll"
                     })
            {
                candidate = Path.Combine(directory, fileName);
                if (File.Exists(candidate)) { return AssemblyLoadContext.Default.LoadFromAssemblyPath(candidate); }
            }
        }
    }
    return null;
}

static void Run(string name, Action test, ICollection<string> failures)
{
    try
    {
        test();
        Console.WriteLine("PASS " + name);
    }
    catch (Exception ex)
    {
        failures.Add(name + ": " + ex.Message);
    }
}

static void Assert(bool condition, string message)
{
    if (!condition) { throw new InvalidOperationException(message); }
}
