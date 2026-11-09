<#
.SYNOPSIS
    Probably-Aug MOD 双设备同步脚本：GitHub 主通道 + Tailscale 回退通道。

.DESCRIPTION
    同一份脚本在每台电脑上运行，逐机配置保存在 %USERPROFILE%\.probably-aug\config.json。

    两台电脑的路径可以完全不同，脚本会自动适配：
      - 仓库位置：默认用脚本自身所在目录（脚本就放在仓库根），不再写死 %USERPROFILE%\Probably-Aug
      - 游戏目录：优先用配置里的路径；失效时自动扫描 Steam 库
                  （注册表 SteamPath + steamapps\libraryfolders.vdf + 各盘常见位置）
      - 配置文件带 ComputerName，发现是从另一台电脑拷来的，会按本机路径自动校正
      - 所有路径支持带空格 / 中文，建立的是 junction（不需要管理员权限）

    -Action Setup      首次配置：克隆仓库 / 建本地 hub / 建游戏目录链接 / 注册计划任务 / 首次同步
    -Action Sync       同步一次（默认动作，计划任务调用这个）
    -Action Status     查看状态：远端连通性、Tailscale、目录链接、最近日志
    -Action Detect     只探测路径（仓库 / Steam 库 / 游戏目录），不改任何配置
    -Action Daemon     常驻的 Tailscale 同步服务（开机计划任务调用这个）
    -Action Uninstall  删除计划任务和目录链接（仓库保留）

.EXAMPLE
    # 第一次（两台电脑都这样；游戏目录会自动找）
    powershell -ExecutionPolicy Bypass -File .\ProbablyAug-Sync.ps1 -Action Setup

.EXAMPLE
    # 自动识别不准时，显式指定本机游戏目录（路径不同就靠这个）
    powershell -ExecutionPolicy Bypass -File .\ProbablyAug-Sync.ps1 -Action Setup -GameDir "D:\SteamLibrary\steamapps\common\Probably Stolen"

.EXAMPLE
    # 指定 Tailscale 上的另一台机器（主机名或 100.x 地址）
    powershell -ExecutionPolicy Bypass -File .\ProbablyAug-Sync.ps1 -Action Setup -PeerName my-laptop

.EXAMPLE
    # 只看看脚本认到了哪些路径
    powershell -ExecutionPolicy Bypass -File .\ProbablyAug-Sync.ps1 -Action Detect
#>
[CmdletBinding()]
param(
    [ValidateSet('Setup', 'Sync', 'Status', 'Daemon', 'Detect', 'Uninstall')]
    [string]$Action = 'Sync',

    [string]$ConfigPath = '',
    [string]$RepoPath = '',
    [string]$RemoteUrl = '',
    [string]$PeerName = '',
    [string]$PeerUrl = '',
    [string]$GameDir = '',
    [string]$ModFolder = '',
    [string]$GameName = '',
    [int]$IntervalMinutes = 0,
    [switch]$NoDeploy,
    [switch]$NoTasks,
    [switch]$NoDaemon
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ---------- 默认值 ----------
# 注意：不能写在 param 默认值里，PS 5.1 + [CmdletBinding()] 下那里取不到 $PSScriptRoot。
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$ScriptPath = if ($PSCommandPath) { $PSCommandPath } else { Join-Path $ScriptDir 'ProbablyAug-Sync.ps1' }
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $env:USERPROFILE '.probably-aug\config.json'
}

# 游戏名：用于自动探测 <Steam库>\steamapps\common\<游戏名>，可用 -GameName 覆盖
$script:GameName = if ($GameName) { $GameName } else { 'Probably Stolen' }

# ---------- 日志 ----------
$script:LogFile = $null

function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'OK', 'WARN', 'ERR')][string]$Level = 'INFO')
    $line = '[{0}] {1,-4} {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    if ($script:LogFile) {
        try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch { }
    }
}

function Limit-Log {
    param([string]$Path, [int]$MaxBytes = 1MB)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return }
        if ((Get-Item -LiteralPath $Path).Length -le $MaxBytes) { return }
        $tail = Get-Content -LiteralPath $Path -Tail 800
        Set-Content -LiteralPath $Path -Value $tail -Encoding UTF8
    } catch { }
}

# ---------- git ----------
$script:GitExe = $null
function Get-GitExe {
    if ($script:GitExe) { return $script:GitExe }
    $cmd = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($cmd) { $script:GitExe = $cmd.Source; return $script:GitExe }
    foreach ($p in @('C:\Program Files\Git\cmd\git.exe', 'C:\Program Files (x86)\Git\cmd\git.exe')) {
        if (Test-Path -LiteralPath $p) { $script:GitExe = $p; $env:PATH = (Split-Path $p) + ';' + $env:PATH; return $p }
    }
    throw '找不到 git.exe，请先安装 Git for Windows'
}

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$GitArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & (Get-GitExe) @GitArgs 2>&1
        $code = $LASTEXITCODE
    } catch {
        $out = @($_.Exception.Message)
        $code = -1
    } finally {
        $ErrorActionPreference = $prev
    }
    $text = if ($out) { (@($out) | ForEach-Object { "$_" }) -join "`n" } else { '' }
    [pscustomobject]@{ Code = $code; Text = $text }
}

# ---------- 网络探测 ----------
function Test-Tcp {
    param([string]$HostName, [int]$Port, [int]$TimeoutMs = 2500)
    if ([string]::IsNullOrWhiteSpace($HostName)) { return $false }
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        if ($client) { $client.Close() }
    }
}

function Get-HostFromUrl {
    param([string]$Url)
    try { return ([uri]$Url).Host } catch { return '' }
}

function Test-RemoteUrl {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    # 本地路径 / UNC 直接算可达（也方便离线自测）
    if ($Url -match '^[a-zA-Z]:[\\/]' -or $Url -match '^\\\\' -or $Url -match '^\.{1,2}[\\/]') { return $true }
    $u = $null
    try { $u = [uri]$Url } catch { return $false }
    if ($u.Scheme -eq 'file') { return $true }
    $port = 443
    if ($u.Port -gt 0) { $port = $u.Port }
    elseif ($u.Scheme -eq 'http') { $port = 80 }
    elseif ($u.Scheme -eq 'git') { $port = 9418 }
    return (Test-Tcp -HostName $u.Host -Port $port -TimeoutMs 3000)
}

function Get-TailscaleExe {
    # 有的机器 PATH 里没有 tailscale.exe（不同安装位置/安装方式），这里按常见位置兜底
    $cmd = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @(
        (Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Tailscale\tailscale.exe'),
        (Join-Path $env:LOCALAPPDATA 'Tailscale\tailscale.exe')
    )) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

function Get-TailscaleIp {
    param([string]$Name = '')
    $ts = Get-TailscaleExe
    if (-not $ts) { return $null }
    try {
        $tsArgs = @('ip', '-4')
        if ($Name) { $tsArgs += $Name }
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $out = & $ts @tsArgs 2>&1
        $code = $LASTEXITCODE
        $ErrorActionPreference = $prev
        if ($code -ne 0) { return $null }
        $ip = @($out | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1)
        if ($ip -and $ip.Count -gt 0) { return $ip[0] }
        return $null
    } catch {
        return $null
    }
}

# ---------- 路径探测（两台电脑路径不同就靠这一段） ----------
function ConvertTo-PlainPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $p = $Path.Trim().Trim('"')
    $p = $p -replace '/', '\'
    $p = $p -replace '^\\\\\?\?\\', ''      # 去掉 \\?\ 前缀
    return $p.TrimEnd('\')
}

function Test-GameDir {
    # 判断一个目录像不像游戏安装目录：<游戏名>.exe / *_Data 目录 / Mods 目录，任一命中即可
    param([string]$Path)
    $p = ConvertTo-PlainPath $Path
    if (-not $p) { return $false }
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    try {
        if (-not (Get-Item -LiteralPath $p -Force).PSIsContainer) { return $false }
    } catch { return $false }
    if ((Split-Path $p -Leaf) -ieq 'Mods') { return $true }
    foreach ($n in @($script:GameName, 'Probably Stolen')) {
        if ($n -and (Test-Path -LiteralPath (Join-Path $p "$n.exe"))) { return $true }
    }
    try {
        if (@(Get-ChildItem -LiteralPath $p -Directory -Filter '*_Data' -ErrorAction SilentlyContinue).Count -gt 0) { return $true }
        if (@(Get-ChildItem -LiteralPath $p -Filter '*.exe' -File -ErrorAction SilentlyContinue).Count -gt 0 -and
            (Test-Path -LiteralPath (Join-Path $p 'Mods'))) { return $true }
    } catch { }
    return $false
}

function Get-SteamRoots {
    # Steam 本体目录：注册表 + 常见安装位置 + 各盘
    $roots = @()
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        try {
            $v = Get-ItemProperty -Path $key -ErrorAction Stop
            foreach ($n in @('SteamPath', 'InstallPath')) {
                $p = ConvertTo-PlainPath $v.$n
                if ($p) { $roots += $p }
            }
        } catch { }
    }
    foreach ($p in @(
        (Join-Path $env:ProgramFiles 'Steam'),
        (Join-Path ${env:ProgramFiles(x86)} 'Steam'),
        'C:\Steam', 'D:\Steam', 'E:\Steam',
        'C:\SteamLibrary', 'D:\SteamLibrary', 'E:\SteamLibrary'
    )) { if ($p) { $roots += $p } }
    try {
        foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
            if ($d.Root -notmatch '^[A-Za-z]:\\$') { continue }
            foreach ($sub in @('SteamLibrary', 'Steam', 'Games\Steam', 'Games\SteamLibrary')) {
                $roots += (Join-Path $d.Root $sub)
            }
        }
    } catch { }
    return @($roots | Where-Object { $_ } | Select-Object -Unique)
}

function Get-SteamLibraries {
    # 所有 Steam 库根目录（即里面含 steamapps 的那一层）
    $libs = @()
    foreach ($root in (Get-SteamRoots)) {
        $r = ConvertTo-PlainPath $root
        if (-not $r) { continue }
        if (Test-Path -LiteralPath (Join-Path $r 'steamapps')) { $libs += $r }
        $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $vdf)) { continue }
        try {
            $text = Get-Content -LiteralPath $vdf -Raw -ErrorAction Stop
            # 新版："path"  "D:\\SteamLibrary"
            foreach ($m in [regex]::Matches($text, '"path"\s*"((?:[^"\\]|\\.)*)"')) {
                $p = ConvertTo-PlainPath ($m.Groups[1].Value -replace '\\\\', '\')
                if ($p -and (Test-Path -LiteralPath (Join-Path $p 'steamapps'))) { $libs += $p }
            }
            # 旧版："1"  "D:\\SteamLibrary"
            foreach ($m in [regex]::Matches($text, '"\d+"\s*"([A-Za-z]:[^"]*)"')) {
                $p = ConvertTo-PlainPath ($m.Groups[1].Value -replace '\\\\', '\')
                if ($p -and (Test-Path -LiteralPath (Join-Path $p 'steamapps'))) { $libs += $p }
            }
        } catch { }
    }
    return @($libs | Where-Object { $_ } | Select-Object -Unique)
}

function Get-GameCandidates {
    param([string]$Name = $script:GameName)
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = $script:GameName }
    $out = @()
    foreach ($lib in (Get-SteamLibraries)) {
        $out += (Join-Path $lib "steamapps\common\$Name")
    }
    try {
        foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
            if ($d.Root -notmatch '^[A-Za-z]:\\$') { continue }
            $out += (Join-Path $d.Root "SteamLibrary\steamapps\common\$Name")
            $out += (Join-Path $d.Root "Steam\steamapps\common\$Name")
            $out += (Join-Path $d.Root "Games\SteamLibrary\steamapps\common\$Name")
            $out += (Join-Path $d.Root "Games\$Name")
            $out += (Join-Path $d.Root $Name)
        }
    } catch { }
    return @($out | Where-Object { $_ } | Select-Object -Unique)
}

function Find-GameDir {
    param([string]$Name = $script:GameName)
    foreach ($c in (Get-GameCandidates -Name $Name)) {
        if (Test-GameDir -Path $c) {
            try { return (Resolve-Path -LiteralPath $c).Path } catch { return $c }
        }
    }
    return $null
}

function Get-ModsDir {
    param($Config)
    $g = ConvertTo-PlainPath $Config.GameDir
    if (-not $g) { return $null }
    if ((Split-Path $g -Leaf) -ieq 'Mods') { return $g }
    return (Join-Path $g 'Mods')
}

# ---------- 配置 ----------
function Get-DefaultHubPath {
    # hub 放纯 ASCII 路径：git daemon 对中文路径的兼容性不稳
    $roots = @(
        (Join-Path $env:PUBLIC 'Probably-Aug-hub'),
        (Join-Path $env:LOCALAPPDATA 'Probably-Aug\hub')
    )
    foreach ($root in $roots) {
        try {
            if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
            if (Test-Path -LiteralPath $root) { return (Join-Path $root 'probably-aug.git') }
        } catch { }
    }
    return (Join-Path $env:USERPROFILE '.probably-aug\hub\probably-aug.git')
}

function Get-DefaultRepoPath {
    # 脚本就放在仓库根，所以仓库路径默认跟脚本走，两台电脑可以完全不同
    if ($ScriptDir -and (Test-Path -LiteralPath (Join-Path $ScriptDir '.git'))) { return $ScriptDir }
    return (Join-Path $env:USERPROFILE 'Probably-Aug')
}

function New-DefaultConfig {
    $hubDir = Join-Path $env:USERPROFILE '.probably-aug'
    [pscustomobject]@{
        ComputerName    = $env:COMPUTERNAME
        RepoPath        = (Get-DefaultRepoPath)
        RemoteUrl       = 'https://github.com/nianxiangchuiyan/Probably-Aug'
        Branch          = 'main'
        GameName        = $script:GameName
        GameDir         = 'D:\SteamLibrary\steamapps\common\Probably Stolen'
        ModFolder       = 'Probably-Aug'
        DeploySource    = ''
        HubPath         = (Get-DefaultHubPath)
        PeerName        = ''
        PeerUrl         = ''
        GitPort         = 9418
        IntervalMinutes = 5
        LogPath         = (Join-Path $hubDir 'sync.log')
        DaemonLog       = (Join-Path $hubDir 'daemon.log')
    }
}

function Get-Config {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return $null }
    try {
        $obj = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "配置文件损坏：$ConfigPath —— 删掉它重跑 -Action Setup"
    }
    $def = New-DefaultConfig
    foreach ($p in $def.PSObject.Properties.Name) {
        if ($null -eq $obj.PSObject.Properties[$p]) {
            $obj | Add-Member -NotePropertyName $p -NotePropertyValue $def.$p
        }
    }
    return $obj
}

function Save-Config {
    param($Config)
    $dir = Split-Path -Parent $ConfigPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}

function Repair-Config {
    # 把配置里的路径按当前电脑校正：仓库 / 游戏目录 / 机器名
    param($Config)
    $changed = $false
    $fromOther = ($Config.ComputerName -and ($Config.ComputerName -ne $env:COMPUTERNAME))
    if ($fromOther) {
        Write-Log "配置来自另一台电脑（$($Config.ComputerName)），按本机路径校正" 'WARN'
    }

    # 仓库：配置的路径上没有 .git 时，优先用脚本所在目录（本机克隆位置可能不同）
    if (-not $Config.RepoPath -or -not (Test-Path -LiteralPath (Join-Path $Config.RepoPath '.git'))) {
        $fallback = Get-DefaultRepoPath
        if (Test-Path -LiteralPath (Join-Path $fallback '.git')) {
            Write-Log "仓库路径不可用（$($Config.RepoPath)），改用：$fallback" 'WARN'
            $Config.RepoPath = $fallback
            $changed = $true
        }
    }

    # 游戏目录：配置的路径不像游戏目录时，自动扫描
    if (-not (Test-GameDir -Path $Config.GameDir)) {
        $name = if ($Config.GameName) { $Config.GameName } else { $script:GameName }
        $found = Find-GameDir -Name $name
        if ($found) {
            Write-Log "游戏目录不可用（$($Config.GameDir)），自动识别为：$found" 'WARN'
            $Config.GameDir = $found
            $changed = $true
        }
    }

    if ($fromOther) { $Config.ComputerName = $env:COMPUTERNAME; $changed = $true }

    if ($changed) {
        try { Save-Config -Config $Config } catch { Write-Log "保存配置失败：$($_.Exception.Message)" 'WARN' }
    }
    return $Config
}

function Get-ConfigOrThrow {
    $c = Get-Config
    if (-not $c) { throw "还没有配置。先运行：powershell -ExecutionPolicy Bypass -File `"$ScriptPath`" -Action Setup" }
    $script:LogFile = $c.LogPath
    Limit-Log -Path $c.LogPath
    $c = Repair-Config -Config $c
    return $c
}

# ---------- 远端 ----------
function Resolve-PeerUrl {
    param($Config)
    if ($Config.PeerName) {
        $hostIp = $Config.PeerName
        if ($hostIp -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
            $hostIp = Get-TailscaleIp -Name $Config.PeerName
            if (-not $hostIp) { return $null }
        }
        $repoName = Split-Path $Config.HubPath -Leaf
        return ('git://{0}:{1}/{2}' -f $hostIp, $Config.GitPort, $repoName)
    }
    if ($Config.PeerUrl) { return $Config.PeerUrl }
    return $null
}

function Ensure-Remote {
    param([string]$Name, [string]$Url)
    $cur = Invoke-Git @('remote', 'get-url', $Name)
    if ($cur.Code -eq 0) {
        if ($cur.Text.Trim() -ne $Url) { Invoke-Git @('remote', 'set-url', $Name, $Url) | Out-Null }
    } else {
        Invoke-Git @('remote', 'add', $Name, $Url) | Out-Null
    }
}

function Test-RemoteBranch {
    param([string]$Remote, [string]$Branch)
    $r = Invoke-Git @('ls-remote', '--heads', $Remote, $Branch)
    if ($r.Code -ne 0) { return $false }
    return ($r.Text.Trim().Length -gt 0)
}

function Get-CurrentBranch {
    $r = Invoke-Git @('symbolic-ref', '--short', 'HEAD')
    if ($r.Code -eq 0 -and $r.Text.Trim()) { return $r.Text.Trim() }
    $r2 = Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD')
    if ($r2.Code -eq 0 -and $r2.Text.Trim() -and $r2.Text.Trim() -ne 'HEAD') { return $r2.Text.Trim() }
    return $null
}

function Ensure-Hub {
    param($Config)
    $hub = $Config.HubPath
    if (Test-Path -LiteralPath $hub) { return }
    $parent = Split-Path -Parent $hub
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $r = Invoke-Git @('init', '--bare', '-q', '-b', $Config.Branch, $hub)
    if ($r.Code -ne 0) { throw "创建 hub 失败：$($r.Text)" }
}

function Get-LocalHubUrl {
    param($Config)
    return ($Config.HubPath -replace '\\', '/')
}

# ---------- 游戏目录链接 ----------
function Remove-Link {
    # 只删链接本身，绝不动链接指向的仓库内容
    param([string]$Path)
    try { [System.IO.Directory]::Delete($Path, $false) }
    catch { Remove-Item -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue }
}

function Ensure-Deploy {
    param($Config, [switch]$Skip)
    if ($Skip) { return 'skipped' }
    if (-not $Config.GameDir -or -not $Config.ModFolder) { return 'disabled' }
    if (-not (Test-Path -LiteralPath (ConvertTo-PlainPath $Config.GameDir))) { return 'no-game-dir' }

    $src = if ($Config.DeploySource) { Join-Path $Config.RepoPath $Config.DeploySource } else { $Config.RepoPath }
    if (-not (Test-Path -LiteralPath $src)) { return 'no-source' }

    $mods = Get-ModsDir -Config $Config
    if (-not (Test-Path -LiteralPath $mods)) { New-Item -ItemType Directory -Path $mods -Force | Out-Null }
    $dst = Join-Path $mods $Config.ModFolder

    if (Test-Path -LiteralPath $dst) {
        $item = Get-Item -LiteralPath $dst -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $target = @($item.Target)[0]
            $target = if ($target) { $target -replace '^\\\\\?\?\\', '' } else { '' }
            try {
                if ($target -and ((Resolve-Path -LiteralPath $target).Path -eq (Resolve-Path -LiteralPath $src).Path)) {
                    return 'ok'
                }
            } catch { }
            Remove-Link -Path $dst
        } else {
            return 'real-dir'
        }
    }

    New-Item -ItemType Junction -Path $dst -Target $src | Out-Null
    return 'created'
}

# ---------- Tailscale daemon ----------
function Test-Daemon {
    param($Config)
    $ip = Get-TailscaleIp
    if (-not $ip) { return $false }
    return (Test-Tcp -HostName $ip -Port $Config.GitPort -TimeoutMs 800)
}

function Stop-Daemon {
    try {
        Get-CimInstance Win32_Process -Filter "Name='git.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -match 'daemon' -and $_.CommandLine -match 'probably' } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch { }
}

function Invoke-Daemon {
    param($Config)
    $script:LogFile = $Config.DaemonLog
    Limit-Log -Path $Config.DaemonLog
    $hubParent = Split-Path -Parent $Config.HubPath
    if (-not (Test-Path -LiteralPath $hubParent)) { New-Item -ItemType Directory -Path $hubParent -Force | Out-Null }
    Ensure-Hub -Config $Config
    $gitExe = Get-GitExe

    while ($true) {
        $ip = Get-TailscaleIp
        if (-not $ip) {
            Write-Log 'Tailscale 未登录 / 无 IPv4，60 秒后重试' 'WARN'
            Start-Sleep -Seconds 60
            continue
        }
        $basePath = $hubParent -replace '\\', '/'
        # 只开 upload-pack（只读）。Windows 上 git daemon 的 receive-pack 会挂死，
        # 所以对端是"只拉不推"：各自把自己的提交推进本机 hub，对端来拉。
        $argStr = ('daemon --reuseaddr --export-all --informative-errors ' +
                   '--listen={0} --port={1} --base-path="{2}" "{2}"' -f $ip, $Config.GitPort, $basePath)
        Write-Log "启动 git daemon：$ip`:$($Config.GitPort) -> $basePath"
        $logDir = Split-Path -Parent $Config.DaemonLog
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $proc = $null
        try {
            $proc = Start-Process -FilePath $gitExe -ArgumentList $argStr -PassThru -WindowStyle Hidden `
                -RedirectStandardOutput (Join-Path $logDir 'daemon.out') `
                -RedirectStandardError (Join-Path $logDir 'daemon.err')
        } catch {
            Write-Log "启动 daemon 失败：$($_.Exception.Message)" 'ERR'
            Start-Sleep -Seconds 30
            continue
        }
        while ($true) {
            Start-Sleep -Seconds 30
            if ($proc.HasExited) {
                Write-Log "daemon 退出（code=$($proc.ExitCode)），5 秒后重启" 'WARN'
                break
            }
            $now = Get-TailscaleIp
            if ($now -ne $ip) {
                Write-Log "Tailscale IP 变化 $ip -> $now，重启 daemon" 'INFO'
                try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch { }
                break
            }
        }
        Start-Sleep -Seconds 5
    }
}

# ---------- 静默启动器 ----------
# 计划任务是"仅在用户登录时运行"（Interactive），直接起 powershell.exe 会闪一个控制台窗口。
# 这里生成一个 VBScript 启动器，用 wscript.exe（GUI 程序，本身没有控制台）以 SW_HIDE 拉起
# PowerShell，任务全程无窗口。
function Get-SilentLauncher {
    if ($script:SilentLauncher -and (Test-Path -LiteralPath $script:SilentLauncher)) { return $script:SilentLauncher }
    $dir = Split-Path -Parent $ConfigPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $vbs = Join-Path $dir 'run-hidden.vbs'
    $body = @'
' Probably-Aug silent launcher - generated by Setup, do not edit (Setup rewrites it)
' Usage: wscript //B //Nologo run-hidden.vbs "<powershell.exe>" "<script path>" [extra args...]
Option Explicit
Dim sh, cmd, i, q, rc
If WScript.Arguments.Count < 2 Then WScript.Quit 1
q = Chr(34)
cmd = q & WScript.Arguments(0) & q & " -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & q & WScript.Arguments(1) & q
For i = 2 To WScript.Arguments.Count - 1
    cmd = cmd & " " & WScript.Arguments(i)
Next
Set sh = CreateObject("WScript.Shell")
' 0 = hidden window, True = wait for the child so the task keeps its exit code and overlap guard
rc = sh.Run(cmd, 0, True)
WScript.Quit rc
'@
    Set-Content -LiteralPath $vbs -Value $body -Encoding ASCII
    $script:SilentLauncher = $vbs
    return $vbs
}

function New-TaskAction {
    # 优先用 wscript 静默启动；机器禁用 Windows Script Host 时退回直接起 powershell（会闪窗）
    param([string]$PsExe, [string]$ActionName)
    $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $launcher = $null
    try { $launcher = Get-SilentLauncher } catch { }
    if ($launcher -and (Test-Path -LiteralPath $wscript)) {
        $argStr = '//B //Nologo "{0}" "{1}" "{2}" -Action {3}' -f $launcher, $PsExe, $ScriptPath, $ActionName
        return (New-ScheduledTaskAction -Execute $wscript -Argument $argStr -WorkingDirectory $ScriptDir)
    }
    $argStr = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Action {1}' -f $ScriptPath, $ActionName
    return (New-ScheduledTaskAction -Execute $PsExe -Argument $argStr -WorkingDirectory $ScriptDir)
}

# ---------- 计划任务 ----------
function Register-Tasks {
    param($Config)
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $ps)) { $ps = 'powershell.exe' }

    $results = @()

    # 同步任务
    try {
        $a = New-TaskAction -PsExe $ps -ActionName 'Sync'
        $t = @(
            (New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME)
            (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
                -RepetitionInterval (New-TimeSpan -Minutes $Config.IntervalMinutes) `
                -RepetitionDuration (New-TimeSpan -Days 3650))
        )
        $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
        Register-ScheduledTask -TaskName 'ProbablyAug-Sync' -Action $a -Trigger $t -Settings $s `
            -Description 'Probably-Aug MOD 自动同步' -Force | Out-Null
        $results += 'ProbablyAug-Sync: OK'
    } catch {
        $results += "ProbablyAug-Sync: 失败（$($_.Exception.Message)）"
    }

    # Tailscale daemon 任务
    try {
        $a2 = New-TaskAction -PsExe $ps -ActionName 'Daemon'
        $t2 = @((New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME))
        $s2 = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) `
            -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
        Register-ScheduledTask -TaskName 'ProbablyAug-Daemon' -Action $a2 -Trigger $t2 -Settings $s2 `
            -Description 'Probably-Aug Tailscale 同步服务' -Force | Out-Null
        $results += 'ProbablyAug-Daemon: OK'
    } catch {
        $results += "ProbablyAug-Daemon: 失败（$($_.Exception.Message)）"
    }

    return $results
}

function Unregister-Tasks {
    $out = @()
    foreach ($n in @('ProbablyAug-Sync', 'ProbablyAug-Daemon')) {
        try {
            Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction Stop
            $out += "$n 已删除"
        } catch {
            $out += "$n 不存在"
        }
    }
    return $out
}

# ---------- 同步核心 ----------
function Invoke-Sync {
    param($Config, [switch]$NoDeploy)

    $repo = $Config.RepoPath
    if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) {
        Write-Log "仓库不存在：$repo" 'ERR'
        return 1
    }

    Ensure-Hub -Config $Config

    $peerUrl = Resolve-PeerUrl -Config $Config
    $peerReachable = $false
    if ($peerUrl) {
        $peerReachable = Test-RemoteUrl -Url $peerUrl
    }

    Push-Location -LiteralPath $repo
    $rc = 0
    try {
        # git remote 必须在仓库里执行
        Ensure-Remote -Name 'origin' -Url $Config.RemoteUrl
        Ensure-Remote -Name 'hub' -Url (Get-LocalHubUrl -Config $Config)
        if ($peerReachable) { Ensure-Remote -Name 'peer' -Url $peerUrl }
        foreach ($m in @('rebase-merge', 'rebase-apply', 'MERGE_HEAD', 'CHERRY_PICK_HEAD')) {
            if (Test-Path -LiteralPath (Join-Path $repo ".git\$m")) {
                Write-Log "仓库有未完成的 $m，先手动处理" 'WARN'
                return 2
            }
        }

        $branch = Get-CurrentBranch
        if (-not $branch) { Write-Log 'detached HEAD，跳过同步' 'WARN'; return 2 }
        if ((Invoke-Git @('rev-parse', '--verify', 'HEAD')).Code -ne 0) {
            Write-Log '仓库还没有任何提交，跳过同步（先提交一次内容）' 'WARN'
            return 2
        }

        if (-not (Invoke-Git @('config', 'user.email')).Text.Trim()) {
            Invoke-Git @('config', 'user.email', "$env:USERNAME@probably-aug.local") | Out-Null
            Invoke-Git @('config', 'user.name', $env:USERNAME) | Out-Null
            Write-Log '本机缺 git 身份，已写入占位身份' 'WARN'
        }

        # 1) 提交
        $committed = $false
        if ((Invoke-Git @('status', '--porcelain')).Text.Trim()) {
            Invoke-Git @('add', '-A') | Out-Null
            $msg = 'sync({0}): {1}' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm')
            $r = Invoke-Git @('commit', '-m', $msg, '--no-verify')
            if ($r.Code -ne 0) { Write-Log "提交失败：$($r.Text)" 'ERR'; return 3 }
            $committed = $true
            Write-Log "已提交：$msg" 'OK'
        } else {
            Write-Log '工作区干净'
        }

        # 2) 可达目标
        $originUp = Test-RemoteUrl -Url $Config.RemoteUrl
        if (-not $originUp) { Write-Log 'GitHub 不可达，走 Tailscale / 本地 hub' 'WARN' }

        $pullables = @()
        $pushables = @()
        if ($originUp) { $pullables += 'origin'; $pushables += 'origin' }
        # peer 只拉不推（Windows 的 git daemon 不支持可靠的 receive-pack）
        if ($peerReachable) { $pullables += 'peer' }
        $pushables += 'hub'

        # 3) 拉取
        $conflict = $false
        foreach ($t in $pullables) {
            if (-not (Test-RemoteBranch -Remote $t -Branch $branch)) {
                Write-Log "  $t 暂无分支 $branch，跳过拉取"
                continue
            }
            $p = Invoke-Git @('pull', '--rebase', '--autostash', '--no-edit', $t, $branch)
            if ($p.Code -ne 0) {
                $files = (Invoke-Git @('diff', '--name-only', '--diff-filter=U')).Text.Trim()
                Invoke-Git @('rebase', '--abort') | Out-Null
                Write-Conflict -Branch $branch -Files $files
                $conflict = $true
                break
            }
            Write-Log "  已从 $t 拉取并 rebase" 'OK'
        }
        if ($conflict) { return 5 }

        # 4) 推送
        foreach ($t in $pushables) {
            for ($i = 1; $i -le 3; $i++) {
                $p = Invoke-Git @('push', $t, $branch)
                if ($p.Code -eq 0) { Write-Log "  已推送到 $t" 'OK'; break }
                if ($p.Text -match 'rejected|non-fast-forward|fetch first') {
                    Write-Log "  $t 拒绝推送，重试 $i/3" 'WARN'
                    $r = Invoke-Git @('pull', '--rebase', '--autostash', '--no-edit', $t, $branch)
                    if ($r.Code -ne 0) {
                        $files = (Invoke-Git @('diff', '--name-only', '--diff-filter=U')).Text.Trim()
                        Invoke-Git @('rebase', '--abort') | Out-Null
                        Write-Conflict -Branch $branch -Files $files
                        return 5
                    }
                    continue
                }
                Write-Log "  推送到 $t 失败：$($p.Text)" 'ERR'
                $rc = 6
                break
            }
        }

        if (-not $originUp -and -not $peerReachable) {
            Write-Log 'GitHub 与 Tailscale 对端都不可达，改动只保存在本机 hub' 'WARN'
            $rc = 4
        } elseif ($committed -and $originUp) {
            Write-Log '同步完成（GitHub 已更新）' 'OK'
        }

        # 5) 部署
        $dep = Ensure-Deploy -Config $Config -Skip:$NoDeploy
        switch ($dep) {
            'ok' { }
            'created' { Write-Log "已建立游戏目录链接：$(Get-ModsDir -Config $Config)\$($Config.ModFolder)" 'OK' }
            'real-dir' { Write-Log "游戏 Mods\$($Config.ModFolder) 是真实目录，未覆盖" 'WARN' }
            'no-game-dir' { Write-Log "游戏目录不存在：$($Config.GameDir)（可用 -Action Detect 或 -GameDir 指定）" 'WARN' }
        }
        return $rc
    } finally {
        Pop-Location
    }
}

function Write-Conflict {
    param([string]$Branch, [string]$Files)
    $marker = Join-Path (Split-Path -Parent $ConfigPath) 'conflict.txt'
    $body = @"
时间 : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
设备 : $env:COMPUTERNAME
分支 : $Branch
冲突 : $Files

处理
1) 打开上面这些文件，手动合并两边内容
2) git add <文件> ... 然后 git rebase --continue
3) 再跑一次 ProbablyAug-Sync.ps1 -Action Sync

已自动 rebase --abort 回滚，本地提交没丢。
"@
    Set-Content -LiteralPath $marker -Value $body -Encoding UTF8
    Write-Log "冲突，已回滚。详情：$marker" 'ERR'
    Write-Host $body -ForegroundColor Yellow
}

# ---------- Setup ----------
function Invoke-Setup {
    $cfg = Get-Config
    if (-not $cfg) { $cfg = New-DefaultConfig }
    $script:LogFile = $cfg.LogPath
    $cfg = Repair-Config -Config $cfg

    if ($RepoPath) { $cfg.RepoPath = ConvertTo-PlainPath $RepoPath }
    if ($RemoteUrl) { $cfg.RemoteUrl = $RemoteUrl }
    if ($PeerName) { $cfg.PeerName = $PeerName }
    if ($PeerUrl) { $cfg.PeerUrl = $PeerUrl }
    if ($GameName) { $cfg.GameName = $GameName }
    $explicitGameDir = -not [string]::IsNullOrWhiteSpace($GameDir)
    if ($explicitGameDir) { $cfg.GameDir = ConvertTo-PlainPath $GameDir }
    if ($ModFolder) { $cfg.ModFolder = $ModFolder }
    if ($IntervalMinutes -gt 0) { $cfg.IntervalMinutes = $IntervalMinutes }
    if ($cfg.IntervalMinutes -lt 1) { $cfg.IntervalMinutes = 5 }
    $cfg.ComputerName = $env:COMPUTERNAME

    $script:LogFile = $cfg.LogPath
    $dir = Split-Path -Parent $cfg.LogPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    # 游戏目录：没给就自动找（显式给了就以用户为准，只提醒）
    if (-not (Test-GameDir -Path $cfg.GameDir)) {
        $name = if ($cfg.GameName) { $cfg.GameName } else { $script:GameName }
        if ($explicitGameDir) {
            Write-Log "指定的游戏目录不存在：$($cfg.GameDir)（仍按它写入配置）" 'WARN'
        } else {
            $found = Find-GameDir -Name $name
            if ($found) {
                Write-Log "自动识别游戏目录：$found" 'OK'
                $cfg.GameDir = $found
            } else {
                Write-Log "没有找到游戏目录（游戏名：$name），稍后用 -GameDir 指定" 'WARN'
            }
        }
    }

    Write-Host ''
    Write-Host '=== Probably-Aug 同步配置 ===' -ForegroundColor Cyan
    Write-Host "  本机      : $env:COMPUTERNAME"
    Write-Host "  仓库路径  : $($cfg.RepoPath)"
    Write-Host "  远端仓库  : $($cfg.RemoteUrl)"
    Write-Host "  游戏目录  : $($cfg.GameDir)"
    Write-Host "  Mod 目录  : $(if (Get-ModsDir -Config $cfg) { Join-Path (Get-ModsDir -Config $cfg) $cfg.ModFolder } else { '未设置' })"
    Write-Host "  Tailscale对端 : $(if ($cfg.PeerName) { $cfg.PeerName } else { '未设置（只用 GitHub）' })"
    Write-Host "  同步间隔  : 每 $($cfg.IntervalMinutes) 分钟"
    Write-Host ''

    # 1) 仓库
    if (Test-Path -LiteralPath (Join-Path $cfg.RepoPath '.git')) {
        Write-Log "仓库已存在：$($cfg.RepoPath)" 'OK'
        Push-Location -LiteralPath $cfg.RepoPath
        Ensure-Remote -Name 'origin' -Url $cfg.RemoteUrl
        Pop-Location
    } else {
        if (Test-Path -LiteralPath $cfg.RepoPath) {
            $inner = Get-ChildItem -LiteralPath $cfg.RepoPath -Force
            if ($inner.Count -gt 0) { throw "目标目录非空且不是 git 仓库：$($cfg.RepoPath)" }
        } else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $cfg.RepoPath) -Force | Out-Null
        }
        Write-Log "克隆 $($cfg.RemoteUrl)"
        $r = Invoke-Git @('clone', $cfg.RemoteUrl, $cfg.RepoPath)
        if ($r.Code -ne 0) { throw "克隆失败：$($r.Text)" }
        Write-Log '克隆完成' 'OK'
    }

    # 2) hub
    Ensure-Hub -Config $cfg
    Push-Location -LiteralPath $cfg.RepoPath
    Ensure-Remote -Name 'hub' -Url (Get-LocalHubUrl -Config $cfg)
    $peerUrl = Resolve-PeerUrl -Config $cfg
    if ($peerUrl) { Ensure-Remote -Name 'peer' -Url $peerUrl }
    Pop-Location
    Write-Log "本地 hub：$($cfg.HubPath)" 'OK'

    # 3) 同步一次（先建好历史，避免空仓库链接）
    $rc = Invoke-Sync -Config $cfg
    Write-Log "首次同步返回：$rc"

    # 4) 部署链接
    $dep = Ensure-Deploy -Config $cfg
    Write-Log "游戏目录部署：$dep"

    # 5) 计划任务
    if ($NoTasks) {
        Write-Log '跳过计划任务注册（-NoTasks）' 'WARN'
    } else {
        foreach ($line in (Register-Tasks -Config $cfg)) { Write-Log $line }
    }

    # 6) daemon
    if ($NoDaemon) {
        Write-Log '跳过 daemon（-NoDaemon）' 'WARN'
    } elseif (Get-TailscaleIp) {
        if (-not (Test-Daemon -Config $cfg)) {
            $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
            $launcher = $null
            try { $launcher = Get-SilentLauncher } catch { }
            if ($launcher -and (Test-Path -LiteralPath $wscript)) {
                # 通过静默启动器拉起，不弹窗口
                Start-Process -FilePath $wscript -WindowStyle Hidden -ErrorAction SilentlyContinue -ArgumentList @(
                    '//B', '//Nologo', ('"{0}"' -f $launcher), ('"{0}"' -f $psExe), ('"{0}"' -f $ScriptPath), '-Action', 'Daemon'
                )
            } else {
                Start-Process -FilePath $psExe -ArgumentList @(
                    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
                    '-File', ('"{0}"' -f $ScriptPath), '-Action', 'Daemon'
                ) -WindowStyle Hidden -ErrorAction SilentlyContinue
            }
            Write-Log '已后台启动 daemon' 'OK'
        }
    } else {
        Write-Log 'Tailscale 未登录，跳过 daemon。登录后重跑 -Action Setup 或手动启动' 'WARN'
    }

    Save-Config -Config $cfg
    Write-Host ''
    Write-Host '=== 完成 ===' -ForegroundColor Green
    Write-Host "  配置：$ConfigPath"
    Write-Host "  日志：$($cfg.LogPath)"
    Write-Host '  手动同步： .\ProbablyAug-Sync.ps1 -Action Sync'
    Write-Host '  查看状态： .\ProbablyAug-Sync.ps1 -Action Status'
    Write-Host '  路径探测： .\ProbablyAug-Sync.ps1 -Action Detect'
    return 0
}

# ---------- Status ----------
function Invoke-Status {
    $cfg = Get-Config
    if (-not $cfg) { Write-Host '尚未配置，运行 -Action Setup' -ForegroundColor Yellow; return 1 }
    $cfg = Repair-Config -Config $cfg

    Write-Host ''
    Write-Host '=== Probably-Aug 同步状态 ===' -ForegroundColor Cyan
    Write-Host "  本机      : $env:COMPUTERNAME"
    Write-Host "  仓库      : $($cfg.RepoPath)"
    Write-Host "  GitHub    : $($cfg.RemoteUrl)"
    Write-Host "  游戏目录  : $($cfg.GameDir)"
    if (-not (Test-Path -LiteralPath (ConvertTo-PlainPath $cfg.GameDir))) {
        $found = Find-GameDir -Name $cfg.GameName
        if ($found) { Write-Host "  自动识别  : $found" -ForegroundColor Yellow }
    }

    $tsIp = Get-TailscaleIp
    if ($tsIp) { Write-Host "  Tailscale : $tsIp" -ForegroundColor Green }
    else { Write-Host '  Tailscale : 未登录' -ForegroundColor Yellow }

    $peerUrl = Resolve-PeerUrl -Config $cfg
    if ($peerUrl) {
        $up = Test-RemoteUrl -Url $peerUrl
        $color = if ($up) { 'Green' } else { 'Yellow' }
        Write-Host "  对端      : $peerUrl  $(if ($up) { '可达' } else { '不可达' })" -ForegroundColor $color
    } else {
        Write-Host '  对端      : 未设置'
    }

    if (Test-RemoteUrl -Url $cfg.RemoteUrl) {
        Write-Host '  GitHub 连通性 : 可达' -ForegroundColor Green
    } else {
        Write-Host '  GitHub 连通性 : 不可达' -ForegroundColor Yellow
    }

    Write-Host "  同步服务  : $(if (Test-Daemon -Config $cfg) { '运行中' } else { '未运行' })"

    $modsDir = Get-ModsDir -Config $cfg
    $dst = if ($modsDir -and $cfg.ModFolder) { Join-Path $modsDir $cfg.ModFolder } else { '' }
    if ($dst -and (Test-Path -LiteralPath $dst)) {
        $item = Get-Item -LiteralPath $dst -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            Write-Host "  游戏链接  : $dst -> $(@($item.Target)[0])" -ForegroundColor Green
        } else {
            Write-Host "  游戏链接  : $dst（真实目录）" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  游戏链接  : 不存在" -ForegroundColor Yellow
    }

    if (Test-Path -LiteralPath (Join-Path $cfg.RepoPath '.git')) {
        Push-Location -LiteralPath $cfg.RepoPath
        try {
            Write-Host "  当前分支  : $((Invoke-Git @('rev-parse','--abbrev-ref','HEAD')).Text.Trim())"
            Write-Host "  最新提交  : $((Invoke-Git @('log','-1','--format=%h %s')).Text.Trim())"
            $dirty = (Invoke-Git @('status', '--porcelain')).Text.Trim()
            Write-Host "  未提交改动: $(if ($dirty) { ($dirty -split "`n").Count } else { 0 })"
            Write-Host '  远端：'
            foreach ($r in @('origin', 'hub', 'peer')) {
                $u = Invoke-Git @('remote', 'get-url', $r)
                if ($u.Code -eq 0) { Write-Host "    $r = $($u.Text.Trim())" }
            }
        } finally { Pop-Location }
    } else {
        Write-Host "  仓库缺失  : $($cfg.RepoPath)" -ForegroundColor Red
    }

    Write-Host ''
    Write-Host '最近日志：'
    if ($cfg.LogPath -and (Test-Path -LiteralPath $cfg.LogPath)) {
        Get-Content -LiteralPath $cfg.LogPath -Tail 12 | ForEach-Object { Write-Host "  $_" }
    }
    Write-Host ''
    return 0
}

# ---------- Detect ----------
function Invoke-Detect {
    $cfg = Get-Config

    Write-Host ''
    Write-Host '=== Probably-Aug 路径探测 ===' -ForegroundColor Cyan
    Write-Host "  本机    : $env:COMPUTERNAME"
    Write-Host "  脚本目录: $ScriptDir"
    Write-Host "  游戏名  : $(if ($cfg -and $cfg.GameName) { $cfg.GameName } else { $script:GameName })"
    Write-Host ''

    Write-Host 'Steam 库：'
    $libs = @(Get-SteamLibraries)
    if ($libs.Count -eq 0) { Write-Host '  （没找到 Steam 库，可能没装 Steam 或装在非常规位置）' -ForegroundColor Yellow }
    foreach ($l in $libs) { Write-Host "  $l" -ForegroundColor Green }

    Write-Host ''
    Write-Host '游戏目录候选：'
    $name = if ($cfg -and $cfg.GameName) { $cfg.GameName } else { $script:GameName }
    foreach ($c in (Get-GameCandidates -Name $name)) {
        if (Test-GameDir -Path $c) {
            Write-Host "  [命中] $c" -ForegroundColor Green
        } else {
            Write-Host "  [  -  ] $c" -ForegroundColor DarkGray
        }
    }

    $found = Find-GameDir -Name $name
    Write-Host ''
    if ($found) {
        Write-Host "自动识别结果：$found" -ForegroundColor Green
        if ($cfg) {
            if ((ConvertTo-PlainPath $cfg.GameDir) -ieq $found) {
                Write-Host '与配置一致' -ForegroundColor Green
            } else {
                Write-Host "配置里是：$($cfg.GameDir)（不一致，跑 -Action Setup 会改正）" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host '没有自动识别到游戏目录，用 -GameDir "<本机游戏目录>" 指定' -ForegroundColor Yellow
    }

    if ($cfg) {
        Write-Host ''
        Write-Host "配置仓库：$($cfg.RepoPath)"
        Write-Host "配置游戏：$($cfg.GameDir)"
        Write-Host "Mod 目标：$(Get-ModsDir -Config $cfg)\$($cfg.ModFolder)"
    }
    Write-Host ''
    return 0
}

# ---------- Uninstall ----------
function Invoke-Uninstall {
    $cfg = Get-Config
    foreach ($l in (Unregister-Tasks)) { Write-Host "  $l" }
    Stop-Daemon
    Write-Host '  daemon 已停止'
    if ($cfg) {
        $modsDir = Get-ModsDir -Config $cfg
        $dst = if ($modsDir -and $cfg.ModFolder) { Join-Path $modsDir $cfg.ModFolder } else { '' }
        if ($dst -and (Test-Path -LiteralPath $dst)) {
            $item = Get-Item -LiteralPath $dst -Force
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                Remove-Link -Path $dst
                Write-Host '  游戏目录链接已删除'
            }
        }
        Write-Host "  仓库保留在：$($cfg.RepoPath)"
    }
    return 0
}

# ---------- 入口 ----------
try {
    switch ($Action) {
        'Setup' { $code = Invoke-Setup }
        'Sync' {
            $cfg = Get-ConfigOrThrow
            $code = Invoke-Sync -Config $cfg -NoDeploy:$NoDeploy
        }
        'Status' { $code = Invoke-Status }
        'Detect' { $code = Invoke-Detect }
        'Daemon' {
            $cfg = Get-ConfigOrThrow
            Invoke-Daemon -Config $cfg
            $code = 0
        }
        'Uninstall' { $code = Invoke-Uninstall }
    }
} catch {
    Write-Host "x $($_.Exception.Message)" -ForegroundColor Red
    if ($script:LogFile) { try { Add-Content -LiteralPath $script:LogFile -Value ("[{0}] ERR  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message) -Encoding UTF8 } catch { } }
    exit 1
}

exit $code
