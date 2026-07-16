using System.Reflection;
using System.Runtime.Loader;
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
MethodInfo saveClientLook = RequireMethod(persistence, "SaveClientLook", typeof(string));
MethodInfo saveMigratedClientLook = RequireMethod(
    persistence,
    "SaveMigratedClientLook",
    typeof(string),
    typeof(string));
MethodInfo clearClientLook = RequireMethod(persistence, "ClearClientLook");
MethodInfo loadClientLook = RequireMethod(persistence, "LoadClientLook");
MethodInfo getClientLookPath = RequireMethod(persistence, "GetClientLookPath");
MethodInfo getVersion = RequireMethod(persistence, "GetVersion");
MethodInfo getLastError = RequireMethod(persistence, "GetLastError");

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
    Run("canonical-v2-json", TestCanonicalV2, failures);
    Run("persistence-diagnostic-contract", TestDiagnosticContract, failures);
    Run("utf8-identifier-limit", TestUtf8IdentifierLimit, failures);
    Run("v1-migration-and-backup", TestV1Migration, failures);
    Run("legacy-text-migration-and-backup", TestLegacyTextMigration, failures);
    Run("noncanonical-v2-quarantine", TestNoncanonicalV2Quarantine, failures);
    Run("atomic-replace-failure-preserves-old", TestAtomicFailure, failures);
    Run("atomic-clear-failure-preserves-old", TestAtomicClearFailure, failures);
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

void TestCanonicalV2()
{
    string directory = NewCaseDirectory("canonical");
    Assert(Save("captured=true|active=true|auto=true|hidehair=true|Head=divinghelmet,Display Name"),
        "SaveClientLook rejected a valid canonical look.");
    string path = CurrentPath();
    Assert(Path.GetDirectoryName(path) == directory, "Test storage seam did not select the requested temp directory.");
    ValidateCanonicalFile(path, "divinghelmet", expectedCaptured: true, expectedHideHair: true);
    string loaded = Load();
    Assert(loaded.Contains("Head=divinghelmet,", StringComparison.Ordinal),
        "Canonical look did not round-trip through LoadClientLook.");
}

void TestDiagnosticContract()
{
    _ = NewCaseDirectory("diagnostic-contract");
    Assert(string.Equals((string?)Invoke(getVersion), "0.5.0", StringComparison.Ordinal),
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

void TestNoncanonicalV2Quarantine()
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
                              "\"OuterClothes\":null,\"Bag\":null,\"HealthInterface\":null}}"
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

void ValidateCanonicalFile(string path, string expectedHead, bool expectedCaptured, bool expectedHideHair)
{
    using JsonDocument document = JsonDocument.Parse(File.ReadAllText(path, Encoding.UTF8));
    JsonElement root = document.RootElement;
    string[] actualProperties = root.EnumerateObject().Select(property => property.Name).Order().ToArray();
    string[] expectedProperties = ["captured", "hideHair", "schemaVersion", "slots"];
    Array.Sort(expectedProperties, StringComparer.Ordinal);
    Assert(actualProperties.SequenceEqual(expectedProperties, StringComparer.Ordinal),
        "Schema v2 contains missing or extra top-level properties.");
    Assert(root.GetProperty("schemaVersion").GetInt32() == 2, "Schema version is not 2.");
    Assert(root.GetProperty("captured").GetBoolean() == expectedCaptured, "Captured intent mismatch.");
    Assert(root.GetProperty("hideHair").GetBoolean() == expectedHideHair, "Hide-hair intent mismatch.");

    JsonElement slots = root.GetProperty("slots");
    string[] actualSlotKeys = slots.EnumerateObject().Select(property => property.Name).Order().ToArray();
    Assert(actualSlotKeys.SequenceEqual(SlotKeys.Order(), StringComparer.Ordinal),
        "Schema v2 does not contain exactly the six canonical slots.");
    Assert(slots.GetProperty("Head").ValueKind == JsonValueKind.String &&
           slots.GetProperty("Head").GetString() == expectedHead,
        "Head slot is not persisted as a stable identifier string.");
    foreach (string key in SlotKeys.Where(key => key != "Head"))
    {
        Assert(slots.GetProperty(key).ValueKind == JsonValueKind.Null,
            key + " should be persisted as null.");
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
