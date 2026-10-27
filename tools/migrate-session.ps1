<#
.SYNOPSIS
    单会话跨项目迁移（试点用）——把某个会话从一个工作区搬到另一个，只改 header 的 cwd。

.DESCRIPTION
    依据 mb 项目的 notes\_archive\21-迁移操作要点.md。

    与上次的差别：
      * 只重压第 0 帧（header），正文逐字节不动 —— 上次替换了 1,223 处，其中 1,222 处是历史正文；
      * 保留 zstd frame 的 checksum —— 上次 checksum 位 1→0，是静默的完整性降级；
      * 默认先跑 DryRun，输出逐条对应验收判据。

    铁律（不满足就抛错退出，不是提示）：
      1. DSH 必须完全退出（含托盘）。台账在内存里，退出时会回写覆盖脚本的改动。
      2. 目标项目下不得已存在同名会话。
      3. 会话文件永远不原地改：先写 .tmp，校验通过后再替换，原件留在备份里。

.PARAMETER DryRun
    只做：备份 → 生成新文件 → 校验 → 打印清单。不替换、不移动、不删缓存。

.EXAMPLE
    pwsh -File migrate-session.ps1 -DryRun
    pwsh -File migrate-session.ps1
#>
[CmdletBinding()]
param(
    [string]$SessionId   = 'session-47a34c29-23a9-40cb-adb5-e0b58882d99f',
    [string]$FromProject = '--C-Artherine-DSH-Temp--',
    [string]$ToProject   = '--C-Artherine-DSH--',
    [string]$OldCwd      = '',
    [string]$NewCwd      = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# 工作区根不写死：工具在 <根>\tools\，所以根 = 本脚本的父目录。
# 换设备时路径可能不同，推导才不会断。
if (-not $PSBoundParameters.ContainsKey('NewCwd')) { $NewCwd = Split-Path $PSScriptRoot -Parent }
if (-not $PSBoundParameters.ContainsKey('OldCwd')) { $OldCwd = Join-Path $NewCwd 'Temp' }
$dshHome = Join-Path $env:USERPROFILE '.dsh'
$srcDir  = Join-Path $dshHome "sessions\$FromProject\$SessionId"
$dstDir  = Join-Path $dshHome "sessions\$ToProject\$SessionId"
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup  = Join-Path $dshHome "_migration-backup\$stamp"
$zstd    = Join-Path $PSScriptRoot 'zstd-frame-tool.cjs'
$fix     = Join-Path $PSScriptRoot 'fix-header.cjs'

Write-Host "=== 迁移：$SessionId ===" -ForegroundColor Cyan
Write-Host "  从 $FromProject → $ToProject"
Write-Host "  cwd $OldCwd → $NewCwd"
Write-Host "  DryRun = $DryRun`n"

# ---------- 1. 前置自检 ----------
$procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(DSH|DSH Desktop|dsh|electron)$' })
if ($procs.Count -gt 0) {
    $procs | Select-Object Id, Name | Format-Table -AutoSize | Out-String | Write-Host
    throw 'DSH 仍在运行。台账在内存里持有，退出时会回写覆盖——必须完全退出（含托盘）后再跑。'
}
if (-not (Test-Path $srcDir)) { throw "源会话目录不存在: $srcDir" }
if (Test-Path $dstDir)       { throw "目标已存在同名会话，拒绝覆盖: $dstDir" }
if (-not (Test-Path $zstd))  { throw "缺少工具: $zstd" }
if (-not (Test-Path $fix))   { throw "缺少工具: $fix" }
Write-Host '[1/7] 前置自检通过（DSH 已退出、路径干净）' -ForegroundColor Green

# ---------- 2. 选当前代际（vN 最高） ----------
$cands = @(Get-ChildItem $srcDir -File -Filter 'session*.jsonl.zstd' | ForEach-Object {
    $v = if ($_.Name -match '^session\.v(\d+)\.jsonl\.zstd$') { [int]$matches[1] } elseif ($_.Name -eq 'session.jsonl.zstd') { 0 } else { -1 }
    if ($v -ge 0) { [pscustomobject]@{ File = $_; Ver = $v } }
} | Sort-Object Ver -Descending)
if ($cands.Count -eq 0) { throw "找不到 session*.jsonl.zstd: $srcDir" }
$log = $cands[0].File
Write-Host "     当前代际: $($log.Name)  ($($log.Length) B)"

# ---------- 3. 基线 ----------
$baseInfo = & node $zstd info $log.FullName | ConvertFrom-Json
$baseline = [ordered]@{
    frames = $baseInfo.frameCount
    bytes  = $baseInfo.bytes
    lines  = $baseInfo.lines
}
Write-Host ("     基线: 帧={0} 字节={1} 行={2}" -f $baseline.frames, $baseline.bytes, $baseline.lines)

# ---------- 4. 备份 ----------
$bkLogs = Join-Path $backup 'session-logs'
$bkStor = Join-Path $backup 'storages'
New-Item -ItemType Directory -Force -Path $bkLogs, $bkStor | Out-Null
Copy-Item $log.FullName (Join-Path $bkLogs $log.Name) -Force
foreach ($f in @('workspace.json', 'session_projcache.json')) {
    $p = Join-Path $dshHome "storages\$f"
    if (Test-Path $p) { Copy-Item $p (Join-Path $bkStor $f) -Force }
}
$pcOne = Join-Path $dshHome "storages\session_projcache\sessions\$SessionId.json"
if (Test-Path $pcOne) { Copy-Item $pcOne (Join-Path $bkStor 'projcache-session.json') -Force }

$manifest = [ordered]@{
    stamp          = $stamp
    dshHome        = $dshHome
    workspaceRoot  = $NewCwd
    oldPath        = $OldCwd
    newPath        = $NewCwd
    oldSessionDir  = $srcDir
    newSessionDir  = $dstDir
    workspaceId    = $null
    workspaceTitle = $null
    sessionIds     = @($SessionId)
    backupDir      = $backup
    generator      = 'migrate-session.ps1（单会话试点）'
    baseline       = $baseline
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $backup 'manifest.json') -Encoding UTF8
Write-Host "[2/7] 已备份到 $backup" -ForegroundColor Green

# ---------- 5. 只改 header ----------
$tmp = Join-Path $srcDir ($log.Name + '.tmp')
& node $fix $log.FullName $tmp $OldCwd $NewCwd
if ($LASTEXITCODE -ne 0) { throw "fix-header 失败（exit $LASTEXITCODE），未做任何替换" }
$newInfo = & node $zstd info $tmp | ConvertFrom-Json
if ($newInfo.frameCount -ne $baseline.frames) { throw "校验失败：帧数变了 $($baseline.frames) → $($newInfo.frameCount)" }
if ($newInfo.lines       -ne $baseline.lines) { throw "校验失败：行数变了 $($baseline.lines) → $($newInfo.lines)" }
Write-Host ("[3/7] 新文件校验通过：帧 {0}、行 {1}、字节 {2} → {3}" -f $newInfo.frameCount, $newInfo.lines, $baseline.bytes, $newInfo.bytes) -ForegroundColor Green

# ---------- 6. 落地 ----------
$steps = @(
    "把 $($log.Name).tmp 替换为 $($log.Name)",
    "把会话目录移动到 $ToProject",
    "把 $SessionId 的归属从 [$FromProject] 移到 [$ToProject]（第五处：sessionIds）",
    "删除该会话的投影缓存（$SessionId.json），让它重建"
)
if ($DryRun) {
    Write-Host "`n[4/7] DryRun —— 以下步骤未执行：" -ForegroundColor Yellow
    $steps | ForEach-Object { Write-Host "      · $_" }
    # 校验做完了；临时文件留着只会弄脏会话目录（原件与备份都在）
    if (Test-Path $tmp) { Remove-Item $tmp -Force; Write-Host "      （已清理 $($log.Name).tmp）" -ForegroundColor DarkGray }
} else {
    Move-Item $tmp $log.FullName -Force
    Write-Host "[4/7] 已替换会话文件" -ForegroundColor Green

    New-Item -ItemType Directory -Force -Path (Split-Path $dstDir) | Out-Null
    Move-Item $srcDir $dstDir
    Write-Host "[5/7] 已移动到 $dstDir" -ForegroundColor Green

    # 第五处：工作区台账里的归属。
    # 复盘文档 §3 只列了"四处路径"，没有这一处；而它才是"归属"本身。
    # DSH 自己只会做"从旧工作区移除"（它发现目录不在了），不会做"加入新工作区"
    # —— 归组发生在"创建时"，不是"扫描时"。
    $wPath = Join-Path $dshHome 'storages\workspace.json'
    $w = Get-Content $wPath -Raw | ConvertFrom-Json
    $changed = 0
    foreach ($p in $w.tables.workspaces.PSObject.Properties) {
        $ids = @($p.Value.sessionIds)
        if ($p.Value.path -eq $OldCwd -and $ids -contains $SessionId) {
            $p.Value.sessionIds = @($ids | Where-Object { $_ -ne $SessionId })
            $changed++
            Write-Host "     从 [$($p.Value.title)] 移除" -ForegroundColor DarkGray
        }
        if ($p.Value.path -eq $NewCwd -and $ids -notcontains $SessionId) {
            $p.Value.sessionIds = @($ids) + $SessionId
            $changed++
            Write-Host "     加入 [$($p.Value.title)]" -ForegroundColor DarkGray
        }
    }
    if ($changed -gt 0) {
        $w | ConvertTo-Json -Depth 12 | Set-Content $wPath -Encoding UTF8
        Write-Host "[6/7] 台账 sessionIds 已更新（$changed 处）" -ForegroundColor Green
    } else {
        Write-Host "[6/7] 台账 sessionIds 无需改动" -ForegroundColor Yellow
    }

    if (Test-Path $pcOne) { Remove-Item $pcOne -Force }
    Write-Host "[7/7] 已删除投影缓存（会重建）" -ForegroundColor Green
}

# ---------- 验收清单 ----------
Write-Host "`n=== 迁移后验收（缺一即回滚）===" -ForegroundColor Cyan
Write-Host "  ① 新日志首条业务事件不是 seq 0 的 session/end-seed"
Write-Host "  ② 最大 seq ≥ $($baseline.lines - 2)（基线行数 $($baseline.lines)，首两行为 header 与首事件）"
Write-Host "  ③ 行数 ≥ $($baseline.lines)"
Write-Host "  ④ 五处一致（workspace.json path／会话目录名／header cwd／projcache identity.cwd／sessionIds），旧路径残留 0 处"
Write-Host "  ⑤ 【只能人工】GUI 里打开该会话，滚到最顶能看见迁移前的第一条用户消息" -ForegroundColor Yellow
Write-Host "`n  回滚：把 $backup\session-logs\ 覆盖回 $dstDir，目录移回 $FromProject。" -ForegroundColor DarkGray
