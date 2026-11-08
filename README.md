# Probably-Aug

深空当铺：可能是改造体mod，增加改造体零号特质和改造体声望系统，没有改造体零号特质也可通过提高改造体声望体验改造体内容。

---

## 多设备开发同步

仓库里带了一个单文件同步脚本 `ProbablyAug-Sync.ps1`，两台电脑用同一份。

- **主通道**：GitHub（`origin`）
- **回退通道**：Tailscale 内网（对端 `git daemon`，只读拉取）
- **本机中转**：`C:\Users\Public\Probably-Aug-hub\probably-aug.git`（纯 ASCII 路径，供对端拉取）

### 第一次配置（每台电脑各做一次）

```powershell
git clone https://github.com/nianxiangchuiyan/Probably-Aug "$env:USERPROFILE\Probably-Aug"
cd "$env:USERPROFILE\Probably-Aug"
powershell -ExecutionPolicy Bypass -File .\ProbablyAug-Sync.ps1 -Action Setup
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

### 日常

| 场景 | 操作 |
|---|---|
| 写代码 | 什么都不用做，5 分钟内自动同步 |
| 立即同步 | `Start-ScheduledTask -TaskName ProbablyAug-Sync` |
| 换设备前 | `.\ProbablyAug-Sync.ps1 -Action Sync` |
| 看状态 | `.\ProbablyAug-Sync.ps1 -Action Status` |
| 看日志 | `Get-Content "$env:USERPROFILE\.probably-aug\sync.log" -Tail 20` |
| 卸载 | `.\ProbablyAug-Sync.ps1 -Action Uninstall` |

### 游戏目录

`-Action Setup` 会建立目录链接：

```
C:\Steam\steamapps\common\Probably Stolen\Mods\Probably-Aug
  -> C:\Users\<你>\Probably-Aug
```

改仓库里的文件，游戏里立刻生效，不用手动拷贝。
如果 mod 内容在仓库的子目录里，改配置项 `DeploySource`（例如 `mod`）。

### 冲突了怎么办

脚本返回 5 时，会：

1. 自动 `git rebase --abort` 回滚，**本地提交不会丢**
2. 把冲突文件写进 `%USERPROFILE%\.probably-aug\conflict.txt`

手动合并后 `git add <文件>` → `git rebase --continue`，再跑一次 Sync。

### 注意

- 仓库**不要**放在 OneDrive / 坚果云里，网盘同步 `.git` 会把仓库写坏
- 同一个文件不要在两台电脑上同时改，这是唯一真会冲突的情况
- `git daemon` 只开 `upload-pack`（只读）：Windows 上它的 `receive-pack` 会挂死，所以对端是"只拉不推"，各自把提交推进自己的 hub
