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
    /// <summary>
    /// Keeps routine wardrobe diagnostics out of the in-game console while retaining
    /// them in a dedicated UTF-8 log beside the saved wardrobe data.
    /// </summary>
    public static class WardrobeFileLogger
    {
        private const string LogFileName = "WardrobeClient.log";
        private static readonly object SyncRoot = new object();

        public static string GetPath()
        {
            return Path.Combine(WardrobePersistence.GetStorageDirectory(), LogFileName);
        }

        public static bool Write(string level, string message)
        {
            try
            {
                string path = GetPath();
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                string line =
                    "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] " +
                    "[" + (string.IsNullOrWhiteSpace(level) ? "INFO" : level) + "] " +
                    (message ?? string.Empty) + Environment.NewLine;
                lock (SyncRoot)
                {
                    File.AppendAllText(path, line, Encoding.UTF8);
                }
                return true;
            }
            catch
            {
                // Logging must never interrupt rendering, persistence or shutdown.
                return false;
            }
        }

        public static void Log(string message) => Write("INFO", message);

    }

}
