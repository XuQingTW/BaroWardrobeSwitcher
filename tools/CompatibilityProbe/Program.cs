using System.Diagnostics;
using System.Reflection;
using System.Runtime.Loader;

const BindingFlags AllMembers = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static;

if (args.Length < 2)
{
    Console.Error.WriteLine("Usage: CompatibilityProbe <BarotraumaInstallDir> <LuaCsPublicizedDir> [--require-optional]");
    return 64;
}

string installDir = Path.GetFullPath(args[0]);
string publicizedDir = Path.GetFullPath(args[1]);
bool requireOptional = args.Contains("--require-optional", StringComparer.Ordinal);
var failures = new List<string>();
var optionalFailures = new List<string>();

AssemblyLoadContext.Default.Resolving += (_, assemblyName) =>
{
    foreach (string directory in new[] { publicizedDir, installDir })
    {
        string candidate = Path.Combine(directory, assemblyName.Name + ".dll");
        if (File.Exists(candidate))
        {
            return AssemblyLoadContext.Default.LoadFromAssemblyPath(candidate);
        }
    }
    return null;
};

string barotraumaPath = Path.Combine(publicizedDir, "Barotrauma.dll");
string installedAssemblyPath = Path.Combine(installDir, "Barotrauma.dll");
if (!File.Exists(barotraumaPath))
{
    Console.Error.WriteLine($"Barotrauma.dll not found: {barotraumaPath}");
    return 66;
}

Assembly game = AssemblyLoadContext.Default.LoadFromAssemblyPath(barotraumaPath);
string corePath = Path.Combine(publicizedDir, "BarotraumaCore.dll");
Assembly? gameCore = File.Exists(corePath)
    ? AssemblyLoadContext.Default.LoadFromAssemblyPath(corePath)
    : null;

Type RequireType(string fullName)
{
    Type? type = game.GetType(fullName, throwOnError: false);
    if (type is null)
    {
        failures.Add($"type missing: {fullName}");
        return typeof(void);
    }
    return type;
}

Type RequireExternalType(string assemblyFile, string fullName)
{
    string path = Path.Combine(installDir, assemblyFile);
    if (!File.Exists(path))
    {
        failures.Add($"assembly missing: {path}");
        return typeof(void);
    }
    Assembly assembly = AssemblyLoadContext.Default.LoadFromAssemblyPath(path);
    Type? type = assembly.GetType(fullName, throwOnError: false);
    if (type is null)
    {
        failures.Add($"type missing: {fullName}");
        return typeof(void);
    }
    return type;
}

MethodInfo? FindExact(Type declaringType, string name, params Type[] parameters)
    => declaringType.GetMethod(name, AllMembers, binder: null, types: parameters, modifiers: null);

void RequireConstructor(string label, Type declaringType, Type[] parameters)
{
    ConstructorInfo? constructor = declaringType.GetConstructor(
        AllMembers,
        binder: null,
        types: parameters,
        modifiers: null);
    if (constructor is null || !constructor.IsPublic)
    {
        failures.Add($"constructor mismatch: {label}");
        return;
    }
    Console.WriteLine($"PASS {label}");
}

void RequireMethod(string label, Type declaringType, string name, Type[] parameters, Type returnType, bool optional = false)
{
    MethodInfo? method = FindExact(declaringType, name, parameters);
    if (method is null || method.ReturnType != returnType)
    {
        (optional ? optionalFailures : failures).Add($"method mismatch: {label}");
        return;
    }
    Console.WriteLine($"PASS {label}");
}

void RequireProperty(string label, Type declaringType, string name)
{
    if (declaringType.GetProperty(name, AllMembers) is null)
    {
        failures.Add($"property missing: {label}");
    }
    else
    {
        Console.WriteLine($"PASS {label}");
    }
}

void RequireReadWriteProperty(string label, Type declaringType, string name)
{
    PropertyInfo? property = declaringType.GetProperty(name, AllMembers);
    if (property?.GetMethod is null ||
        property.SetMethod is null ||
        !property.GetMethod.IsPublic ||
        !property.SetMethod.IsPublic)
    {
        failures.Add($"read/write property missing: {label}");
    }
    else
    {
        Console.WriteLine($"PASS {label}");
    }
}

void RequireField(string label, Type declaringType, string name, bool optional = false)
{
    if (declaringType.GetField(name, AllMembers) is null)
    {
        (optional ? optionalFailures : failures).Add($"field missing: {label}");
    }
    else
    {
        Console.WriteLine($"PASS {label}");
    }
}

void RequirePublicField(string label, Type declaringType, string name, Type fieldType)
{
    FieldInfo? field = declaringType.GetField(name, AllMembers);
    if (field is null || !field.IsPublic || field.FieldType != fieldType)
    {
        failures.Add($"public field mismatch: {label}");
    }
    else
    {
        Console.WriteLine($"PASS {label}");
    }
}

Type limb = RequireType("Barotrauma.Limb");
Type camera = RequireType("Barotrauma.Camera");
Type wearableSprite = RequireType("Barotrauma.WearableSprite");
Type sprite = RequireType("Barotrauma.Sprite");
Type character = RequireType("Barotrauma.Character");
Type animController = RequireType("Barotrauma.AnimController");
Type statusEffect = RequireType("Barotrauma.StatusEffect");
Type animLoadInfo = RequireType("Barotrauma.StatusEffect+AnimLoadInfo");
Type entity = RequireType("Barotrauma.Entity");
Type hull = RequireType("Barotrauma.Hull");
Type itemComponent = RequireType("Barotrauma.Items.Components.ItemComponent");
Type actionType = RequireType("Barotrauma.ActionType");
Type networkClient = RequireType("Barotrauma.Networking.Client");
string monoGameFile = new[]
{
    "MonoGame.Framework.Windows.NetStandard.dll",
    "MonoGame.Framework.Linux.NetStandard.dll",
    "MonoGame.Framework.dll"
}.FirstOrDefault(file => File.Exists(Path.Combine(installDir, file))) ?? "MonoGame.Framework.dll";
Type spriteBatch = RequireExternalType(monoGameFile, "Microsoft.Xna.Framework.Graphics.SpriteBatch");
Type color = RequireExternalType("XNATypes.dll", "Microsoft.Xna.Framework.Color");
Type vector2 = RequireExternalType("XNATypes.dll", "Microsoft.Xna.Framework.Vector2");
Type spriteEffects = spriteBatch.Assembly.GetType("Microsoft.Xna.Framework.Graphics.SpriteEffects", throwOnError: true)!;

RequireMethod("Limb.Draw(SpriteBatch,Camera,Color?,bool)", limb, "Draw",
    new[] { spriteBatch, camera, typeof(Nullable<>).MakeGenericType(color), typeof(bool) }, typeof(void));
RequireMethod("Limb.DrawWearable(WearableSprite,float,SpriteBatch,Color,float,SpriteEffects)", limb, "DrawWearable",
    new[] { wearableSprite, typeof(float), spriteBatch, color, typeof(float), spriteEffects }, typeof(void));
RequireMethod("WearableSprite.Init(Character)", wearableSprite, "Init", new[] { character }, typeof(void));
RequireProperty("WearableSprite.IsInitialized", wearableSprite, "IsInitialized");
RequireReadWriteProperty("WearableSprite.Sprite", wearableSprite, "Sprite");
RequireProperty("WearableSprite.SourceElement", wearableSprite, "SourceElement");
RequireProperty("WearableSprite.CanBeHiddenByItem", wearableSprite, "CanBeHiddenByItem");
foreach (string property in new[]
         {
             "Type",
             "Limb",
             "DepthLimb",
             "Scale",
             "Rotation",
             "InheritLimbDepth",
             "InheritOrigin",
             "InheritScale",
             "InheritSourceRect",
             "IgnoreLimbScale",
             "IgnoreRagdollScale",
             "IgnoreTextureScale",
             "HideLimb",
             "HideWearablesOfType",
             "ObscureOtherWearables",
             "CanBeHiddenByOtherWearables",
             "CanBeHiddenByItem",
             "SheetIndex",
             "Sound",
             "SpritePath",
             "UnassignedSpritePath",
             "Variant",
             "Picker"
         })
{
    RequireReadWriteProperty($"WearableSprite.{property}", wearableSprite, property);
}

RequireConstructor("Sprite.Sprite(Sprite)", sprite, new[] { sprite });
RequireMethod("Sprite.Remove()", sprite, "Remove", Array.Empty<Type>(), typeof(void));
RequireMethod("WearableSprite.Remove()", wearableSprite, "Remove", Array.Empty<Type>(), typeof(void));
foreach (string property in new[] { "SourceRect", "RelativeSize", "RelativeOrigin", "Origin", "Depth" })
{
    RequireReadWriteProperty($"Sprite.{property}", sprite, property);
}
RequireProperty("Sprite.FullPath", sprite, "FullPath");
RequireProperty("Sprite.FilePath", sprite, "FilePath");
RequirePublicField("Sprite.size", sprite, "size", vector2);
RequirePublicField("Sprite.offset", sprite, "offset", vector2);
RequirePublicField("Sprite.rotation", sprite, "rotation", typeof(float));
RequirePublicField("Sprite.effects", sprite, "effects", spriteEffects);

Type? readMessage = game.GetType("Barotrauma.Networking.IReadMessage", throwOnError: false) ??
                    gameCore?.GetType("Barotrauma.Networking.IReadMessage", throwOnError: false);
if (readMessage is null)
{
    failures.Add("type missing: Barotrauma.Networking.IReadMessage");
}
else if (readMessage.GetProperty("LengthBytes", AllMembers) is null &&
         readMessage.GetProperty("LengthBits", AllMembers) is null)
{
    failures.Add("IReadMessage has neither LengthBytes nor LengthBits for the 4 KiB wire gate");
}
else
{
    Console.WriteLine("PASS IReadMessage wire-length contract");
}

RequireMethod("AnimController.UpdateAnimations(float)", animController, "UpdateAnimations",
    new[] { typeof(float) }, typeof(void), optional: true);
RequireMethod("AnimController.TryLoadTemporaryAnimation(AnimLoadInfo,bool)", animController, "TryLoadTemporaryAnimation",
    new[] { animLoadInfo, typeof(bool) }, typeof(bool), optional: true);
RequireMethod("StatusEffect.PlaySound(Entity,Hull,Vector2)", statusEffect, "PlaySound",
    new[] { entity, hull, vector2 }, typeof(void), optional: true);
RequireField("StatusEffect.propertyConditionals", statusEffect, "propertyConditionals", optional: true);
RequireField("StatusEffect.requiredItems", statusEffect, "requiredItems", optional: true);
RequireField("StatusEffect.playSoundOnRequiredItemFailure", statusEffect, "playSoundOnRequiredItemFailure", optional: true);
RequireMethod("ItemComponent.PlaySound(ActionType,Character)", itemComponent, "PlaySound",
    new[] { actionType, character }, typeof(void), optional: true);

MemberInfo? accountIdMember = networkClient.GetProperty("AccountId", AllMembers) ??
    (MemberInfo?)networkClient.GetField("AccountId", AllMembers);
if (accountIdMember is null)
{
    failures.Add("Client.AccountId missing");
}
else
{
    Type optionType = accountIdMember is PropertyInfo property ? property.PropertyType : ((FieldInfo)accountIdMember).FieldType;
    Type? accountIdType = optionType.IsGenericType ? optionType.GetGenericArguments().FirstOrDefault() : null;
    bool hasTryUnwrap = optionType.GetMethods(AllMembers).Any(method => method.Name == "TryUnwrap");
    bool hasIsSomeProperty = optionType.GetProperty("IsSome", AllMembers) is not null;
    bool hasIsSomeMethod = optionType.GetMethods(AllMembers).Any(method => method.Name == "IsSome" && method.GetParameters().Length == 0);
    bool hasRepresentation = accountIdType?.GetProperty("StringRepresentation", AllMembers) is not null;
    Console.WriteLine($"INFO AccountId option={optionType.FullName}, IsSomeProperty={hasIsSomeProperty}, IsSomeMethod={hasIsSomeMethod}, TryUnwrap={hasTryUnwrap}");
    if (!hasTryUnwrap || !hasRepresentation)
    {
        failures.Add("Client.AccountId Option/TryUnwrap/StringRepresentation contract mismatch");
    }
    else
    {
        Console.WriteLine("PASS Client.AccountId stable identity contract");
    }
}

if (File.Exists(installedAssemblyPath))
{
    string? version = FileVersionInfo.GetVersionInfo(installedAssemblyPath).FileVersion;
    if (version is null || !version.StartsWith("1.13.4.0", StringComparison.Ordinal))
    {
        failures.Add($"expected Barotrauma 1.13.4.0, found {version ?? "unknown"}");
    }
    else
    {
        Console.WriteLine($"PASS Barotrauma.dll {version}");
    }
}
else
{
    failures.Add($"game assembly missing: {installedAssemblyPath}");
}

const string RequiredLuaCsCommit = "0d380afcd1feeb842c0c86290d46bcaf198cd5e4";
string? publicizedProductVersion = FileVersionInfo.GetVersionInfo(barotraumaPath).ProductVersion;
if (publicizedProductVersion is null ||
    !publicizedProductVersion.Contains(RequiredLuaCsCommit, StringComparison.OrdinalIgnoreCase))
{
    failures.Add($"expected LuaCs publicized commit {RequiredLuaCsCommit}, found {publicizedProductVersion ?? "unknown"}");
}
else
{
    Console.WriteLine($"PASS LuaCs publicized commit {RequiredLuaCsCommit}");
}

foreach (string warning in optionalFailures)
{
    Console.WriteLine($"OPTIONAL UNAVAILABLE {warning}");
}
if (requireOptional)
{
    failures.AddRange(optionalFailures);
}

foreach (string failure in failures)
{
    Console.Error.WriteLine($"FAIL {failure}");
}

return failures.Count == 0 ? 0 : 1;
