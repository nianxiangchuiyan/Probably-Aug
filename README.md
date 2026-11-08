# Probably-Aug

深空当铺：可能是改造体mod，增加改造体零号特质和改造体声望系统，没有改造体零号特质也可通过提高改造体声望体验改造体内容。

---

## 多设备开发同步

仓库里带了一个单文件同步脚本 `ProbablyAug-Sync.ps1`，两台电脑用同一份。

- **主通道**：GitHub（`origin`）
- **回退通道**：Tailscale 内网（对端 `git daemon`，只读拉取）
- **本机中转**：`C:\Users\Public\Probably-Aug-hub\probably-aug.git`（纯 ASCII 路径，供对端拉取）

### 两台电脑的路径可以完全不同

脚本不写死任何一台电脑的路径，全部按本机情况解析：

| 项目 | 怎么确定 |
|---|---|
| 仓库目录 | 默认 = **脚本自身所在目录**（脚本就放在仓库根）。配置里的 `RepoPath` 失效时自动回退到这里 |
| 游戏目录 | 优先用配置里的 `GameDir`；失效时自动扫描 Steam 库：注册表 `SteamPath` + `steamapps\libraryfolders.vdf` + 各盘常见位置（`SteamLibrary` / `Steam` / `Games\...`） |
| Mod 链接 | `<游戏目录>\Mods\<ModFolder>` → 仓库目录（junction，不需要管理员权限） |
| 配置文件 | `%USERPROFILE%\.probably-aug\config.json`，**每台电脑一份**，不随仓库同步 |

配置文件里带 `ComputerName`。如果把 config.json 从另一台电脑拷过来，脚本发现机器名不一致，会自动按本机路径校正（仓库、游戏目录）并回写配置，不用手改。

### 第一次配置（每台电脑各做一次）

```powershell
git clone https://github.com/nianxiangchuiyan/Probably-Aug "$env:USERPROFILE\Probably-Aug"
cd "$env:USERPROFILE\Probably-Aug"
powershell -ExecutionPolicy Bypass -File .\ProbablyAug-Sync.ps1 -Action Setup
```

游戏目录会自动识别；识别不准（装在非常规位置、盘符不同）就显式指定：

```powershell
powershell -ExecutionPolicy Bypass -File .\ProbablyAug-Sync.ps1 -Action Setup -GameDir "D:\SteamLibrary\steamapps\common\Probably Stolen"
```

第二台电脑再加上对端设备名（`tailscale status` 里能看到）：

```powershell
powershell -ExecutionPolicy Bypass -File .\ProbablyAug-Sync.ps1 -Action Setup -PeerName <另一台设备名>
```

装完会自动注册两个计划任务：

| 任务 | 作用 |
|---|---|
| `ProbablyAug-Sync` | 每 5 分钟 + 每次登录，自动 commit → pull --rebase → push |
| `ProbablyAug-Daemon` | 开机常驻 `git daemon`，把本机 hub 以只读方式暴露给 Tailscale |

两个任务都不是直接起 `powershell.exe`，而是先经过 `%USERPROFILE%\.probably-aug\run-hidden.vbs`
（用 `wscript.exe` 以隐藏窗口拉起 PowerShell，`SW_HIDE`），所以**不会每 5 分钟弹一个窗口**。
启动器由 `-Action Setup` 自动生成/重写；机器禁用了 Windows Script Host 时会退回直接启动（会有窗口闪现）。

> 计划任务是逐机注册的：**改了脚本后，每台电脑都要重跑一次 `-Action Setup`**，任务动作才会更新成静默启动。

### 日常

| 场景 | 操作 |
|---|---|
| 写代码 | 什么都不用做，5 分钟内自动同步 |
| 立即同步 | `Start-ScheduledTask -TaskName ProbablyAug-Sync` |
| 换设备前 | `.\ProbablyAug-Sync.ps1 -Action Sync` |
| 看状态 | `.\ProbablyAug-Sync.ps1 -Action Status` |
| 看路径认对没 | `.\ProbablyAug-Sync.ps1 -Action Detect` |
| 看日志 | `Get-Content "$env:USERPROFILE\.probably-aug\sync.log" -Tail 20` |
| 卸载 | `.\ProbablyAug-Sync.ps1 -Action Uninstall` |

### 路径不一样 / 换了机器怎么办

- **游戏换盘、Steam 库变了**：直接跑 `-Action Sync`。配置里的目录不存在时，脚本会自动重新识别、写回配置，并在日志里 `WARN` 一行
- **只想确认认到了哪些路径**：`-Action Detect`，会把所有 Steam 库和游戏目录候选列出来，命中的标 `[命中]`
- **仓库换位置**：把脚本和新仓库放一起再 `-Action Setup`，仓库路径会跟脚本走
- **想手动指定**：`-GameDir`、`-ModFolder`、`-RepoPath` 都能覆盖
- **Tailscale 装在非常规位置**：脚本会在 PATH 找不到时去 `C:\Program Files\Tailscale\tailscale.exe` 等常见位置找

### 游戏目录

`-Action Setup` 会建立目录链接：

```
D:\SteamLibrary\steamapps\common\Probably Stolen\Mods\Probably-Aug
  -> C:\Users\<你>\Probably-Aug
```

（路径随本机变化，`-Action Detect` 会打印实际值。）

改仓库里的文件，游戏里立刻生效，不用手动拷贝。
如果 mod 内容在仓库的子目录里，改配置项 `DeploySource`（例如 `mod`）。
如果 `Mods\<ModFolder>` 已经是真实目录而不是链接，脚本不会覆盖，只会在日志里警告。

### 冲突了怎么办

脚本返回 5 时，会：

1. 自动 `git rebase --abort` 回滚，**本地提交不会丢**
2. 把冲突文件写进 `%USERPROFILE%\.probably-aug\conflict.txt`

手动合并后 `git add <文件>` → `git rebase --continue`，再跑一次 Sync。

### 注意

- 仓库**不要**放在 OneDrive / 坚果云里，网盘同步 `.git` 会把仓库写坏
- 同一个文件不要在两台电脑上同时改，这是唯一真会冲突的情况
- `git daemon` 只开 `upload-pack`（只读）：Windows 上它的 `receive-pack` 会挂死，所以对端是"只拉不推"，各自把提交推进自己的 hub
- `config.json` 是逐机的，别提交到仓库里
