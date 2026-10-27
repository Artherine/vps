<#
.SYNOPSIS
    把一个项目从旧目录搬到 projects\<名字>\，连它的会话一起。

.DESCRIPTION
    一次只搬一个项目。设计成"全有或全无"：

      阶段 A：对每个会话只生成并校验 .tmp，**不替换**
      阶段 B：全部校验通过后，才批量替换、移目录、改台账

    任何一步在阶段 A 失败 → 什么都没改。阶段 B 失败 → 会指出去哪拿备份。

    为什么必须先移目录后改台账：台账里的 path 是"项目在哪"的唯一真源；
    目录还没到新位置就改台账，DSH 起来会认为项目失效（判成"未分组"）。

.PARAMETER Project
    QX_MES ／ mb ／ M365

.PARAMETER DryRun
    只做阶段 A 和报告：生成 .tmp、逐项校验、**不替换、不移动、不改台账**。

.EXAMPLE
    pwsh -File migrate-project.ps1 -Project QX_MES -DryRun
    pwsh -File migrate-project.ps1 -Project QX_MES
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('QX_MES', 'mb', 'M365')]
    [string]$Project,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# 工作区根从脚本位置推导：工具在 <根>\tools\，所以根 = 父目录。换设备也不会断。
$Root    = Split-Path $PSScriptRoot -Parent
$dshHome = Join-Path $env:USERPROFILE '.dsh'
$zstd    = Join-Path $PSScriptRoot 'zstd-frame-tool.cjs'
$fix     = Join-Path $PSScriptRoot 'fix-header.cjs'

# 项目定义用**相对路径**，不含盘符
$defs = @{
    'QX_MES' = @{ Old = 'QX_MES';                       New = 'projects\QX_MES' }
    'mb'     = @{ Old = 'workspaces\mb';                New = 'projects\mb' }
    'M365'   = @{ Old = 'workspaces\Microsoft365Issues'; New = 'projects\Microsoft365Issues' }
}
$def     = $defs[$Project]
$oldPath = Join-Path $Root $def.Old
$newPath = Join-Path $Root $def.New

# 会话目录名 = '--' + 路径去掉冒号、反斜杠换 '-' + '--'
function Get-ProjDir([string]$abs) { '--' + ($abs.Replace(':', '') -replace '\\', '-') + '--' }
$oldDirName = Get-ProjDir $oldPath
$newDirName = Get-ProjDir $newPath
$oldSessDir = Join-Path $dshHome "sessions\$oldDirName"
$newSessDir = Join-Path $dshHome "sessions\$newDirName"

$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $dshHome "_migration-backup\$stamp-$Project"

Write-Host "=== 搬项目：$Project ===" -ForegroundColor Cyan
Write-Host "  $oldPath"
Write-Host "  → $newPath"
Write-Host "  会话目录：$oldDirName → $newDirName"
Write-Host "  DryRun = $DryRun`n"

# ---------- 1. 前置自检 ----------
$procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(DSH|DSH Desktop|dsh|electron)$' })
if ($procs.Count -gt 0) {
    $procs | Select-Object Id, Name | Format-Table -AutoSize | Out-String | Write-Host
    throw 'DSH 仍在运行。台账在内存里，退出时会回写——必须完全退出（含托盘）后再跑。'
}
if (-not (Test-Path $oldPath)) { throw "源项目目录不存在: $oldPath" }
if (Test-Path $newPath) {
    # 允许目标预先存在，但只允许它装着 AGENTS.md（那是"先放公告"的合法姿势）
    $extra = @(Get-ChildItem $newPath -Force | Where-Object { $_.Name -ne 'AGENTS.md' })
    if ($extra.Count -gt 0) { throw "目标已存在且含非 AGENTS.md 的内容，拒绝覆盖: $newPath" }
}
if (-not (Test-Path $oldSessDir)) { throw "源会话目录不存在: $oldSessDir" }
if (-not (Test-Path $zstd)) { throw "缺少工具: $zstd" }
if (-not (Test-Path $fix))  { throw "缺少工具: $fix" }
Write-Host '[1/8] 前置自检通过' -ForegroundColor Green

# ---------- 2. 从台账取要搬的会话 ----------
$wPath = Join-Path $dshHome 'storages\workspace.json'
$w = Get-Content $wPath -Raw | ConvertFrom-Json
$wsEntry = $w.tables.workspaces.PSObject.Properties | Where-Object { $_.Value.path -eq $oldPath } | Select-Object -First 1
if (-not $wsEntry) { throw "台账里找不到 path = $oldPath 的工作区" }
$sessionIds = @($wsEntry.Value.sessionIds)
Write-Host ("[2/8] 台账归属会话 {0} 个（题目：{1}）" -f $sessionIds.Count, $wsEntry.Value.title)

# 只搬有内容的；空壳（无文件或最大文件 < 1 KB）跳过
$todo = @()
foreach ($id in $sessionIds) {
    $d = Join-Path $oldSessDir $id
    if (-not (Test-Path $d)) { Write-Host "     跳过（目录不存在）: $id" -ForegroundColor Yellow; continue }
    $f = Get-ChildItem $d -File -Filter 'session*.jsonl.zstd' -ErrorAction SilentlyContinue |
         Sort-Object { if ($_.Name -match '^session\.v(\d+)\.') { [int]$matches[1] } else { 0 } } -Descending |
         Select-Object -First 1
    if (-not $f -or $f.Length -lt 1KB) {
        $sz = if ($f) { $f.Length } else { 0 }
        Write-Host ("     跳过（空壳 {0} B）: {1}" -f $sz, $id) -ForegroundColor Yellow
        continue
    }
    $todo += [pscustomobject]@{ Id = $id; File = $f }
}
Write-Host ("[3/8] 实际要搬 {0} 个会话" -f $todo.Count)

# ---------- 3. 备份 ----------
$bkLogs = Join-Path $backup 'session-logs'
$bkStor = Join-Path $backup 'storages'
New-Item -ItemType Directory -Force -Path $bkLogs, $bkStor | Out-Null
foreach ($t in $todo) { Copy-Item $t.File.FullName (Join-Path $bkLogs ($t.Id + '-' + $t.File.Name)) -Force }
Copy-Item $wPath (Join-Path $bkStor 'workspace.json') -Force

# ---------- 4. 阶段 A：逐个生成并校验 .tmp（不替换） ----------
Write-Host '[4/8] 阶段 A：生成并校验（不替换）' -ForegroundColor Cyan
$prepared = @()
foreach ($t in $todo) {
    $v = & node $zstd info $t.File.FullName | ConvertFrom-Json
    $tmp = $t.File.FullName + '.tmp'
    $fixOut = & node $fix $t.File.FullName $tmp $oldPath $newPath | Out-String
    if ($LASTEXITCODE -ne 0) { throw "fix-header 失败（$($t.Id)），未做任何替换。备份在 $backup" }
    # 把它的校验结论当场打出来——这是唯一"只改了一行"的即时证据，不要再吞掉
    try {
        $fj = $fixOut | ConvertFrom-Json
        Write-Host ("     fix: cwd 替换 {0} 处  checksum {1}  首个不同行 {2}" -f $fj.'cwd替换处数', $fj.'checksum保留', $fj.'首个不同行') -ForegroundColor DarkGray
    } catch { Write-Host '     fix: （报告解析失败，但退出码为 0）' -ForegroundColor Yellow }
    $v2 = & node $zstd info $tmp | ConvertFrom-Json
    if ($v2.frameCount -ne $v.frameCount) { throw "帧数不符（$($t.Id)）：$($v.frameCount) → $($v2.frameCount)" }
    if ($v2.lines      -ne $v.lines)      { throw "行数不符（$($t.Id)）：$($v.lines) → $($v2.lines)" }

    $prepared += [pscustomobject]@{ Id = $t.Id; File = $t.File; Tmp = $tmp; Frames = $v.frameCount; Lines = $v.lines; Bytes = $v.bytes }
    Write-Host ("     ✓ {0}  帧 {1}  行 {2}  {3:N0} B" -f $t.Id, $v.frameCount, $v.lines, $v.bytes)
}

$manifest = [ordered]@{
    stamp = $stamp; project = $Project; dshHome = $dshHome
    oldPath = $oldPath; newPath = $newPath
    oldSessionDir = $oldSessDir; newSessionDir = $newSessDir
    workspaceId = $wsEntry.Name; workspaceTitle = $wsEntry.Value.title
    sessionIds = @($todo.Id); backupDir = $backup
    generator = 'migrate-project.ps1'
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $backup 'manifest.json') -Encoding UTF8
Write-Host "[5/8] 备份就绪：$backup" -ForegroundColor Green

if ($DryRun) {
    Write-Host "`n[6/8] DryRun —— 以下未执行：" -ForegroundColor Yellow
    Write-Host ("      · 替换 {0} 个会话文件的 .tmp" -f $prepared.Count)
    Write-Host "      · 移动这些会话目录到新项目目录下"
    if (Test-Path $newPath) {
        Write-Host "      · 目标目录已存在（只含 AGENTS.md）→ 内容**并入**它，旧壳删掉" -ForegroundColor Yellow
    } else {
        Write-Host "      · 项目目录整体改名到 $newPath"
    }
    Write-Host "      · 改台账 path"
    Write-Host "      · 删投影缓存"
    foreach ($p in $prepared) { if (Test-Path $p.Tmp) { Remove-Item $p.Tmp -Force } }
    Write-Host "      （已清理 .tmp）" -ForegroundColor DarkGray
    return
}

# ---------- 5. 阶段 B：替换 ----------
Write-Host '[6/8] 阶段 B：替换' -ForegroundColor Cyan
foreach ($p in $prepared) { Move-Item $p.Tmp $p.File.FullName -Force }
Write-Host ("      {0} 个文件已替换" -f $prepared.Count) -ForegroundColor Green

# ---------- 6. 移会话目录 ----------
New-Item -ItemType Directory -Force -Path $newSessDir | Out-Null
foreach ($p in $prepared) { Move-Item (Join-Path $oldSessDir $p.Id) (Join-Path $newSessDir $p.Id) -Force }
Write-Host ("[7/8] {0} 个会话目录已移动" -f $prepared.Count) -ForegroundColor Green

# ---------- 7. 移项目目录 ----------
New-Item -ItemType Directory -Force -Path (Split-Path $newPath) | Out-Null
if (Test-Path $newPath) {
    # 目标已存在（只含 AGENTS.md）：把内容移进去再删旧壳，避免目录改名冲突
    Get-ChildItem $oldPath -Force | ForEach-Object { Move-Item $_.FullName (Join-Path $newPath $_.Name) -Force }
    Remove-Item $oldPath -Recurse -Force
    Write-Host "      内容已并入已存在的目标目录（AGENTS.md 保留原地）" -ForegroundColor Green
} else {
    Move-Item $oldPath $newPath
    Write-Host "      项目目录已移动" -ForegroundColor Green
}

# ---------- 8. 改台账 + 删缓存 ----------
$wsEntry.Value.path = $newPath
$w | ConvertTo-Json -Depth 12 | Set-Content $wPath -Encoding UTF8
$cacheDir = Join-Path $dshHome 'storages\session_projcache\sessions'
foreach ($p in $prepared) {
    $c = Join-Path $cacheDir ($p.Id + '.json')
    if (Test-Path $c) { Remove-Item $c -Force }
}
Write-Host "[8/8] 台账 path 已更新；投影缓存已清（会重建）" -ForegroundColor Green

Write-Host "`n=== 验收清单 ===" -ForegroundColor Cyan
Write-Host "  ① 新项目目录存在、旧目录不存在"
Write-Host "  ② 会话目录在 $newDirName\ 下，旧会话目录还剩未归组的（正常）"
Write-Host "  ③ 台账里该工作区 path = $newPath"
Write-Host "  ④ 打开 DSH：项目出现在 projects\ 下、会话能打开、历史滚得到顶"
Write-Host "`n  回滚：把 $backup\session-logs\ 与 storages\workspace.json 覆盖回去，" -ForegroundColor DarkGray
Write-Host "        再把项目目录与会话目录移回原处。" -ForegroundColor DarkGray
