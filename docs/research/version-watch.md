# 版本监控与更新复核（version-watch）

> 用途：记录《深空当铺》本机构建变化、每次更新后的 API 复核结果，以及开发前的检查流程。  
> 关联：`04-技术实现与验收.md` §1.3、`06-修改确认清单-v0.3.1.md` §一.1。

---

## 1. 本机构建历史

| 采样时间 | BuildID | LastUpdated（UTC） | 本地时间（Asia/Shanghai） | 备注 |
|---|---|---|---|---|
| 2026-11-08 早 | 26496118 | — | 2026-11-07 更新 | v0.3 文档初版基线 |
| **2026-11-09 22:44** | **26525552** | 1794229600 = 2026-11-09 13:06:40Z | **2026-11-09 21:06:40** | 本次复核；`Probably Stolen.exe`/`Assembly-CSharp.dll` 时间戳 2026-11-09 21:06:38 |

**取证**：
- `D:\SteamLibrary\steamapps\appmanifest_4348910.acf`：`buildid=26525552`、`LastUpdated=1794229600`、`StateFlags=4`。
- `Assembly-CSharp.dll`：4,820,224 字节（上次 4,752,136）；类型 **949**（上次 946）。

---

## 2. 本次 API 复核结果（26525552）

| 项 | 结果 |
|---|---|
| `ModLoader` | ✅ 81 个方法 |
| `ModHook` | ✅ 142 个方法；`OnGenerateCustomer*`、`OnGoingSleep*`、`OnWakingUp*`、`OnHandlingNightlyServices*`、`OnShutter*`、`OnAfterhour*` 均在 |
| `ModHelper` | ✅ **165** 个方法（上次 143）；`AddStartingPerk`、`AddNetworkUpgrade`、`SetModData`、`GetModData` 在 |
| `StoreReputation` | ✅ 43 个方法；❌ **无 `AddFaction`/`CreateFaction`** |
| `ReputationUIManager` | ✅ 存在（固定列表，需 patch 扩展） |
| `HusbandryHelper.InitAnimalSurgeryTool` | ✅ 存在（动物手术工具） |
| `AugHelper` / `AugScanner` / `ContrabandHelper` / `SecData` / `StoreClientManager` | ✅ 均在 |
| `PerkDirectory.RegisterModUpgrade` | ✅ 存在 |
| `QFSW.QC` / `DevMode` / `mod-scan` | ✅ 仍在 |

**结论**：旧文档依赖的关键 API 未缺失；`ModHelper` 新增 20+ 方法，后续可排查是否有更省事的派系/UI/存档辅助。

---

## 3. 开发前检查流程

每次开始开发/打包前：

1. **读构建号**：
   ```powershell
   Get-Content 'D:\SteamLibrary\steamapps\appmanifest_4348910.acf' |
     Select-String 'buildid|LastUpdated'
   ```
2. **对比**：若与本文记录不同，记录新 BuildID/时间，继续 3–6。
3. **重导符号**：用 Mono.Cecil 读取 `Probably Stolen_Data\Managed\Assembly-CSharp.dll`，确认关键类型/方法仍在；输出到 `docs/research/_api_signatures_<build>.txt`。
4. **检查新增/移除**：重点 `ModHelper`、`ModHook`、`StoreReputation`、`ReputationUIManager`、`FactionStatusList`、`HusbandryHelper`。
5. **mod-scan**：游戏内运行 `mod-scan`，确认 manifest 能力声明无未声明项。
6. **冒烟测试**：加载 Mod → 开局 → 闭店 → "改造体行动中" → 保存/读档 → 确认无报错。

> `manifest.xml` 的 `GameVersions` 使用范围（如 `1.0.x`），不写死 BuildID；BuildID 仅用于文档与排查。

---

## 4. 版本口径冲突（外部资料）

| 来源 | 口径 |
|---|---|
| 本机 appmanifest | BuildID 26525552（2026-11-09） |
| BWIKI | "正式版 1.0" |
| 生态文档 | "0.46D / ModLoader 100-Rev1" |
| MCP Bridge | "100-REV6 / 0.46D" |

**处理**：以本机 appmanifest 为准；外部口径仅作参考。若后续游戏更新导致 API 变化，按 §3 复验并回填本文。

---

## 5. 下次检查

- 建议每次启动游戏/Steam 更新后检查一次；
- 若 BuildID 变化，在本文追加一行，并重跑 §3；
- 若关键 API 缺失，暂停打包，先修兼容层。
