<#
.SYNOPSIS
    同一会话在两台设备之间"跃迁"：发布／取回／比对。

.DESCRIPTION
    目标：**不是"两个 session 共享进度"，是"一个 session 跟着人走"。**
    所以全程是"整文件覆盖"，不做合并——因为任何时刻只有一台设备在写。

    要同步的只有两样：
      1. session.v4.jsonl.zstd   —— 会话本体（header 里的 cwd 必须两端一致）
      2. workspace.json          —— 归属（tables.workspaces[<uuid>].sessionIds）
    少第二样，会话内容对、位置对，但**不属于任何项目**（落进"未分组"）。

    硬约束：
      · **所有动作都必须在 DSH 完全关闭时做。** DSH 占着文件句柄，覆盖会失败；
        而且它可能在 flush，抓到半帧。
      · **两端的 C:\Artherine\DSH 必须一致。** 否则 cwd 对不上，就要改用
        migrate-session.ps1 改五处路径——那"之后只需拉取"就不成立了。

    判新旧用 **turn 号**，不用 mtime（跨设备时区/时钟/复制时间全不一样）。

.PARAMETER Action
    status  —— 只读：两端 turn 号、路径、归属，谁新谁旧。**不需要关 DSH。**
    take    —— 取回：远端新 → 备份本地 → 覆盖。需要关 DSH。
    publish —— 发布：本地新 → 复制进 sessions\ → commit。需要关 DSH。
    sync    —— take 然后 publish。

.PARAMETER DryRun
    只打印计划，不动任何文件。

.EXAMPLE
    pwsh -File session-sync.ps1 -Action status
    pwsh -File session-sync.ps1 -Action sync -DryRun
    pwsh -File session-sync.ps1 -Action sync
#>
[CmdletBinding()]
param(
    [ValidateSet('status', 'take', 'publish', 'sync')]
    [string]$Action = 'status',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# 这台机器默认代码页是 936(GBK)。原生命令（node）输出的是 UTF-8，
# 不设这一行，中文字段会被按 GBK 解码——usage 返回里的 "note" 会吃掉引号，
# 报 "Unterminated string. Expected delimiter: `""。2026-10-28 实测过。
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$Root     = Split-Path $PSScriptRoot -Parent
$SyncDir  = Join-Path $Root 'sessions'
$SessionId = 'session-1a212fb6-8418-4172-9eea-4d9f45f9d3c2'
$Cwd      = 'C:\Artherine\DSH'
$ProjDir  = '--C-Artherine-DSH--'

$LiveLog  = Join-Path $env:USERPROFILE ".dsh\sessions\$ProjDir\$SessionId\session.v4.jsonl.zstd"
$LiveWs   = Join-Path $env:USERPROFILE '.dsh\storages\workspace.json'
$SyncLog  = Join-Path $SyncDir "$SessionId.zstd"
$SyncWs   = Join-Path $SyncDir 'workspace.json'
$Zstd     = Join-Path $Root 'tools\zstd-frame-tool.cjs'

# --- node 解析：不能假定它一定在 PATH 上（换 shell 就可能是另一个环境）---
$script:NodeExe = $null
function Resolve-Node {
    if ($script:NodeExe) { return $script:NodeExe }
    $cands = @()
    $cmd = Get-Command node -ErrorAction SilentlyContinue
    if ($cmd) { $cands += $cmd.Source }
    $cands += @(
        'C:\nvm4w\nodejs\node.exe',
        (Join-Path $env:ProgramFiles 'nodejs\node.exe'),
        (Join-Path $env:LOCALAPPDATA 'nvm\node.exe')
    )
    foreach ($x in $cands) { if ($x -and (Test-Path $x)) { $script:NodeExe = $x; return $x } }
    throw '找不到 node.exe（试过 PATH、C:\nvm4w\nodejs、Program Files\nodejs、LOCALAPPDATA\nvm）。'
}

# --- 失败原因必须留下来：只丢一个 -2 等于让人去猜 ---
$script:TurnError = ''
function Get-Turn($path) {
    if (-not (Test-Path $path)) { return -1 }
    $script:TurnError = ''
    try {
        $node = Resolve-Node
        $raw = & $node $Zstd usage $path 2>&1
        $code = $LASTEXITCODE
        if ($code -ne 0) {
            $script:TurnError = "node 退出码 $code：" + (($raw | Select-Object -First 3) -join ' / ')
            return -2
        }
        $u = ($raw -join [Environment]::NewLine) | ConvertFrom-Json
        if (-not $u.newest) { $script:TurnError = 'usage 返回里没有 newest'; return -2 }
        if ($null -eq $u.newest.turn) {
            $script:TurnError = 'usage.newest 里没有 turn，现有键: ' + (($u.newest.PSObject.Properties.Name) -join ',')
            return -2
        }
        return [int]$u.newest.turn
    } catch {
        $script:TurnError = '异常: ' + $_.Exception.Message
        return -2
    }
}

function Format-Turn($t) {
    switch ($t) {
        -1 { '（文件不存在）' }
        -2 {
            if ($script:TurnError) { '（读不出来 —— ' + $script:TurnError + '）' }
            else { '（读不出来）' }
        }
        default { "turn $t" }
    }
}

function Assert-DshClosed {
    $procs = @(Get-Process -Name 'DSH Desktop' -ErrorAction SilentlyContinue)
    if ($procs.Count -gt 0) {
        throw "还有 $($procs.Count) 个 DSH Desktop 进程（Id: $($procs.Id -join ',')）。**完全退出后再跑**——它占着日志文件的句柄，覆盖会失败。"
    }
}

function Show-Status {
    $lt = Get-Turn $LiveLog
    $st = Get-Turn $SyncLog
    Write-Host "`n=== 路径契约 ===" -ForegroundColor Cyan
    Write-Host "  要求的 cwd : $Cwd"
    $alive = Test-Path (Join-Path $env:USERPROFILE ".dsh\sessions\$ProjDir")
    Write-Host ("  本地日志   : {0}" -f $(if ($alive) { '✓ 在' } else { '✗ 不在' })) -ForegroundColor $(if ($alive) { 'Green' } else { 'Red' })
    Write-Host "`n=== turn 号 ===" -ForegroundColor Cyan
    Write-Host ("  本地活件   : {0}" -f (Format-Turn $lt))
    Write-Host ("  仓库快照   : {0}" -f (Format-Turn $st))
    $verdict = if ($lt -eq -1 -and $st -eq -1) { '两边都没有' }
               elseif ($st -le 0) { '仓库里还没有快照 —— 该 publish' }
               elseif ($lt -le 0) { '本地没有 —— 该 take' }
               elseif ($st -gt $lt) { "仓库更新（领先 $($st - $lt) 轮）—— 该 take" }
               elseif ($lt -gt $st) { "本地更新（领先 $($lt - $st) 轮）—— 该 publish" }
               else { '一致' }
    Write-Host "`n  判断: $verdict" -ForegroundColor Yellow
    Write-Host "`n=== 归属 ===" -ForegroundColor Cyan
    foreach ($f in @(@{n='本地'; p=$LiveWs}, @{n='快照'; p=$SyncWs})) {
        if (Test-Path $f.p) {
            try {
                $j = Get-Content $f.p -Raw | ConvertFrom-Json
                $hit = $j.tables.workspaces.PSObject.Properties | Where-Object { $_.Value.path -eq $Cwd }
                if ($hit) {
                    $in = (@($hit.Value.sessionIds) -contains $SessionId)
                    Write-Host ("  {0}: 项目 {1} / 本会话在 sessionIds 里 {2}" -f $f.n, $hit.Name.Substring(0,8), $(if ($in) { '✓' } else { '✗' })) -ForegroundColor $(if ($in) { 'Green' } else { 'Red' })
                } else { Write-Host "  $($f.n): 没有 cwd=$Cwd 的项目" -ForegroundColor Red }
            } catch { Write-Host "  $($f.n): 解析失败" -ForegroundColor Red }
        } else { Write-Host "  $($f.n): 文件不存在" -ForegroundColor Yellow }
    }
    $running = @(Get-Process -Name 'DSH Desktop' -ErrorAction SilentlyContinue).Count
    Write-Host "`n  DSH 进程: $running 个$($(if ($running -gt 0) { ' —— take/publish 会被拒绝' } else { '' }))" -ForegroundColor $(if ($running) { 'Yellow' } else { 'Green' })
}

function Do-Take {
    $lt = Get-Turn $LiveLog; $st = Get-Turn $SyncLog
    if ($st -le 0) { throw '仓库里没有可用的快照，先在一台设备上 publish。' }
    if ($st -le $lt) { Write-Host "  仓库快照不新于本地（$st <= $lt），不覆盖。" -ForegroundColor Yellow; return }
    Write-Host "  仓库 turn $st > 本地 turn $lt → 覆盖本地" -ForegroundColor Cyan
    if ($DryRun) { Write-Host '  [DryRun] 会先备份本地为 .bak-turn<本地turn>，再用快照覆盖。' ; return }
    if ($lt -gt 0) {
        $bak = "$LiveLog.bak-turn$lt"
        Copy-Item $LiveLog $bak -Force
        Write-Host "  已备份 → $bak" -ForegroundColor Green
    }
    $dir = Split-Path $LiveLog -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item $SyncLog $LiveLog -Force
    Copy-Item $SyncWs  $LiveWs  -Force
    Write-Host "  已覆盖日志与 workspace.json" -ForegroundColor Green
    Write-Host "  验: 现在本地 turn $(Get-Turn $LiveLog)"
}

function Do-Publish {
    $lt = Get-Turn $LiveLog; $st = Get-Turn $SyncLog
    if ($lt -le 0) { throw "本地日志不可用（$(Format-Turn $lt)），不能发布。" }
    if ($st -gt $lt) { throw "仓库快照更新（$st > $lt）——先 take，否则会用旧的覆盖新的。" }
    Write-Host "  本地 turn $lt → 复制进 sessions\" -ForegroundColor Cyan
    if ($DryRun) { Write-Host '  [DryRun] 会复制日志与 workspace.json 进 sessions\，然后 git add + commit（不 push）。'; return }
    if (-not (Test-Path $SyncDir)) { New-Item -ItemType Directory -Path $SyncDir -Force | Out-Null }
    Copy-Item $LiveLog $SyncLog -Force
    Copy-Item $LiveWs  $SyncWs  -Force
    $meta = @{ turn = $lt; publishedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); device = $env:COMPUTERNAME; cwd = $Cwd } | ConvertTo-Json
    [System.IO.File]::WriteAllText((Join-Path $SyncDir '.source.json'), $meta)
    $sz = (Get-Item $SyncLog).Length
    Write-Host ("  已写 {0} 文件 / {1:N1} MB" -f 2, ($sz/1MB)) -ForegroundColor Green
    Push-Location $Root
    try {
        & git add sessions
        $s = & git status --porcelain sessions
        if (-not $s) { Write-Host '  git: 没有变化' -ForegroundColor Yellow }
        else {
            & git commit -q -m "session: turn $lt @ $($env:COMPUTERNAME)"
            Write-Host "  git: 已提交 $(git rev-parse --short HEAD)" -ForegroundColor Green
        }
        Write-Host '  下一步（由你）：git push origin HEAD:refs/heads/hub-sync' -ForegroundColor Cyan
    } finally { Pop-Location }
}

# ---------- 主流程 ----------
# 纪律：DryRun 时不"挡门"，只"报情况"——检查该打印结论，不该在打印之前抛错。
$running = @(Get-Process -Name 'DSH Desktop' -ErrorAction SilentlyContinue).Count

if ($Action -eq 'status') { Show-Status; return }

if ($running -gt 0) {
    Write-Host "`n✗ DSH 还开着（$running 个进程）—— take/publish 会被拒绝。" -ForegroundColor Red
    if (-not $DryRun) {
        throw "完全退出 DSH（含托盘）之后再跑。原因：它占着日志文件的句柄，覆盖会失败；而且可能在 flush，抓到半帧。"
    }
    Write-Host '  （DryRun 继续，下面只是计划）' -ForegroundColor Yellow
} else {
    Write-Host "`n✓ DSH 已完全退出" -ForegroundColor Green
}

switch ($Action) {
    'take'    { Do-Take }
    'publish' { Do-Publish }
    'sync'    { Do-Take; Write-Host ''; Do-Publish }
}