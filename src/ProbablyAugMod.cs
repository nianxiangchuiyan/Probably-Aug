using System;
using UnityEngine;

namespace ProbablyAug
{
    /// <summary>
    /// 零号改造体 Mod 的基础框架（原型）。
    /// 只使用官方 IMod / ModHook / ModHelper / ModData，不使用 Harmony、反射或运行时生成代码，
    /// 因此 manifest 的 Capabilities 保持为空。
    /// </summary>
    public class ProbablyAugMod : global::IMod
    {
        public const string ModId = "ProbablyAug";

        public static ProbablyAugMod Instance;

        public global::ModManifest Manifest;

        // 基础状态（数值后续再调）
        public int Power = 100;
        public int PowerMax = 100;
        public int AugRep = 0;
        public int Alertness = 0;
        public bool AlertnessActive = false;

        // 闭店状态：用于“改造体行动中”入口
        public bool ShopClosed = false;

        private GameObject hudObject;
        private AugHud hud;

        public void Init(global::ModManifest manifest)
        {
            Manifest = manifest;
            Instance = this;
        }

        public void OnEnable()
        {
            Instance = this;

            global::ModHook.OnGameLoadedInit += OnGameLoadedInit;
            global::ModHook.OnNewGameStarted += OnNewGameStarted;
            global::ModHook.OnWakingUpLate += OnWakingUpLate;
            global::ModHook.OnGoingSleepLate += OnGoingSleepLate;
            global::ModHook.OnShutterClosedLate += OnShutterClosedLate;
            global::ModHook.OnShutterOpenedLate += OnShutterOpenedLate;

            LoadState();
            CreateHud();
            RegisterDebugFunctions();

            UnityEngine.Debug.Log("[ProbablyAug] enabled");
        }

        public void OnDisable()
        {
            SaveState();

            global::ModHook.OnGameLoadedInit -= OnGameLoadedInit;
            global::ModHook.OnNewGameStarted -= OnNewGameStarted;
            global::ModHook.OnWakingUpLate -= OnWakingUpLate;
            global::ModHook.OnGoingSleepLate -= OnGoingSleepLate;
            global::ModHook.OnShutterClosedLate -= OnShutterClosedLate;
            global::ModHook.OnShutterOpenedLate -= OnShutterOpenedLate;

            if (hudObject != null)
            {
                UnityEngine.Object.Destroy(hudObject);
                hudObject = null;
                hud = null;
            }

            try { global::ModHelper.RemoveDebugFunctions(ModId); }
            catch { }

            UnityEngine.Debug.Log("[ProbablyAug] disabled");
        }

        private void OnGameLoadedInit()
        {
            LoadState();
            if (hud != null) hud.Refresh();
        }

        private void OnNewGameStarted(string saveId)
        {
            ResetState();
            SaveState();
            if (hud != null) hud.Refresh();
            UnityEngine.Debug.Log("[ProbablyAug] new game state initialized");
        }

        private void OnWakingUpLate()
        {
            // 每夜基础消耗：先做最小闭环，数值后续再调
            Power = Math.Max(0, Power - 5);
            if (Power <= 0)
            {
                Power = 0;
            }
            SaveState();
            if (hud != null) hud.Flash("新的一天：电量 -5 kJ");
        }

        private void OnGoingSleepLate()
        {
            SaveState();
        }

        private void OnShutterClosedLate()
        {
            ShopClosed = true;
            if (hud != null) hud.Refresh();
        }

        private void OnShutterOpenedLate()
        {
            ShopClosed = false;
            if (hud != null) hud.Refresh();
        }

        public void ResetState()
        {
            Power = PowerMax;
            AugRep = 0;
            Alertness = 0;
            AlertnessActive = false;
            ShopClosed = false;
        }

        public void AddPower(int amount)
        {
            Power = Math.Max(0, Math.Min(PowerMax, Power + amount));
            SaveState();
        }

        public void AddRep(int amount)
        {
            AugRep = Math.Max(-100, Math.Min(100, AugRep + amount));
            SaveState();
        }

        public void AddAlertness(int amount)
        {
            Alertness = Math.Max(0, Math.Min(100, Alertness + amount));
            if (Alertness > 0) AlertnessActive = true;
            SaveState();
        }

        public void SaveState()
        {
            try
            {
                global::ModHelper.SetModDataInt(ModId, "power", Power);
                global::ModHelper.SetModDataInt(ModId, "power_max", PowerMax);
                global::ModHelper.SetModDataInt(ModId, "aug_rep", AugRep);
                global::ModHelper.SetModDataInt(ModId, "alertness", Alertness);
                global::ModHelper.SetModDataBool(ModId, "alertness_active", AlertnessActive);
            }
            catch (Exception e)
            {
                UnityEngine.Debug.LogWarning("[ProbablyAug] save failed: " + e.Message);
            }
        }

        public void LoadState()
        {
            try
            {
                PowerMax = global::ModHelper.GetModDataInt(ModId, "power_max", 100);
                if (PowerMax <= 0) PowerMax = 100;
                Power = global::ModHelper.GetModDataInt(ModId, "power", PowerMax);
                AugRep = global::ModHelper.GetModDataInt(ModId, "aug_rep", 0);
                Alertness = global::ModHelper.GetModDataInt(ModId, "alertness", 0);
                AlertnessActive = global::ModHelper.GetModDataBool(ModId, "alertness_active", false);
            }
            catch (Exception e)
            {
                UnityEngine.Debug.LogWarning("[ProbablyAug] load failed: " + e.Message);
                ResetState();
            }
        }

        private void CreateHud()
        {
            if (hudObject != null) return;
            hudObject = new GameObject("ProbablyAug_HUD");
            UnityEngine.Object.DontDestroyOnLoad(hudObject);
            hud = hudObject.AddComponent<AugHud>();
            hud.Mod = this;
        }

        private void RegisterDebugFunctions()
        {
            try
            {
                global::ModHelper.AddDebugFunction(ModId, "零号改造体", "电量 +10", delegate
                {
                    AddPower(10);
                    if (hud != null) hud.Flash("电量 +10");
                }, false);

                global::ModHelper.AddDebugFunction(ModId, "零号改造体", "声望 +5", delegate
                {
                    AddRep(5);
                    if (hud != null) hud.Flash("改造体声望 +5");
                }, false);

                global::ModHelper.AddDebugFunction(ModId, "零号改造体", "警觉 +5", delegate
                {
                    AddAlertness(5);
                    if (hud != null) hud.Flash("警觉度 +5");
                }, false);

                global::ModHelper.AddDebugFunction(ModId, "零号改造体", "重置基础状态", delegate
                {
                    ResetState();
                    SaveState();
                    if (hud != null) hud.Flash("基础状态已重置");
                }, false);
            }
            catch (Exception e)
            {
                UnityEngine.Debug.LogWarning("[ProbablyAug] debug functions failed: " + e.Message);
            }
        }
    }
}
