using System.Collections;
using System.Reflection;
using System.Runtime.CompilerServices;

internal static class MovementAnimationProbe
{
    private const BindingFlags All = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static;

    public static void Run(Assembly mod)
    {
        Type renderer = mod.GetType("BaroWardrobeSwitcher.VisualOverride", true)!;
        Type sessionType = mod.GetType("BaroWardrobeSwitcher.RenderSession", true)!;
        Type characterType = sessionType.GetProperty("Character")!.PropertyType;
        Assembly game = characterType.Assembly;
        object character = RuntimeHelpers.GetUninitializedObject(characterType);
        object controller = RuntimeHelpers.GetUninitializedObject(game.GetType("Barotrauma.HumanoidAnimController", true)!);
        Field(controller.GetType(), "character").SetValue(controller, character);
        object session = Activator.CreateInstance(sessionType, [character])!;
        Set(session, "IsActive", true);
        var sessions = (IDictionary)renderer.GetField("RenderSessions", All)!.GetValue(null)!;
        var movements = (IDictionary)sessionType.GetProperty("EquipmentMovementAnimations")!.GetValue(session)!;
        Type entryType = movements.GetType().GetGenericArguments()[1];
        Type animationType = game.GetType("Barotrauma.AnimationType", true)!;
        object walk = Enum.Parse(animationType, "Walk");
        object run = Enum.Parse(animationType, "Run");
        object swim = Enum.Parse(animationType, "SwimSlow");
        object parameters = RuntimeHelpers.GetUninitializedObject(game.GetType("Barotrauma.HumanRunParams", true)!);
        Set(parameters, "AnimationType", run);
        Set(parameters, "MovementSpeed", 1.7f);
        Set(parameters, "BackwardsMovementMultiplier", 0.5f);
        object info = RuntimeHelpers.GetUninitializedObject(game.GetType("Barotrauma.StatusEffect+AnimLoadInfo", true)!);
        object suppressed = sessionType.GetProperty("SuppressedEquipmentAnimations")!.GetValue(session)!;
        suppressed.GetType().GetMethod("Add")!.Invoke(suppressed, [info]);
        movements.Add(info, Activator.CreateInstance(entryType, [parameters, 10f, 0L])!);
        MethodInfo limit = sessionType.GetMethod("LimitEquipmentMovementSpeed", All)!;
        float Speed(object type, bool backwards = false, float requested = 5f) =>
            (float)limit.Invoke(session, [type, backwards, requested])!;
        void Check(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }

        renderer.GetMethod("ResetPatchStatus")!.Invoke(null, null);
        var patches = (IDictionary)renderer.GetField("PatchStates", All)!.GetValue(null)!;
        foreach (object patch in patches.Values) Set(patch, "Applied", true);
        sessions.Add(character, session);
        try
        {
            Check(Speed(run) == 1.7f && Speed(run, true) == 0.85f, "suit forward/backward speed lost");
            Check(Speed(run, false, 0.5f) == 0.5f, "slow movement was accelerated");
            Check(Speed(walk) == 5f && Speed(swim) == 5f, "unrelated animation type was slowed");
            object lowerPriority = RuntimeHelpers.GetUninitializedObject(parameters.GetType());
            Set(lowerPriority, "AnimationType", run);
            Set(lowerPriority, "MovementSpeed", 0.2f);
            object lowerKey = new object();
            movements.Add(lowerKey, Activator.CreateInstance(entryType, [lowerPriority, 1f, 0L])!);
            Check(Speed(run) == 1.7f, "lower-priority animation replaced the suit speed");
            movements.Remove(lowerKey);
            object otherSession = Activator.CreateInstance(sessionType, [character])!;
            Check((float)limit.Invoke(otherSession, [run, false, 5f])! == 5f, "speed leaked between sessions");
            Set(session, "MovementAnimationFrame", 1L);
            Check(Speed(run) == 1.7f, "previous-frame effect was dropped before input");
            Set(session, "MovementAnimationFrame", 2L);
            Check(Speed(run) == 5f, "expired effect left a speed limit");

            MethodInfo prefix = mod.GetType("BaroWardrobeSwitcher.AnimControllerTryLoadTemporaryAnimationPatch", true)!
                .GetMethod("Prefix", All)!;
            object[] args = [controller, info, false];
            Check(!(bool)prefix.Invoke(null, args)! && (bool)args[2], "suppression reports failure to StatusEffect");
            Check(Speed(run) == 1.7f, "suppression did not refresh the speed limit");
            renderer.GetMethod("SetUseFashionMovementAnimations")!.Invoke(null, [character, false]);
            Check(Speed(run) == 5f && movements.Count == 0, "equipment mode retains cosmetic speed state");
            Check((bool)prefix.Invoke(null, args)!, "equipment mode does not resume native animation loading");
            renderer.GetMethod("SetUseFashionMovementAnimations")!.Invoke(null, [character, true]);
            Check(Speed(run) == 5f, "re-enabling fashion resurrected a stale limit");
            movements.Add(info, Activator.CreateInstance(entryType, [parameters, 10f, 2L])!);
            renderer.GetMethod("RestoreCharacterItemVisuals")!.Invoke(null, [character]);
            Check(movements.Count == 0 && (bool)prefix.Invoke(null, args)!, "clear look retains suppression");
        }
        finally
        {
            sessions.Remove(character);
            renderer.GetMethod("ResetPatchStatus")!.Invoke(null, null);
        }
    }

    private static FieldInfo Field(Type type, string name)
    {
        for (Type? current = type; current != null; current = current.BaseType)
            if (current.GetField(name, All) is FieldInfo field) return field;
        throw new MissingFieldException(type.FullName, name);
    }

    private static void Set(object target, string name, object value) =>
        target.GetType().GetProperty(name, All)!.SetValue(target, value);
}
