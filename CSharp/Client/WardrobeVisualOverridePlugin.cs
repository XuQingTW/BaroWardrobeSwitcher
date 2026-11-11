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
    // 設定名稱需和 Config 中的定義一致；新增選項也要接上預設值及 Dispose 清理。
    public sealed class WardrobeVisualOverridePlugin : IAssemblyPlugin
    {
        private Harmony harmonyInstance;

        public IConfigService ConfigService { get; set; }

        public IPluginManagementService PluginService { get; set; }

        public void Initialize()
        {
            LuaCsLogger.Log($"[Baro Wardrobe Switcher] C# visual override v{VisualOverride.Version} initializing.");
            harmonyInstance = new Harmony("BaroWardrobeSwitcher.VisualOverride");
            VisualOverride.ResetPatchStatus();
            ContentPackage package = null;
            bool hasPackage = ConfigService != null &&
                PluginService != null &&
                PluginService.TryGetPackageForPlugin<WardrobeVisualOverridePlugin>(out package);
            if (hasPackage &&
                ConfigService.TryGetConfig(package, "PanelKey", out ISettingBase<string> panelKey))
            {
                VisualOverride.SetPanelKeySetting(panelKey);
            }
            else
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] PanelKey setting unavailable; using F8.");
            }
            if (hasPackage &&
                ConfigService.TryGetConfig(package, "HideHuskVisuals", out ISettingBase<bool> hideHuskVisuals))
            {
                VisualOverride.SetHideHuskVisualsSetting(hideHuskVisuals, ConfigService);
            }
            else
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] HideHuskVisuals setting unavailable; using false.");
            }
            if (hasPackage &&
                ConfigService.TryGetConfig(package, "UnequipOnSave", out ISettingBase<bool> unequipOnSave))
            {
                VisualOverride.SetUnequipOnSaveSetting(unequipOnSave, ConfigService);
            }
            else
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] UnequipOnSave setting unavailable; using true.");
            }
            if (hasPackage &&
                ConfigService.TryGetConfig(package, "HideEmptySlotEquipment", out ISettingBase<bool> hideEmptySlotEquipment))
            {
                VisualOverride.SetHideEmptySlotEquipmentSetting(hideEmptySlotEquipment, ConfigService);
            }
            else
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] HideEmptySlotEquipment setting unavailable; using true.");
            }
            if (hasPackage &&
                ConfigService.TryGetConfig(package, "OverrideGeneSplicerAppearance", out ISettingBase<bool> overrideGeneSplicerAppearance))
            {
                VisualOverride.SetOverrideGeneSplicerAppearanceSetting(overrideGeneSplicerAppearance, ConfigService);
            }
            else
            {
                LuaCsLogger.Log("[Baro Wardrobe Switcher] OverrideGeneSplicerAppearance setting unavailable; using false.");
            }
        }

        public void OnLoadCompleted()
        {
            VisualOverride.InstallPatches(harmonyInstance);
            LuaCsLogger.Log($"[Baro Wardrobe Switcher] C# visual override loaded: {VisualOverride.GetReadinessStatus()}.");
        }

        public void PreInitPatching() { }

        public void Dispose()
        {
            VisualOverride.SetPanelKeySetting(null);
            VisualOverride.SetHideHuskVisualsSetting(null, null);
            VisualOverride.SetUnequipOnSaveSetting(null, null);
            VisualOverride.SetHideEmptySlotEquipmentSetting(null, null);
            VisualOverride.SetOverrideGeneSplicerAppearanceSetting(null, null);
            VisualOverride.ClearAll();
            harmonyInstance?.UnpatchSelf();
            LuaCsLogger.Log("[Baro Wardrobe Switcher] C# visual override disposed.");
        }
    }

}
