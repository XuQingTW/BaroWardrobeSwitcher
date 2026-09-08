using System.Collections;
using System.Reflection;
using System.Runtime.CompilerServices;

// Exercise the real render transaction without creating a window, textures, or world items.
internal static class RendererMaskProbe
{
    private const BindingFlags All = BindingFlags.Public | BindingFlags.NonPublic |
                                     BindingFlags.Instance | BindingFlags.Static;

    public static void Run(Assembly mod)
    {
        Type renderer = mod.GetType("BaroWardrobeSwitcher.VisualOverride", true)!;
        Type sessionType = mod.GetType("BaroWardrobeSwitcher.RenderSession", true)!;
        Type transactionType = renderer.GetNestedType("LimbRenderTransaction", All)!;
        Type characterType = sessionType.GetProperty("Character")!.PropertyType;
        Assembly game = characterType.Assembly;
        Type limbType = game.GetType("Barotrauma.Limb", true)!;
        Type spriteType = game.GetType("Barotrauma.WearableSprite", true)!;
        Type descriptorType = mod.GetType("BaroWardrobeSwitcher.FashionSpriteDescriptor", true)!;
        Type wearableType = game.GetType("Barotrauma.Items.Components.Wearable", true)!;
        Type slotType = wearableType.GetProperty("AllowedSlots")!.PropertyType.GetGenericArguments()[0];
        Type attachmentType = spriteType.GetProperty("Type")!.PropertyType;
        object outerSlot = Enum.Parse(slotType, "OuterClothes");
        object innerSlot = Enum.Parse(slotType, "InnerClothes");
        object hair = Enum.Parse(attachmentType, "Hair");
        object beard = Enum.Parse(attachmentType, "Beard");
        var sessions = (IDictionary)renderer.GetField("RenderSessions", All)!.GetValue(null)!;
        MethodInfo setHidden = renderer.GetMethod("SetHideEmptySlotEquipment")!;
        bool previous = (bool)renderer.GetMethod("GetHideEmptySlotEquipment")!.Invoke(null, null)!;
        try
        {
            foreach (var scenario in new[]
            {
                (Hide: false, Saved: false, Forced: false, ShowHair: false, Preserve: true),
                (Hide: false, Saved: false, Forced: false, ShowHair: true, Preserve: true),
                (Hide: true, Saved: false, Forced: false, ShowHair: false, Preserve: false),
                (Hide: false, Saved: true, Forced: false, ShowHair: false, Preserve: false),
                (Hide: true, Saved: true, Forced: false, ShowHair: false, Preserve: false),
                (Hide: false, Saved: false, Forced: true, ShowHair: false, Preserve: false)
            })
            foreach (string limbName in new[] { "LeftHand", "RightHand", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot" })
            foreach (bool fashionHidesLimb in new[] { false, true })
            {
                setHidden.Invoke(null, [scenario.Hide]);
                object character = RuntimeHelpers.GetUninitializedObject(characterType);
                object session = Activator.CreateInstance(sessionType, [character])!;
                object emptySlots = sessionType.GetProperty("EmptySlots")!.GetValue(session)!;
                emptySlots.GetType().GetMethod("Add")!.Invoke(emptySlots, [outerSlot]);
                object savedSlots = sessionType.GetProperty("SavedSlots")!.GetValue(session)!;
                savedSlots.GetType().GetMethod("Add")!.Invoke(savedSlots, [innerSlot]);
                Set(session, "ForceHideEmptySlots", scenario.Forced);
                Set(session, "ForceShowAttachmentMask", scenario.ShowHair ? 1 : 0);
                sessions.Add(character, session);
                object wearable = RuntimeHelpers.GetUninitializedObject(wearableType);
                var allowedSlots = (IList)Activator.CreateInstance(wearableType.GetProperty("AllowedSlots")!.PropertyType)!;
                allowedSlots.Add(scenario.Saved ? innerSlot : outerSlot);
                Field(wearableType, "allowedSlots").SetValue(wearable, allowedSlots);
                object sprite = RuntimeHelpers.GetUninitializedObject(spriteType);
                Field(spriteType, "_wearableComponent").SetValue(sprite, wearable);
                Set(sprite, "Type", Enum.Parse(attachmentType, "Item"));
                Set(sprite, "HideLimb", true);
                Set(sprite, "ObscureOtherWearables", Enum.Parse(
                    spriteType.GetProperty("ObscureOtherWearables")!.PropertyType, "Hide"));
                var hiddenTypes = (IList)Activator.CreateInstance(spriteType.GetProperty("HideWearablesOfType")!.PropertyType)!;
                hiddenTypes.Add(hair);
                hiddenTypes.Add(beard);
                Set(sprite, "HideWearablesOfType", hiddenTypes);
                object limb = RuntimeHelpers.GetUninitializedObject(limbType);
                Field(limbType, "character").SetValue(limb, character);
                FieldInfo limbKind = Field(limbType, "type");
                object kind = Enum.Parse(limbKind.FieldType, limbName);
                limbKind.SetValue(limb, kind);
                foreach (string fieldName in new[] { "WearingItems", "OtherWearables", "wearableTypeHidingSprites", "wearableTypesToHide" })
                {
                    FieldInfo field = Field(limbType, fieldName);
                    field.SetValue(limb, Activator.CreateInstance(field.FieldType));
                }
                ((IList)Field(limbType, "WearingItems").GetValue(limb)!).Add(sprite);
                // Preload a descriptor into the limb cache/list to exercise the mask
                // transaction without loading a texture or opening a graphics device.
                object fashion = RuntimeHelpers.GetUninitializedObject(spriteType);
                Set(fashion, "Type", Enum.Parse(attachmentType, "Item"));
                Set(fashion, "Limb", kind);
                Set(fashion, "HideLimb", fashionHidesLimb);
                Set(fashion, "HideWearablesOfType", Activator.CreateInstance(hiddenTypes.GetType())!);
                var fashionSlots = (IList)Activator.CreateInstance(allowedSlots.GetType())!;
                fashionSlots.Add(innerSlot);
                object descriptor = Activator.CreateInstance(descriptorType, All, null,
                    [fashion, fashionSlots, "probe", "probe", "probe.png"], null)!;
                ((IDictionary)Field(sessionType, "descriptorsBySprite").GetValue(session)!).Add(fashion, descriptor);
                var cacheByLimb = (IDictionary)sessionType.GetProperty("FashionSpritesByLimb")!.GetValue(session)!;
                var descriptors = (IList)Activator.CreateInstance(typeof(List<>).MakeGenericType(descriptorType))!;
                descriptors.Add(descriptor);
                cacheByLimb.Add(kind, descriptors);
                ((IList)Field(limbType, "WearingItems").GetValue(limb)!).Add(fashion);
                limbType.GetMethod("UpdateWearableTypesToHide", All)!.Invoke(limb, null);
                object transaction = Activator.CreateInstance(transactionType, [limb])!;
                try
                {
                    transactionType.GetMethod("Begin")!.Invoke(transaction, [session]);
                    Check((bool)spriteType.GetProperty("HideLimb")!.GetValue(sprite)! == scenario.Preserve,
                        "visible empty-slot equipment lost its body mask: " + scenario);
                    var during = (IList)spriteType.GetProperty("HideWearablesOfType")!.GetValue(sprite)!;
                    Check(during.Contains(hair) == (scenario.Preserve && !scenario.ShowHair),
                        "hair hiding did not follow native mask/explicit Show: " + scenario);
                    Check(during.Contains(beard) == scenario.Preserve,
                        "unrelated beard mask was changed: " + scenario);
                    Check((bool)spriteType.GetProperty("HideLimb")!.GetValue(fashion)! == fashionHidesLimb,
                        $"real equipment changed saved fashion body mask: {limbName}, {scenario}");
                    MethodInfo occludes = renderer.GetMethod("ShouldHideFashionBehindVisibleEquipment", All)!;
                    Check((bool)occludes.Invoke(null, [limb])! == scenario.Preserve,
                        "fashion occlusion did not follow visible equipment: " + scenario);
                    var items = (IList)Field(limbType, "WearingItems").GetValue(limb)!;
                    items.Remove(sprite);
                    Check(!(bool)occludes.Invoke(null, [limb])!, "removed equipment still hides fashion");
                    items.Insert(0, sprite);
                }
                finally
                {
                    transactionType.GetMethod("Cleanup")!.Invoke(transaction, null);
                    sessions.Remove(character);
                }
                Check(ReferenceEquals(spriteType.GetProperty("HideWearablesOfType")!.GetValue(sprite), hiddenTypes) &&
                      (bool)spriteType.GetProperty("HideLimb")!.GetValue(sprite)!, "cleanup did not restore original masks");
                Check((bool)spriteType.GetProperty("HideLimb")!.GetValue(fashion)! == fashionHidesLimb,
                    "cleanup changed the saved fashion body mask");
                object cache = Field(limbType, "wearableTypesToHide").GetValue(limb)!;
                Check((bool)cache.GetType().GetMethod("Contains")!.Invoke(cache, [hair])!,
                    "cleanup did not restore the native hair hide cache");
            }
        }
        finally { setHidden.Invoke(null, [previous]); }
    }

    private static FieldInfo Field(Type type, string name)
    {
        for (Type? current = type; current != null; current = current.BaseType)
            if (current.GetField(name, All) is FieldInfo field) return field;
        throw new MissingFieldException(type.FullName, name);
    }

    private static void Set(object target, string name, object value) =>
        target.GetType().GetProperty(name, All)!.SetValue(target, value);

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
