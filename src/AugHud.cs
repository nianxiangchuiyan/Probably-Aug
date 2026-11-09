using System;
using UnityEngine;

namespace ProbablyAug
{
    /// <summary>
    /// 原型 HUD/面板：先用 OnGUI 验证状态与交互，后续替换为原版 UI/场景内按钮。
    /// </summary>
    public class AugHud : MonoBehaviour
    {
        public ProbablyAugMod Mod;

        private bool showHud = true;
        private bool showPanel = false;
        private string message = "";
        private float messageUntil = 0f;
        private static Texture2D white;
        private static Font cjkFont;
        private static bool fontTried;

        private void Awake()
        {
            if (white == null)
            {
                white = new Texture2D(1, 1);
                white.SetPixel(0, 0, Color.white);
                white.Apply();
            }
            if (!fontTried)
            {
                fontTried = true;
                try { cjkFont = Font.CreateDynamicFontFromOSFont(new string[] { "Microsoft YaHei", "SimHei", "Arial" }, 14); }
                catch { cjkFont = null; }
            }
        }

        private void Update()
        {
            if (Input.GetKeyDown(KeyCode.F8)) showHud = !showHud;
            if (Input.GetKeyDown(KeyCode.Escape)) showPanel = false;
        }

        public void Refresh()
        {
        }

        public void Flash(string text)
        {
            message = text;
            messageUntil = Time.time + 3f;
        }

        private void OnGUI()
        {
            if (white == null)
            {
                white = new Texture2D(1, 1);
                white.SetPixel(0, 0, Color.white);
                white.Apply();
            }

            if (cjkFont != null) GUI.skin.font = cjkFont;

            if (!showHud) return;

            GUI.Box(new Rect(12f, 12f, 270f, 172f), "零号改造体 · 基础框架");
            GUI.Label(new Rect(24f, 40f, 240f, 20f), "电量：" + Mod.Power + " / " + Mod.PowerMax + " kJ");
            GUI.Label(new Rect(24f, 62f, 240f, 20f), "改造体声望：" + Mod.AugRep);
            GUI.Label(new Rect(24f, 84f, 240f, 20f), "警觉度：" + Mod.Alertness + (Mod.AlertnessActive ? "" : "（未激活）"));
            GUI.Label(new Rect(24f, 106f, 240f, 20f), "距离下次闭店结算：夜间自动 -5 kJ");

            if (Mod.ShopClosed)
            {
                if (GUI.Button(new Rect(24f, 130f, 150f, 26f), "改造体行动中"))
                {
                    showPanel = true;
                }
            }
            else
            {
                GUI.Label(new Rect(24f, 132f, 240f, 20f), "闭店后可打开行动面板");
            }

            GUI.Label(new Rect(24f, 158f, 240f, 18f), "F8 显示/隐藏 · Esc 关闭面板");

            if (message != "" && Time.time < messageUntil)
            {
                GUI.Box(new Rect(12f, 190f, 270f, 26f), message);
            }

            if (showPanel && Mod.ShopClosed)
            {
                DrawActionPanel();
            }
        }

        private void DrawActionPanel()
        {
            float px = Mathf.Max(12f, Screen.width - 380f);
            Rect panel = new Rect(px, 80f, 360f, 450f);
            GUI.Box(panel, "改造体行动中");

            // 三条竖排进度条
            DrawBar(new Rect(panel.x + 28f, panel.y + 40f, 42f, 190f), Mod.Power / (float)Mod.PowerMax, false,
                "电量\n" + Mod.Power + "/" + Mod.PowerMax);
            DrawBar(new Rect(panel.x + 118f, panel.y + 40f, 42f, 190f), (Mod.AugRep + 100f) / 200f, false,
                "声望\n" + Mod.AugRep);
            DrawBar(new Rect(panel.x + 208f, panel.y + 40f, 42f, 190f), Mod.Alertness / 100f, true,
                "警觉\n" + Mod.Alertness);

            GUI.Label(new Rect(panel.x + 28f, panel.y + 245f, 300f, 20f), "网络状态：HIDDEN 0 / TASKED 0 / AUTONOMOUS 0（占位）");
            GUI.Label(new Rect(panel.x + 28f, panel.y + 268f, 300f, 20f), "夜间指令、感染、派系等后续接入");

            if (GUI.Button(new Rect(panel.x + 20f, panel.y + 305f, 100f, 28f), "电量 +10"))
            {
                Mod.AddPower(10);
                Flash("电量 +10");
            }
            if (GUI.Button(new Rect(panel.x + 128f, panel.y + 305f, 100f, 28f), "声望 +5"))
            {
                Mod.AddRep(5);
                Flash("改造体声望 +5");
            }
            if (GUI.Button(new Rect(panel.x + 236f, panel.y + 305f, 100f, 28f), "警觉 +5"))
            {
                Mod.AddAlertness(5);
                Flash("警觉度 +5");
            }
            if (GUI.Button(new Rect(panel.x + 20f, panel.y + 345f, 100f, 28f), "重置状态"))
            {
                Mod.ResetState();
                Mod.SaveState();
                Flash("基础状态已重置");
            }
            if (GUI.Button(new Rect(panel.x + 128f, panel.y + 345f, 208f, 28f), "关闭"))
            {
                showPanel = false;
            }

            GUI.Label(new Rect(panel.x + 20f, panel.y + 390f, 320f, 40f),
                "数值为原型占位；后续替换为原版场景按钮与正式进度条。");
        }

        private void DrawBar(Rect rect, float ratio, bool invert, string label)
        {
            ratio = Mathf.Clamp01(ratio);

            GUI.color = new Color(0.12f, 0.12f, 0.12f, 0.92f);
            GUI.DrawTexture(rect, white);

            Color fill;
            if (invert)
            {
                fill = ratio >= 0.6f ? new Color(0.85f, 0.2f, 0.2f) :
                       ratio >= 0.3f ? new Color(0.9f, 0.75f, 0.15f) :
                       new Color(0.2f, 0.75f, 0.3f);
            }
            else
            {
                fill = ratio >= 0.6f ? new Color(0.2f, 0.75f, 0.3f) :
                       ratio >= 0.3f ? new Color(0.9f, 0.75f, 0.15f) :
                       new Color(0.85f, 0.2f, 0.2f);
            }

            GUI.color = fill;
            GUI.DrawTexture(new Rect(rect.x, rect.y + rect.height * (1f - ratio), rect.width, rect.height * ratio), white);
            GUI.color = Color.white;

            GUI.Label(new Rect(rect.x - 8f, rect.y + rect.height + 4f, 66f, 40f), label);
        }
    }
}
