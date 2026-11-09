# 基础 Mod 框架说明 v0.1.0

> 日期：2026-11-10  
> 游戏：Probably Stolen（本机 BuildID 26525552）  
> 代码位置：仓库根目录 `manifest.xml` + `ProbablyAug.dll` + `src/`  
> 设计依据：`01-设计文档-v0.3.md`（v0.3.1）  
> 目标：先把 **可加载、可存档、可见 UI** 的基础闭环跑通；数值、研究、机器、任务内容后续再做。

---

## 1. 当前已完成

| 功能 | 状态 | 说明 |
|---|---|---|
| Mod 加载 | ✅ | `IMod`（`Init/OnEnable/OnDisable`），官方加载器 |
| manifest | ✅ | `Capabilities` 为空；`Assemblies` 指向 `ProbablyAug.dll` |
| 状态持久化 | ✅ | `ModHelper.SetModData*/GetModData*`：电量、上限、声望、警觉、激活标记 |
| 每夜基础消耗 | ✅ | `ModHook.OnWakingUpLate`：电量 −5 kJ（占位数值） |
| 读档/新档 | ✅ | `OnGameLoadedInit` 恢复；`OnNewGameStarted` 重置 |
| 闭店状态 | ✅ | `OnShutterClosedLate` / `OnShutterOpenedLate` |
| 原型 HUD | ✅ | `OnGUI` 左上角：电量/声望/警觉；F8 显示/隐藏 |
| “改造体行动中”面板 | ✅（原型） | 闭店后 HUD 按钮；竖排绿/黄/红进度条 + 数字；Esc 关闭 |
| 调试命令 | ✅ | 游戏控制台：电量 +10、声望 +5、警觉 +5、重置 |
| 无 Harmony/反射 | ✅ | 依赖检查无 `0Harmony`、无 `System.Reflection` 调用 |

> UI 目前是 **OnGUI 原型**，按钮还在 HUD 上；“门右侧到柜台左侧”的场景锚点、原版 UI 风格后续替换。

---

## 2. 文件结构

```
Probably-Aug/
  manifest.xml                 # Mod 清单（ID=ProbablyAug）
  ProbablyAug.dll              # 构建产物（游戏加载）
  build.ps1                    # 构建脚本（dotnet / netstandard2.1）
  src/
    ProbablyAug.csproj         # netstandard2.1，引用游戏 Managed 程序集
    ProbablyAugMod.cs          # IMod 入口、状态、ModData、事件、调试命令
    AugHud.cs                  # OnGUI HUD 与“改造体行动中”原型面板
  docs/
    07-基础Mod框架.md          # 本文
```

---

## 3. 构建

前置：.NET SDK 8+（本机已有 8.0.405 / 9.0.305）。  
脚本会自动从 `%USERPROFILE%\.probably-aug\config.json` 读取游戏目录，失败时再按脚本目录/父目录查找：

```powershell
cd C:\Users\16706\Probably-Aug
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

也可以显式指定：

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1 -GameDir "D:\SteamLibrary\steamapps\common\Probably Stolen"
```

输出：仓库根目录 `ProbablyAug.dll`（`netstandard2.1`，引用 `Assembly-CSharp` 与 Unity 模块；不复制到游戏目录，仓库本身通过 `Mods\Probably-Aug` junction 被游戏读取）。

---

## 4. 启用与测试

1. 游戏内 **Mod 管理器**启用 `零号改造体（基础框架）`；
2. 重启游戏（或让 Mod 重载）；
3. 载入存档或新开档；
4. 按 **F8** 显示/隐藏 HUD；
5. 正常营业到闭店（卷帘门关闭），HUD 出现“改造体行动中”按钮；点击打开竖排进度条面板；
6. 过夜后电量应 −5；读档后数值保留；
7. 调试命令：打开游戏控制台，找“零号改造体”分类下的电量/声望/警觉/重置。

**当前预期结果**：
- 左上角显示 `电量 100/100`、`改造体声望 0`、`警觉度 0（未激活）`；
- 闭店后按钮出现；
- 面板竖排条随调试按钮变化；
- 退出/读档后数值不丢。

---

## 5. 当前边界

- 没有开局特质、身份状态机、派系栏、植入物、机器、感染、夜间指令、任务/剧情；
- 数值是占位（电量 −5/夜、上限 100），等基础框架稳定后再调；
- HUD 是 OnGUI，不是原版 UGUI/PaperUI，也不在门/柜台场景锚点；
- 没有 Harmony/反射，因此也**没有**新增派系、替换 UI、patch 原版方法；
- 没有本地化/中文 key，文本直接写在代码里；
- 未做多人/联机兼容。

---

## 6. 为什么先不做派系/机器/数值

你的两个工坊 Mod 已证明派系栏可扩展，但实现是 Harmony + 反射：
- `3830995342`（深空罗德岛）用 `HarmonyLib.AccessTools`/反射操作 `List<StoreReputation>`，插入新 `StoreReputation`；
- `3833223505`（声望面板滚动）用 `Harmony.PatchAll` 改 `ReputationUIManager`。

两者 manifest 的 `<Capabilities />` 都是空的，但 **2026-11-09 游戏更新已把“反射/运行时生成代码”列入淘汰名单，2026-12-10 起可能拒绝带这些声明的 Mod**。所以基础框架先走纯官方 API；派系/机器等第二阶段再做，并保留回退方案。

---

## 7. 下一阶段建议

1. **开局特质 + 身份状态机**：`ModHelper.AddStartingPerk`（含 `incompatiblePerks` 与“改造体危机”互斥）；
2. **“改造体行动中”场景按钮**：从 HUD 原型替换为门右侧/柜台左侧的场景锚点；
3. **派系栏扩展验证**：参考 `3830995342`，先做独立测试分支，评估能力声明与后续兼容；
4. **现有 2×2 机器换皮 + 基础配方**：按 01 §5.2；
5. **植入物/销售/感染**：等基础 UI 与状态稳定后接入；
6. **数值/研究/任务内容**：最后再做。

---

## 8. 版本与能力

- 游戏 build：**26525552**（2026-11-09 21:06）；
- 目标框架：`netstandard2.1`；
- `manifest.xml`：`Capabilities` 空；无 Prerequisites；`GameVersions` 空（用范围策略，不写死 build）；
- 依赖检查：`ProbablyAug.dll` 仅引用 `netstandard`、`Assembly-CSharp`、`UnityEngine.CoreModule/IMGUIModule/InputLegacyModule/TextRenderingModule`，无 `0Harmony`、无 `System.Reflection` 调用；
- 更新游戏后：按 `research/version-watch.md` 复验。
