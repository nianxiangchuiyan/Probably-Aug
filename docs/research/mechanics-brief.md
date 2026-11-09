# 《深空当铺》"零号改造体"Mod — 机制事实与 Mod 可行性调研简报

> 用途：为 v0.3 详细策划提供事实依据（只做事实与可行性，不含剧情/任务线设计）。
> 编写：researcher（子代理）｜ 采样时间：2026-11-08 21:xx（Asia/Shanghai）
> 覆盖面：游戏内机制事实（A）+ Mod 技术栈与 API（B）+ 代码级 Hook 清单。

---

## 0. 本机安装与版本事实（先看这一节）

| 项目 | 事实 | 证据 |
| --- | --- | --- |
| 安装路径 | `D:\SteamLibrary\steamapps\common\Probably Stolen` | 本机目录 |
| Steam AppID / BuildID | `4348910` / **26525552**（2026-11-09 21:06 更新；本文初稿采样时为 26496118 / 2026-11-07） | `steamapps\appmanifest_4348910.acf`；更新复核见 `version-watch.md` |
| 最后更新 | 2026-11-07（`LastUpdated`=1794007125，UTC） | 同上 |
| 引擎/运行时 | **Unity Mono，不是 IL2CPP**：存在 `MonoBleedingEdge\`、`Probably Stolen_Data\Managed\`（161 个 dll），**无 `il2cpp_data`** | 本机目录取证 |
| Mod 前置 | **不需要 MelonLoader / BepInEx**。游戏自带 `ModLoader` 类与 `0Harmony.dll`(2.4.2)。`Mods\<ModID>\manifest.xml` + DLL，游戏内 Mod 页启用 | 【A】`Assembly-CSharp.dll` 反编译 + `Mods` 目录 |
| 开发辅助 | 游戏内含 `QFSW.QC`（Quantum Console）、`DseCecil`、`Unity.Burst.Cecil`、`SingularityGroup.HotReload` | `ScriptingAssemblies.json` / Managed |
| 当前 Mods 内容 | 仅 `Mods\Probably-Aug`（junction 到 `C:\Users\16706\Probably-Aug`，只有同步脚本与 README，**暂无 Mod 代码**） | 本机目录 + `git log` |
| 版本口径冲突（需确认） | BWIKI 标注"正式版 1.0 / 2026-11-07 更新"；生态文档标注"0.46D，ModLoader 100-Rev1"；MCP Bridge 标注"标题版本 100-REV6，内部版本 0.46D" | 三方来源不一致，见 §5 |

**更正**：任务书中"MelonLoader（IL2CPP）"的假设不成立。本作是 Mono 构建，Harmony patch 直接可用；MelonLoader 至多是"可选的第三方加载器"，**不是必需前置**。

---

## 1. 调研方法与可信度说明

**证据等级**（下表逐条标注）：

- **【A】源码证实**：从本机 `Assembly-CSharp.dll` 用 Mono.Cecil 读出的类型/方法/字段签名，或 `manifest.xml`、`.csproj`、`appmanifest` 原文。
- **【B】官方/代码整理 Wiki**：BWIKI（非官方，但逐条自称"依据正式版游戏代码整理"，给出公式与阈值）。
- **【C】社区/攻略/README**：GitHub 项目文档、Nexus/创意工坊说明、论坛整理帖。
- **【D】推测**：以上都不足以支撑，仅作假设，需实测。

**已做的工作**：

1. 安装目录取证（Mono/IL2CPP、Mods 结构、版本、依赖 dll）。
2. `Assembly-CSharp.dll` 全量导出：**949** 个类型（初稿采样 946；build 26525552 复核）、每类型的方法与字段签名 → `docs\research\_asm_dump.txt`；可打印字符串 → `_asm_strings.txt`。
3. 抓取并核对了 BWIKI 机制页（违禁品与赃物、犯罪值、治安部调查、改造体、派系、夜间结算、房租、机器）与 GitHub `Codesoulme/shenkongdangpuMOD` 的 README/Architecture/manifest。
4. 未完成：PSApi 与 ItemForge 的成品说明（PSApi 页 403、ItemForge 页正文被截断）；手术工具数值、电费换算率的具体常量未读到 IL 常量值。

> 说明：`_cjk_strings.txt` 是错误解码产物（中文不在 DLL 里，而在 Unity 本地化资源），不作为依据。

---

## 2. A 表：原版机制事实清单

### 2.1 电量、电池与充电

| 机制 | 事实 | 来源 | 对设计的约束/影响 |
| --- | --- | --- | --- |
| 能量单位 | 机器耗能以 **KJ** 计；物品侧属性键 `POWER_SOURCE_ITEM_ENERGY / MAX_ENERGY / RECHARGE / BANDWIDTH / DISPOSABLE` | 【A】`PowerHelper` 字段 | 身体电量沿用 KJ 量纲无障碍 |
| 充能器 | 基础价值 **150**，夜间工作，为能量电池 **+3 KJ/晚**（需已付电力服务费） | 【B】BWIKI 机器 | "直接为身体充电"可套用 `PowerHelper.ChargeBattery(item, amount, ignoreBlackout)` 语义；但目标必须是 `GameItem`，身体电量须先包装成物品或另挂结算 |
| 能量阵列 | 价值 **200**，夜间为相邻电池 **+2 KJ/晚**，可叠加；商用级供电单元解锁后 +4 | 【B】 | — |
| 自充电电池 | 夜间自恢复 **4 KJ**，不超上限 | 【B】夜间结算 | — |
| 电流转换器 | 价值 **300**，从下层区电网取电代替电池；**每晚付"电流转换器"服务费**，费用按机器耗电折算（`CurrentConverterHelper.ToCredits(energy, rate)`、`UpdateServiceCost(StoreService)`） | 【A】`CurrentConverterHelper`；【B】机器/夜间结算 | 这是"电费↔信用点"的官方换算入口；具体 rate 常量未读到，需实测 |
| 店铺电力服务费 | 公式 **（天数÷10＋5）× 难度倍率**；停电事件期间免费；解锁"偷接私电"后不收且免疫停电 | 【B】夜间结算 | 可作为"身体电量充能收费"的定价锚点 |
| 停机语义 | 电源槽空 / 电量不足一次耗电 / 转换器关闭 / 停电 / 未开夜间服务 → 物品提示红色"能量不足" | 【B】机器 | 电量归零"强制休眠"可直接对齐这套 UI 语义 |
| 电池容量量级 | 原版机器单次耗电为 2–24 KJ 级；充能器一晚只回 3 KJ | 【B】机器页各机器参数 | **100 kJ 身体电量池远超原版量级**（≈33 晚充能器），基线数值必须重设或改量纲 |

### 2.2 夜间、闭店与夜间外出

| 机制 | 事实 | 来源 | 约束/影响 |
| --- | --- | --- | --- |
| 关店 ≠ 过夜 | 关店后仍可整理物品、准备机器、**进行夜间外出**；点睡袋/睡觉入口才进入"营业结束面板"→黑屏结算 | 【B】夜间结算 | Mod 的"闭店后指令"必须挂在**营业结束面板确认**前后，而不是关店时 |
| 结算管线（14 段） | 供电准备与设备早段 → 夜间服务扣费 → 服务与店铺事务 → 远征/玩家状态/联系人 → 化学与冷藏 → 进料斗 → 设备正常段 → 进料斗 → 设备末段 → 进料斗 → 夜间收尾 → **日期与事件（天数+1）** → 次日经营（房租倒计时、自动售货机犯罪入账、顾客/治安刷新）→ 结束检查与自动存档 | 【B】夜间结算 | 换日类逻辑的唯一正确插入点是第 12 段前后；直接改 `StoreDate.AdvanceDay` 会漏掉事件/房租回填 |
| 夜间外出 | 每晚 **1 次**机会，垃圾场/配给站/杰克逊博士店**共用**；去过一处当晚不能再出门；**次日普通顾客名额 −1**（"短眠者"特性不计） | 【B】夜间结算/顾客机制 | v0.2"夜间外出且不错过客人 −5 kJ"的判定要读"当晚是否外出"+"次日名额"两个状态，不是单一 flag |
| 不能外出 | 重伤；"全站严打"事件期间；"广场恐惧症"休息期 | 【B】 | 手术改造"消耗夜间外出机会"应做同样的拒绝条件 |
| 夜间报告 | 次日展示服务费、失窃、健康、治安、改造体来访等消息；读档若仍有日志会重显（不重算） | 【B】；【A】`NightLog` | Mod 追加"身体电量/感染结果"条目有现成落点 |

### 2.3 违禁品与盘查

| 机制 | 事实 | 来源 | 约束/影响 |
| --- | --- | --- | --- |
| 违禁品等级 | 4 级：**低级 / 中级 / 高级 / 高危级**。代码常量 `CONTRABAND_LEVEL_NONE/LOW/MID/HIGH/CRITICAL`，标签键 `CONTRABAND_ITEM_TAG` | 【A】`ContrabandHelper`；【B】违禁品页 | "人类"物品可直接定为 `CRITICAL`，无需新等级 |
| 出售加价 | 低级 +35%、中级 +70%、高级 +100%、高危 +150% | 【B】 | — |
| 卖出即记罪 | 违禁品按成交价**全额**计入对应走私罪名（麻醉品/武器/钥匙卡/一般）；赃物按 `round(成交价×热度÷100)` 记销赃 | 【B】犯罪值 | 任何"卖植入物"的行为都应显式决定是否记账 |
| 盘查结果 | 低级→警告；中级/赃物→没收；高级→没收+罚款（罚款=被查物品单价之和）；高危→**被捕**（豁免权可挡一次并改警告） | 【B】违禁品页/治安部调查 | — |
| 盘查范围 | 仓库、柜台前后、展示柜、**隐藏区（海报拉开时）**、垃圾桶（懒惰盘查员不查）；上锁/锁后/隐藏物品、走私者暗格、迷你走私储藏区**查不到** | 【B】 | "人类"物品的藏匿与查获规则可完全复用这套容器判定 |
| 展示柜风险 | 展示柜中每件赃物**每天按热度掷骰**，任意一件成功即当天生成盘查员；任意等级违禁品直接触发 | 【B】 | 光学迷彩/伪装植入物"0 信用点摆放"必须避开展示柜触发路径 |
| 治安部顾客进店 | 只查**柜台前后 + 展示柜**；先查违禁品，再逐件对玩家所有的赃物按热度掷骰；认出后热度重置 100 并进入盘查对话 | 【B】 | 顾客视角的"发现违禁品并报警"有明确入口（`SecurityCheckCounter/SecurityCheckDisplayCase`） |
| 藏匿不加声望 | 被藏起来的违禁品/赃物即使本次盘查通过也不加治安部声望 | 【B】 | — |
| 举报奖励 | 举报违禁品顾客：中级 25、高级 40、高危 60（低级 0）信用点 | 【B】 | 原版已有"举报"经济，Mod 的"顾客发现植入物→报警"可复用 |

### 2.4 治安部调查、犯罪值与判决

| 机制 | 事实 | 来源 | 约束/影响 |
| --- | --- | --- | --- |
| 两个数值 | **犯罪值**（各罪名金额之和）与**证据进度**（0–100）分开推进；调查面板可查 | 【B】治安部调查 | "警觉度"若要复用，证据=调查进度，犯罪值=总量 |
| 自然衰减 | 新日处理时，若证据 <80，则**每项罪名各减 20**（最低 0）；证据 ≥80 停止衰减 | 【B】 | 等价于原版的"警觉度自然回落"，可直接作为 Mod 警觉度的减排参照 |
| 证据增长 | 按（衰减后）犯罪值分档，每新日 +2/+6/+9/+12/+20/+33（0–99 / 100–299 / 300–849 / 850–1199 / 1200–1499 / 1500–2499 / ≥2500） | 【B】 | 可作"治安部警觉度"增长曲线的现成映射 |
| 派员与判决 | 证据达 100 → 判决警官排入来访队列；对话开始时复核：证据 ≥95 且金额 >0 才判；**<300 罚款、300–1499 逮捕、≥1500 处决**；证据不足走"证据遗失"（治安部声望 −20） | 【B】 | 结局级风险已存在，Mod 的"高警觉度"应映射到证据增速，而非新增一套审判系统 |
| 声望修正 | 证据增长：值得信赖 ÷2、重点盯防 ×1.2、头号通缉 ×1.5、联名检举 再 ×1.5 | 【B】 | 可作为警觉度系数的现成乘区 |
| 降低手段 | 王尔德善后人（每晚每项 −15%−50 / −20%−150 / −25%−400，25/45/70 信用点/晚）、清除证据（500/600/700，14 天冷却）、豁免权（250 起，每买一次 +100）、盘查预警（10/晚） | 【B】 | — |
| 钓鱼执法 | 走私+赃物 >1000 时面板显示"钓鱼执法"，**仅有提示与夜间报告，无实际事件**（疑似未完成内容） | 【B】 | 不要基于它做设计；也不要假定"治安部会主动来查" |

### 2.5 改造体（Aug）

| 机制 | 事实 | 来源 | 约束/影响 |
| --- | --- | --- | --- |
| 引入节奏 | 普通开局**第 12 天**导师送霰弹枪+《改造体鉴别指南》，存在度从 15 起；第 13/18 天各一名医疗改造体；常规到访第 24–26 天起，每 6–8 天一名，每天最多一名 | 【B】；【A】`AUG_INTRODUCED_DAY` 等常量 | 零号开局若"主动制造"改造体，需接管到访调度并抑制随机来访 |
| 两种形态 | 约 **80% 伪装改造体**（顶替当天已排队买家，沿用其名字/预算/求购），其余明面改造体（求购医疗/材料，预算 150–250） | 【B】；【A】`MakeDisguisedAug`、`FindEventCustomerAugCandidate` | Mod 的"伪装型植入物/光学迷彩"与原版伪装机制同构，可复用 |
| 存在度 augPresence | 初始 15；放走 +10（困难 +15、挑战 +16）、击杀 −25（困难 −10、挑战 −8）；**满 100 结束本局**（普通/轻松仅"改造体危机"或高难度结束） | 【B】；【A】`DEFAULT_AUG_PRESENCE`、`augPresence` | 可直接作为改造体派系的"威胁/关注度"反向指标（暴力清零策略） |
| 击杀奖励 | 信用点 = **100 +（天数 − 引入日）**，钳制 100–250；"改造体危机"开局 ×1.25。声望：治安部 +8、革命军/黑市/下层区各 +2。累计 10 杀解锁成就 | 【B】；【A】`ACH_AUG_HUNTER` | 基线"击杀给治安部声望"与原版一致，无需改奖励管线 |
| 误杀 | 记"过失杀人"250（<25 天）/500（25–49 天）/750（≥50 天）并扣多派系声望；豁免权**不能**抵消 | 【B】 | 击杀判定必须精确，Mod 新增的"伪装成人类的改造体"会放大误杀风险 |
| 扫描仪 | 杰克逊博士出售（引入后至剧情结束，每次来访 50% 概率），价值 **200**；需装电池，**每次扫描耗 25 能量**，每人只能扫一次，**100% 准确** | 【B】；【A】`AugScanner`（`AUG_SCANNER_TAG`、`ACTIVATION_COST`） | "改造体识别/扫描"已有完整实现，Mod 只需扩展识别对象或降低误判 |
| 威胁议价 | 指控对方是改造体：真改造体接受，卖给它 +20%（它卖你 −20%）；指控错误：所属派系 −7，或 50% 概率 −10 且不再交易；每人只能威胁一次 | 【B】 | 可作为"揭穿伪装不像人类"的参照实现 |
| 剧情终点 | 引入 50 天后存在度归 0 且买下营业许可证满 25 天 → 治安部宣布清除完毕；无营业许可证则不触发 | 【B】；【A】`AUG_ALL_CLEAR_DAYS / AUG_ALL_CLEAR_PERMIT_DAYS` | Mod 长期经营必须处理这个"改造体消失"的终局，否则后期无改造体 |
| 开局特性"改造体危机" | 中性特性、花费 1 点；第 1 天解锁、无第 13/18 天固定来访、击杀奖励 ×1.25、**任何难度存在度满 100 都结束本局**、永不结束 | 【B】特性页 | 与"零号改造体"互斥可用官方 `StartingPerk.incompatiblePerks` 实现 |

### 2.6 派系与声望

| 机制 | 事实 | 来源 | 约束/影响 |
| --- | --- | --- | --- |
| 派系数量 | 常规 **5 个**：下层区、上层区、治安部、黑市、革命军；**13 区卡特尔**为隐藏派系（仅化学家开局） | 【B】派系；【A】`FACTION_LOWER/UPPER/SECURITY/BLACK_MARKET/REVOLUTION/CARTEL/CHURCH/CRIME/TOURIST`、`FACTION_MIDDLE` | **"第五派系"实际会变成第六个**；`FACTION_MIDDLE` 在代码中存在但 wiki 无中层声望，需确认其用途 |
| 数值范围 | 每个派系 **−200 至 200**，22 个显示等级 | 【B】 | 基线"改造体声望 −100～100"是另一套量纲，不能直接塞进原版字段 |
| 获取公式 | 交易声望 = 成交价 × 派系倍率 × 顾客倍率 × 特性倍率 × 额外倍率 ÷ 400（派系倍率：下层 0.66 / 上层 1.2 / 其余 1.0） | 【B】 | Mod 若走"卖物品涨声望"，应复用此公式而非自建 |
| 关键阈值（治安部） | ≥100 VIP（不再被盘查/小偷不来了）、≥60 值得信赖（盘查少、调查慢）、≤−20 重点盯防（调查×1.2）、≤−60 头号通缉（×1.5）、≤−80 彻底查抄、≤−100 立即入狱结局 | 【B】 | "警觉度"与治安部声望是**两套**压力源，Mod 不要把两者混为一个变量 |
| 关键阈值（下层区） | ≥20 **每天必定额外吸引 1 名随机顾客**；≥80 守口如瓶（违禁证据减半）；≤−20 每天少 1 名顾客 | 【B】 | 基线 v0.2 "改造体声望 ≥20 每天额外 1 名改造体顾客"与原版特权**结构完全相同**，应复用 `StoreClientManager.AddClient` 的调度管线 |
| 破坏与结局 | 任一派系 ≤−20 可能夜间砸店；≤−100 各有结局（暴民私刑/暗杀/立即逮捕） | 【B】夜间结算/派系 | 改造体声望 −100 的"打砸店铺"可直接触发原版破坏状态 |

### 2.7 日历、房租、顾客

| 机制 | 事实 | 来源 | 约束/影响 |
| --- | --- | --- | --- |
| 日历 | 第 1 天是周一，7 天一轮；每周日交租/周供 | 【B】首页/房租 | 周级节律可用 |
| 房租 | 首期 **200**；每期按难度 ×1.025 / ×1.05 / ×1.1 / ×1.1；`dayCounter % 7 == 0` 时收取；欠租、租金宽限 15 天冷却；接受自动售货机合作每周 +150；抵押贷款改为固定周供 | 【B】房租（含 `rentValue`/`temporaryRent` 字段名） | Mod 若加"改造体经营收入"，需与周租现金流一起平衡 |
| 顾客身份 | 原版用**派系**区分（下层区/上层区/治安部/黑市/革命军/卡特尔）+ 具体顾客模板（`StoreClientListTier` 数十种：水贩、拾荒者、医生、护士、工程师…）；**没有独立的"中层区"顾客等级** | 【A】`StoreClientListTier` 方法族；【B】派系 | 基线"按身份等级给改造经费"应定义为"按顾客派系/模板预算"，取 `StoreClient.budget` 类字段 |
| 每日名额 | 基础名额按日计算，受声望、事件、外出影响（外出 −1、"短眠者"不计） | 【B】顾客机制/夜间结算 | 额外顾客类 Mod 必须检查名额，否则会挤掉剧情来客 |
| 剧情来客优先 | 脚本/事件/剧情来客有专门队列与"不可打发"保护 | 【B】；【A】`HandleImportantScriptedClient`、`HandleClientFromStoryLine` | Mod 生成顾客要走 `AddClient/TryAddClient`，不要直接插队 |

### 2.8 物品、标签与机器

| 机制 | 事实 | 来源 | 约束/影响 |
| --- | --- | --- | --- |
| 标签系统 | 物品特性（`ItemFeature`/`ItemFeatureList`）+ 字符串标签键，如 `AUG_SCANNER_TAG`、`CONTRABAND_ITEM_TAG`、`ITEM_HIDDEN_TAG`、`POWER_SOURCE_*`、`ENDANGERMENT_ITEM_TAG`、`STOLEN_TAG` | 【A】各 Helper 字段 | 自定义"植入物/人类/医疗品"标签应复用字符串标签，而不是新增枚举 |
| 已知物品与价格 | 充能器 150、能量阵列 200、电流转换器 300、改造体扫描仪 200、3D 打印机 350、熔炉 200、净水器 300、水分收集器 650、幻影投影仪 400、高级涡轮增压器 300、超科技涡轮增压器 15000 | 【B】机器页 | 基线"手术工具约 200 信用点"在 wiki 机器页未找到对应条目，**未核实** |
| 3D 打印机 | 价值 350，夜间工作，耗 8 KJ，用塑料打印多种物品 | 【B】 | 可作为"植入物制造"的载体，但产出表是硬编码掉落表（可经 ModLoot 扩展） |
| 净水药片/试纸 | 存在于游戏内（MCP Bridge 实测消耗净水药片、使用试纸） | 【C】MCP Bridge 说明 | 医疗品/化学品类可作手术消耗品的先例 |
| 废料客 | "退休废料客"为人脉（周二到访），另有拾荒者/垃圾场拾荒体系 | 【B】首页/顾客机制 | — |
| 武器 | 霰弹枪（改造体击杀专用）、枪械订单与武器许可证 I/II 体系、`SecuritySlip`/`WantedList` | 【B】改造体/通缉名单；【A】`GunHelper`、`WeaponPermit` 类 | 玩家持枪与"反杀袭击"需考虑武器许可证与治安部声望吊销逻辑 |
| 机器模组 | 机器有模组舱，可用"模组舱扩建套件"扩容；无模组舱的机器用材料升级 | 【B】机器 | 自定义 2×2 工作台的可行性参照 |

---

## 3. B 表：Mod 能力清单

可行性标记：**现成官方 API** / **现成 API + 少量 Harmony** / **需 Harmony/反射** / **高风险** / **未证实**。

| 能力 | 可行性 | 证据/来源 | 风险与建议 |
| --- | --- | --- | --- |
| Mod 加载方式 | **现成官方 API** | 【A】`ModLoader.LoadAllMods/LoadModFromFolder/LoadModDll`、`ModManifest`；`Mods\<ID>\manifest.xml` | 不需要 MelonLoader。清单必须含 `ID/Name/Author/ModVersion/GameVersions/Assemblies/Capabilities` |
| 入口点 | **现成官方 API** | 【A】`IMod { Init(ModManifest); OnEnable(); OnDisable(); }` | 用 `OnEnable` 挂事件；`OnDisable` 必须完整反注册 |
| Harmony patch | **现成官方 API** | 【A】`LoadedMod.HarmonyInstance`（`HarmonyLib.Harmony`）、随包 `0Harmony.dll 2.4.2`；【C】csproj 直接引用 `0Harmony` | 是否由加载器自动 `PatchAll` **未证实**；建议自建 `new Harmony(modId)` 并自行 patch，且声明 `dynamic-code` 能力 |
| 游戏事件钩子 | **现成官方 API** | 【A】`ModHook` 单例 + 30 余组 `Early/Late` 事件（见 §4.2） | **优先用 ModHook，少用 Harmony**，兼容性最好 |
| 自定义物品 | **现成 API + 少量代码** | 【A】`ModItemDirectory.InitDirectory()`、`ModHook.OnModItemDirectoryInit`、`ModHelper.SpawnItem(id)`、`ItemDirectory` 子类族 | 具体数据格式（JSON/CSV/资源）**未证实**；建议先做"复制现有物品改标签"的最小验证 |
| 内容包加载（PSApi） | **未证实** | 【C】Nexus 存在 PSApi 条目（`mods/374`）；3DM 整理帖称"前置与加载器齐备" | 页面返回 403，能力/版本/是否与官方 `ModItemDirectory` 叠加**均未核实**；不要写进技术基线 |
| 自定义违禁品/等级 | **现成 API** | 【A】`ContrabandHelper.InitContrabandItem(item[, level])`、`ApplyContrabandFeature`、等级常量 | "人类"物品做成 `CRITICAL` 最省事；注意自动加价与记罪是既成规则 |
| 自定义道具标签 | **现成 API** | 【A】`ItemFeature`/`ItemFeatureList`、各 Helper 的 `*_TAG` 常量、`ModHelper.SetSource` | 用字符串标签，别改枚举 |
| 自定义设施（2×2 工作台） | **需 AssetBundle + 高风险** | 【A】`FurnitureItemDirectory : ItemDirectory`、`PopulateFurniture`、`GridShapeBuilder`、`ComputeModifiedShapeState`；【C】机器有模组舱/升级体系 | 需要预制体、网格形状、放置/吸附验证；建议第一版用"现有机器换皮/改配方"，不要造新放置系统 |
| 顾客/NPC 状态注入 | **现成可能 + Harmony** | 【A】`StoreClientManager.AddClient/TryAddClient/AddNextClient/HandleAugClient/FindEventCustomerAugCandidate`、`StoreClient` 公开方法 | 生成顾客容易，**行为/对话/预算**要靠 `StoreClient` 数据；必须避开剧情/不可打发顾客 |
| 额外顾客调度 | **现成 API** | 【A】`StoreClientManager.GetNormalCustomerCount/PickClient/TryAddClient`；【B】下层区 ≥20 每天 +1 顾客 | 复用原版每日名额与排队逻辑，别自己 `Instantiate` |
| 夜晚结算 Hook | **现成官方 API** | 【A】`ModHook.OnGoingSleepEarly/Late`、`OnWakingUpEarly/Late`、`OnHandlingNightlyServicesEarly/Late`；`StartOfDayUIManager.ShowMorningReport` | 结算顺序固定（§2.2），不要在 `OnWakingUp` 里改当天已结算的数值 |
| 换日 / 日期 | **现成 API** | 【A】`StoreDate.AdvanceDay/GetDateToday`、`StoreClientManager.OnNewDay`、`SecData.OnNewDay` | 优先 ModHook `OnWakingUp*`；直接 patch `AdvanceDay` 会绕过事件/房租回填 |
| 夜间报告追加行 | **需 Harmony/反射** | 【A】`NightLog` 方法族（`AugIncoming/AugLeftAlive/PowerOff/...`） | 方法无参数、自成一条；新文本大概率要自建 UI 或 patch 报表构建 |
| 声望读写 | **现成 API（限原版 6 派系）** | 【A】`StoreReputation.ModReputation(String,Int32,Boolean)`、`ModSecReputation/ModLLReputation/...`、`GetReputationStatus` | **新增"改造体"派系没有官方入口**：只能塞 ModData + 自建 UI，或劫持未用槽位（高风险） |
| "第五派系"UI | **需 Harmony/高风险** | 【B】派系 UI 为固定列表；【A】`ReputationUIManager`、`StoreReputationPerk` | 自建面板（PaperUI/ModConfigWindow）比改原版声望栏安全 |
| 科技树 / 网络升级 | **现成官方 API** | 【A】`PerkDirectory.RegisterModUpgrade(NetworkUpgrade, Action onUnlock)`；`ModHelper.AddNetworkUpgrade(modId,id,cost,subtitle,title,description,onUnlock,tab,icon,prerequisites,cooldownDays,...)` | 双轨（免费科研/付费解锁）可用 `cost=0` + 自定义 `prerequisites` + `onUnlock` 组合；"科研耗时"需自建计时 |
| 开局特质 / 互斥 | **现成官方 API** | 【A】`ModHelper.AddStartingPerk(..., incompatiblePerks[], ...)`、`StartingPerk`、`PerkDirectory.RegisterModPerk`、`GetModPerk`、`RemoveModPerks` | **特质互斥有官方参数**，不要用 Harmony 硬改 |
| 开局场景 / 难度 | **现成官方 API** | 【A】`ModHelper.AddStartingScenario`、`AddDifficulty`、`ModifyDifficulty` | 零号改造体可作为新开局场景 |
| 固有 UI / HUD | **现成 API + 自建** | 【A】`ModConfig`/`ModConfigWindow`、`ModHelper.AddGameOption*`、`PaperUI.CreatePaper/OpenPaper`、`CustomUIBuilder`、`ModUIManager` | 原版 UI 是预制体，改版式建议用 PaperUI 叠页；HUD 常驻状态条需自建 |
| 本地化 | **现成官方 API** | 【A】`ModLoader.LoadLocalization(LoadedMod)`、`LoadedMod.Localization` 字典、`ModHelper.GetLocalized(modId,key,args)`、`GetCurrentLocale` | 中文文本在 Unity 本地化表（不在 DLL）；Mod 自带 CSV/键表即可 |
| 音效/贴图 | **现成官方 API** | 【A】`RegisterModClip`、`LoadTexturesFromFolder`、`LoadSoundsCoroutine`、`LoadModAssetBundle` | 像素图需 `pixelArt` 参数 |
| 存档持久化 | **现成官方 API** | 【A】`ModHelper.SetModData*/GetModData*`、`WriteModDataFileText/Bytes`、`ListModDataFiles`；`SaveManager.Save/Load`；`SaveFiles`（槽位/历史） | **跨天状态必须走 ModData/自建 JSON**；不要写进原版存档结构 |
| 掉落表/经济修正 | **现成官方 API** | 【A】`ModHelper.RegisterLootTable/AddLootEntry/SetLootWeight/RollLootTable`、`ModLootFile`（JSON：tables/groups/patches） | 物品价格/掉落可数据化，无需 Harmony |
| 夜间外出地点/事件 | **现成官方 API** | 【A】`ModHelper.AddAfterhourLocation/AddAfterhourEvent/GetAfterhourModifier/SetAfterhourCounter`、`ModHook.OnAfterhour*` | 基线"夜间指令"可映射为 afterhour 地点/事件，但需自建"指派改造体"逻辑 |
| Steam 创意工坊 | **现成官方 API** | 【A】`ModWorkshop.GetInstalledItems/OnItemInstalled/OpenItemPage`；【C】工坊条目 3829066775、3832110492、3833038046 | 发布走工坊；本地开发直接放 `Mods\<ID>\` |
| 能力声明/安全扫描 | **官方强制** | 【A】`ModCapability`（files/network/process/dynamic-code/native/reflection-external/steam/steam-auth）、`ModScanner`、`ModTrust`、`ModTrustRecord`、`ModHook` 无 | 未声明能力会被扫描标记为"未声明"；`PatchAll`/反射/网络都会被检出。**提前设计好最小能力集** |
| Mod 冲突处理 | **部分** | 【A】`ModLoader._modOrder/ReorderMods/EnabledMods`、`ModTrust`（安全层，不解决功能冲突） | 功能冲突需自管：Harmony priority、幂等、检测同类 Mod（`ModLoader.Mods`）、必要时 soft-depend |
| Mod 配置界面 | **现成官方 API** | 【A】`ModConfig.Define(key, default, section, label, tooltip, requiresRestart)`、`Load/Save`、`ModConfigWindow` | 平衡数值应全部配置化 |
| 控制台/调试 | **现成** | 【A】`DevMode`、`ModHelper.AddDebugFunction`、`QFSW.QC`、`mod-scan`/`mod-trust` 命令 | 测试期用 `mod-scan` 预检能力声明 |

---

## 4. 官方 Mod API 与 Hook 点（代码级）

> 以下类型/方法名均来自 `_asm_dump.txt`（Mono.Cecil 从 `Assembly-CSharp.dll` 读取），**签名已确认**；只标注了名称、未验证运行行为的条目已注明。

### 4.1 加载器与清单

- `ModLoader`（单例 `ModLoader.Instance`）：`LoadAllMods/LoadModFromFolder/LoadModDll/ParseManifest/ValidatePrerequisites/ResolveModDependency/LoadModAssets/LoadTextures/LoadLocalization/SetModEnabled/ReorderMods/LogAudit`。
- `ModManifest` 字段：`ID, Name, Author, ModVersion, Description, GameVersions[], Prerequisites[], Assemblies[], Capabilities[]`。
- `LoadedMod` 字段：`Instance(IMod), Manifest, Assembly, HarmonyInstance, FolderPath, DllPath, IsEnabled, Source(Local/Workshop), WorkshopId, TrustState, Fingerprint, UnlistedDlls, Textures/Sprites/Sounds/Localization`。
- `IMod`：`Init(ModManifest)`、`OnEnable()`、`OnDisable()`。
- `ModCapability` 内置能力：`files, network, process, dynamic-code, native, reflection-external, steam, steam-auth`。

### 4.2 `ModHook` 事件（官方，可直接订阅，无需 Harmony）

| 分组 | 事件（均为 Early/Late 成对，除注明） | 对应系统 |
| --- | --- | --- |
| 顾客生成 | `OnGenerateCustomerVeryEarly / Early / Normal / Late / VeryLate(StoreClientManager)` | 额外顾客、改造体伪装替换 |
| 读档 | `OnGameLoadedInit / Early / Normal / Late` | 状态恢复 |
| 卷帘门 | `OnShutterOpenedEarly/Late`、`OnShutterClosedEarly/Late` | 开店/关店 |
| 睡眠 | `OnGoingSleepEarly/Late`、`OnWakingUpEarly/Late` | 闭店确认 / 次日起床 |
| 外出 | `OnLeavingStoreEarly/Late`、`OnReturningStoreEarly/Late` | 夜间外出 |
| 夜间服务 | `OnHandlingNightlyServicesEarly/Late` | 结算服务费 |
| 物品入位 | `OnPlaceInventorInventoryItemEarly/Late(List<GameItem>)` | 发明家/库存 |
| 提示框 | `OnCreateTooltipEarly/Late(RichTextBuilder, GameItem)`、`CreateDevTooltip*` | 物品 tooltip 注入 |
| 资源/配置 | `OnModAssetsLoaded(LoadedMod)`、`OnModConfigApplied(String modId)`、`OnModItemDirectoryInit(ModItemDirectory)` | 注册自定义内容 |
| 掉落 | `OnLootTablesLoaded`、`OnLootRolled(LootRollContext)` | 掉落表扩展 |
| 其它 | `OnPaperOpened(String,PaperUI)`、`OnNetworkUpgradeUnlocked(String)`、`OnNewGameStarted(String)`、`OnDifficultyApplied(String)` | UI/科技树/开局 |
| 外出地点 | `OnAfterhourArrive/Leave{Early,Late}(String locationId)`、`OnAfterhourEventStarted/Ended(String,String)` | 夜间地点与事件 |

### 4.3 `ModHelper` 关键 API（build 26525552 为 **165** 个方法；初稿 143，摘与本案相关）

`AddCredit(int,bool)`、`SpawnItem(id)`、`MoveItemTo{Inventory,FrontCounter,BackCounter,DisplayCase,Trash,Afterhours}`、`SetItemOwnerShip`、`SetSource`、`SetClientSource`、`GetLocalized`、`PlaySound`、`GetConfig`、`AddGameOption{Toggle,Slider,Dropdown,KeyBind}`、`RegisterLootTable/AddLootEntry/SetLootWeight/RollLootTable`、`AddNetworkUpgrade`、`AddStartingScenario`、`AddStartingPerk`、`AddDifficulty`、`AddAfterhourLocation/AddAfterhourEvent`、`CreatePaper/OpenPaper/RegisterPaperBook`、`SetModData*/GetModData*`、`WriteModDataFileText`、`AddDebugFunction`、`RequestSteamAuthTicket`。

### 4.4 可复用的机制类（代码级）

| 类 | 关键方法（节选） | 用途 | 可挂接系统 |
| --- | --- | --- | --- |
| `AugHelper` | `RollAugTier`、`MakeDisguisedAug`、`SetRandomAugFaction`、`OnGoodKill`、`OnAugLeftAlive`、`OnShootoutLeave`、`GetShootResult`、`BuildTieredAugDialogue` | 改造体到访/伪装/击杀/放走 | 击杀、到访、对话 |
| `AugScanner` | `CreateWindow`、`GetBatterySlot`、`CreateTooltip`、`ACTIVATION_COST=25` | 扫描仪电池与耗能 | 识别系统 |
| `ContrabandHelper` | `InitContrabandItem(item[,level])`、`StartInspection(personality,fromShowcase)`、`SecurityCheckCounter/DisplayCase`、`GetHighestContrabandLevel(Int)`、`GetFineAmount`、`GetBribeAmount`、`IsConcealedFromInspection`、`IsSmugglerBay`、`CheckIfContrabandWasFound` | 违禁品初始化、盘查、查获 | 盘查/报警 |
| `StolenHelper` | `InitStolenItem(item,forcedHeat)`、`SetHeat`、`GetFoundChance`、`UpdateStolenItem`、`GetStolenItemTradingRepBonus`、`DEFAULT_HEAT_LOSS` | 赃物热度 | 显示/盘查/记账 |
| `SecData` | `CommitCrime(id,amount)`、`CheckSoldContraband(item,client)`、`OnNewDay()`、`SendOfficer()`、`GetTotalCrimeValue`、`GetProjectedSentence`、`GetFineValue`、`GetInspectorPersonality` | 犯罪值/证据/判决 | 治安调查、警觉度 |
| `PowerHelper` | `ChargeBattery(item[,amount,ignoreBlackout])`、`ChargeAllRechargable`、`TryRemoveEnergy`、`DrawPowerSource`、`InitPowerSourceItem`、`GetAvailableEnergyFromItem`、`RandomizedEnergyCredit` | 电池与机器供电 | 身体电量 |
| `CurrentConverterHelper` | `InitCurrentConverter`、`GetRate`、`ToCredits(energy,rate)`、`GetHostUsage`、`IsBlackedOut`、`IsServiceActive`、`Supply`、`UpdateServiceCost` | 电网取电与电费 | 电费换算、充电 |
| `StoreClientManager` | `GenerateClient`、`OnNewDay`、`AddClient/TryAddClient/AddNextClient`、`HandleAugClient(bool)`、`AddAugClient`、`FindEventCustomerAugCandidate`、`GetNormalCustomerCount`、`ComputeClientType` | 顾客调度 | 额外顾客、改造体网络 |
| `StoreClient` | `IsClientBuyingThisItem`、`IsSellingContraband/Stolen`、`OnDealAccepted`、`StartMainDialogue`、`CanReport`、`HasBudgetLeftToBuy`、`GetScavNoAcceptContrabandChance` | 交易/对话/预算 | 植入物销售、感染判定 |
| `StoreReputation` | `GetReputation`、`ModReputation(factionId,int,bool)`、`ModReputationRaw`、`ModSecReputation/ModRevReputation/ModBMReputation/ModLLReputation/ModULReputation/ModCartelReputation`、`GetReputationStatus`、`GetPerkByID` | 声望读写 | 改造体声望（需自建槽） |
| `EndOfDayUIManager` | `OpenUI/CloseUI/RefreshUI/OnEndDayButtonClick`、`BuildServiceRow` | 营业结束面板 | 闭店指令入口 |
| `StartOfDayUIManager` | `ShowMorningReport`、`OnStartDayButtonClicked`、`rentReminder` | 夜间报告 | 次日报表 |
| `NightLog` | `AugLeftAlive`、`AugIncoming`、`SecurityInvestigationNearComplete`、`PowerOff/PowerOn`、`BlackoutActive`… | 夜间报告条目 | 报告追加（需 patch） |
| `StoreDate` | `AdvanceDay`、`GetDateToday`、`SetDateToday`、`GetRandomDateInFuture` | 日期 | 换日 |
| `SaveManager` | `Save()`、`Load()`、`HasSave()`、`EncodeNode/DecodeNodes` | 存档 | 持久化校验 |
| `SaveFiles` | `Slot`、`SaveHistory`、`RotateIntoHistory`、`IndexSave/IndexLoad`、`RepairDamagedRun` | 槽位/历史 | 备份与回滚 |
| `PerkDirectory` | `RegisterModPerk(StartingPerk)`、`RegisterModUpgrade(NetworkUpgrade,Action)`、`GetModPerk`、`RemoveModPerks` | 特质/科技树 | 零号特质、双轨科技树 |
| `ItemDirectory` 族 | `MiscItemDirectory`(154)、`MedsItemDirectory`(49)、`GunsItemDirectory`(37)、`FurnitureItemDirectory`(6) 等 | 物品定义 | 自定义物品/植入物 |

### 4.5 建议的 Harmony Patch 清单（目标 → 时机 → 用途 → 风险）

| # | 目标方法 | 时机 | 用途 | 风险 |
| --- | --- | --- | --- | --- |
| 1 | `StoreDate.AdvanceDay` | Postfix | 换日后结算身体电量自然消耗、感染结果、改造体行动成果 | 中：会绕过事件/房租/存档回填；**优先改用 `ModHook.OnWakingUpLate`** |
| 2 | `StoreClientManager.OnNewDay` | Postfix | 重置每日改造体名额、存在度、警觉度日结 | 低：原版新日入口之一 |
| 3 | `EndOfDayUIManager.OnEndDayButtonClick` | Prefix/Postfix | 拦截"结束营业"→分配夜间指令、扣夜间外出机会 | 中：面板可被反复打开；需幂等 |
| 4 | `ModHook.OnGoingSleepLate`（事件，非 patch） | 事件回调 | 夜间指令主入口（推荐） | 低 |
| 5 | `StoreClientManager.GenerateClient` 或 `AddAugClient` | Postfix | 声望阈值触发的额外改造体顾客 | 中：名额/排队冲突，须检查 `GetNormalCustomerCount` |
| 6 | `StoreClientManager.FindEventCustomerAugCandidate` | Prefix（可替换目标） | 控制伪装改造体顶替对象 | 中：会影响原版改造体到访 |
| 7 | `StoreClient.OnDealAccepted` | Postfix | 植入物售出后登记"待感染"名单、收取改造经费 | 中：要对多物品/议价/退货去重 |
| 8 | `SecData.CheckSoldContraband` | Prefix/Postfix | "人类"物品/植入物是否计入走私罪、警觉度 | 中：影响判决与结局，须按原版记账口径 |
| 9 | `ContrabandHelper.StartInspection` | Prefix | 注入警觉度对盘查概率/结果的修正 | 中：盘查同时影响声望与现金 |
| 10 | `AugHelper.OnGoodKill` | Postfix | 击杀改造体额外降低警觉度、改造体声望不降 | 低：原版已有声望奖励，追加即可 |
| 11 | `StoreReputation.ModReputation(String,Int32,Boolean)` | Prefix | 改造体声望 99/100 硬上限、朋友路线锁定 | **高**：新增派系不被支持，可能需整段替换；建议改为 ModData + 自建 UI |
| 12 | `PowerHelper.ChargeBattery(GameItem,Int32,Boolean)` | Prefix/Postfix | 把电池能量转成身体 kJ、电费结算 | 低：纯数值管线 |
| 13 | `CurrentConverterHelper.ToCredits` | Postfix | 电费↔信用点换算（若需改汇率） | 低 |
| 14 | `NightLog.<各类无参方法>` 或报表构建 | Postfix | 夜间报告追加"电量/感染/警觉"条目 | 中：UI 与文本布局 |
| 15 | `StartOfDayUIManager.ShowMorningReport` | Postfix | 次日 HUD/状态条注入 | 中：UI 层级 |
| 16 | `SaveManager.Save` / `Load` | Postfix | 校验 ModData 落盘、版本迁移 | 低：只读校验，勿改原版字段 |
| 17 | `AugHelper.RollAugTier` / `IsInTierHoldWindow` | Prefix | "零号"开局抑制随机改造体 | 低：配合 `incompatiblePerks` 更稳 |
| 18 | `StoreClient.StartMainDialogue` | Postfix | 注入口头"伪装不像人类"的判定交互 | 中：对话树是原版预制结构 |

> 原则：**能用 `ModHook` / `ModHelper` 的绝不 patch**；必须 patch 的只做 Postfix 追加，不改原版返回值；所有 patch 加 try/catch 与开关，确保可单独关闭。

---

## 5. 关键结论

### 5.1 最可行的实现路径（按风险从低到高）

1. **第 0 层（1–2 天可验证）**：官方 `IMod` + `manifest.xml` + `ModHook` 订阅 + `ModConfig`；用 `ModHelper.SpawnItem` 与 `ModData` 做最小闭环（例如：开局特质 → 每晚安 +5 "身体电量" → 次日 HUD 显示）。这一步不碰任何原版数值，先验证加载、保存、UI 三条链。
2. **第 1 层（数据驱动，低风险）**：自定义物品/标签/违禁品（`ItemDirectory` 族 + `ContrabandHelper.InitContrabandItem` + 字符串标签）；掉落表用 `ModLoot` JSON；文案走 Mod 本地化表。
3. **第 2 层（事件驱动，中风险）**：额外顾客（`StoreClientManager.AddClient` + 每日名额检查）、夜间报告、击杀奖励/警觉度修正（`AugHelper.OnGoodKill`、`SecData` 派生字段），全部通过 `ModHook` 或 Postfix。
4. **第 3 层（高风险，最后做）**：新增"改造体派系声望"、夜间指令网络、2×2 工作台、伪装/光学迷彩的顾客可见性。这一层需要自建 UI 与状态机，且必须与原版存档兼容。

### 5.2 必须规避的坑

- **不要再假设 IL2CPP / MelonLoader**：用 Mono + 官方 `ModLoader`，否则打包与签名、能力声明全部对不上。
- **"第五派系"不存在官方插槽**：`StoreReputation` 的读写方法按固定派系写死（Sec/Rev/BM/UL/LL/Cartel）。硬加派系会牵动 UI、存档、结局判定；建议 ModData + 自建面板，或明确接受"借用未使用槽位"的兼容风险。
- **100 kJ 身体电量与 3 kJ/晚的充能器量级差 30 倍**：要么重设数值（如 10 kJ 池、+1/晚），要么把"身体电量"改成百分比条，不要直接搬基线数值。
- **夜间外出不是自由行动**：每晚 1 次、三地点共用、次日顾客 −1、重伤/严打禁行。任何"夜间指令"必须建立在这套限制上。
- **展示柜是警报器**：赃物/违禁品放展示柜会每天掷骰触发盘查；光学迷彩"0 信用点摆放"必须绕开 `SecurityCheckDisplayCase`。
- **误杀代价极高**（250–750 犯罪值 + 多派系掉声望，豁免权无效）：新增"伪装成人类"的改造体时必须给玩家可靠识别手段（扫描仪/指南/破绽），否则体验灾难。
- **钓鱼执法是空壳**：不要设计依赖"治安部主动钓鱼"的机制。
- **结算顺序不可乱**：早段/正常段/末段 + 进料斗三轮是硬编码顺序；在 `OnWakingUp` 里修改当夜已结算的机器/房租会失效。
- **能力声明最小化**：`dynamic-code`（Harmony/反射）与 `network` 都会被扫描记录并需要玩家确认；能不用就不用，否则工坊审核与用户信任成本上升。

### 5.3 需要向用户确认的技术假设

1. **版本基线**：本机已更新至 **BuildID 26525552**（2026-11-09 21:06；初稿采样 26496118 / 2026-11-07）。BWIKI 称"正式版 1.0"，生态文档称"0.46D / ModLoader 100-Rev1"，MCP Bridge 称"100-REV6 / 0.46D"——外部口径仍不一致；以本机 appmanifest 为准，`manifest` 的 `GameVersions` 用范围，不写死 build。复核记录见 `version-watch.md`。
2. **PSApi 与 ItemForge**：PSApi 已定位到 Nexus `mods/374`（搜索标题可核实），但正文 403；ItemForge（`mods/68`）页面正文被截断。两者与官方 `ModItemDirectory`/`ModLoader` 是否叠加、版本要求如何**均未核实**；若为既定技术路线，需用户提供本地文件或说明文档。
3. **"手术工具约 200 信用点"**：wiki 机器页未找到对应条目；唯一相近的是 `InitAnimalSurgeryTool`（动物手术工具）。需确认是"人用手术工具"还是记忆偏差。
4. **改造体声望扩展 Mod 的现状**：本机 `Probably-Aug` 仓库只有同步脚手架（README 声称"增加改造体零号特质和改造体声望系统"，但无 Mod 代码）；3DM/游侠页面存在"改造体数量上下限MOD"标题（未读正文）。**无可核实的功能实现可参考**。
5. **电费换算率**：`CurrentConverterHelper.DEFAULT_RATE` 与 `ToCredits` 的实际常量需读 IL/实测，才能定"1 kJ = 多少信用点"。

---

## 6. 参考链接

**官方/商店**

- Steam 商店页（AppID 4348910）：https://store.steampowered.com/app/4348910/
- 发行商稿（tinyBuild）：https://www.gamespress.com/pt/TINYBUILD-SMUGGLES-PROBABLY-STOLEN-THE-GRITTY-PIXEL-ART-CYBERPUNK-SHOP
- AUTOMATON 报道：https://automaton-media.com/en/news/probably-stolen-cyberpunk-shopkeeper-sim-started-out-as-an-obscure-game-with-max-28-concurrent-players-but-became-a-breakout-hit-thanks-to-makeover-by-publisher/

**BWIKI（非官方，内容自称依据游戏代码整理）**

- 首页/导航：https://wiki.biligame.com/probablystolen/首页
- 违禁品与赃物：https://wiki.biligame.com/probablystolen/违禁品与赃物
- 犯罪值：https://wiki.biligame.com/probablystolen/犯罪值
- 治安部调查：https://wiki.biligame.com/probablystolen/治安部调查
- 改造体：https://wiki.biligame.com/probablystolen/改造体
- 派系：https://wiki.biligame.com/probablystolen/派系
- 夜间结算：https://wiki.biligame.com/probablystolen/夜间结算
- 房租：https://wiki.biligame.com/probablystolen/房租
- 机器：https://wiki.biligame.com/probablystolen/机器
- 顾客机制：https://wiki.biligame.com/probablystolen/顾客机制
- 治安部盘查员：https://wiki.biligame.com/probablystolen/治安部盘查员
- 治安部警官：https://wiki.biligame.com/probablystolen/治安部警官

**Mod 生态**

- Codesoulme/shenkongdangpuMOD（仓库）：https://github.com/Codesoulme/shenkongdangpuMOD
- 架构文档：https://github.com/Codesoulme/shenkongdangpuMOD/blob/main/mods/free-chat-bargain-barter/docs/Architecture_zh-CN.md
- 原版世界与阵营资料：https://github.com/Codesoulme/shenkongdangpuMOD/blob/main/mods/free-chat-bargain-barter/docs/Original_World_And_Factions_zh-CN.md
- manifest 样例：https://github.com/Codesoulme/shenkongdangpuMOD/blob/main/mods/free-chat-bargain-barter/manifest.xml
- 自由聊天&议价&交换（工坊）：https://steamcommunity.com/sharedfiles/filedetails/?id=3829066775
- 账本：好好记账（工坊）：https://steamcommunity.com/sharedfiles/filedetails/?id=3832110492
- MCP Bridge（工坊）：https://steamcommunity.com/sharedfiles/filedetails/?id=3833038046
- MCP Bridge 说明（LobeHub）：https://lobehub.com/mcp/yidengdengdashi-probably-stolen-mcp-releases
- ItemForge（Nexus）：https://www.nexusmods.com/probablystolen/mods/68
- PSApi（Nexus，正文 403 未读取）：https://www.nexusmods.com/probablystolen/mods/374
- Nexus Probably Stolen 板块：https://www.nexusmods.com/games/probablystolen
- 3DM 热门 Mod 整理帖：https://bbs.3dmgame.com/thread-6718765-1-1.html
- 改造体数量上下限 MOD（页面标题可核实）：https://3g.ali213.net/patch/314423.html

**本地产物（供复核）**

- 反编译类型/方法/字段全量导出：`docs\research\_asm_dump.txt`
- DLL 可打印字符串：`docs\research\_asm_strings.txt`
- 引自本机 `Probably Stolen_Data\Managed\Assembly-CSharp.dll`、`0Harmony.dll`、`Probably Stolen_Data\app.info`、`..\appmanifest_4348910.acf`
