<#
.SYNOPSIS
    把本工作区的会话日志搬进仓库，并在原位置留一个 junction。

.DESCRIPTION
    目的：**让会话日志进版本管理，同时不让它变成两份副本。**

    架构：
        ~\.dsh\sessions\--C-Artherine-DSH--\   ← junction
                                ↓
        C:\Artherine\DSH\sessions\             ← 真实目录，在仓库内

    **一份数据，两条路径。** 不做镜像——.sync-staging 那次的教训：两份副本必然产生
    "哪边是权威"的问题，而那比它解决的问题多。

    **必须在 DSH 完全关闭时运行。**

.PARAMETER DryRun
    只跑检查并打印计划，**一个字节都不动**。检查项逐条列结果，失败也照列不抛。

.PARAMETER Rollback
    反向操作：删 junction，把目录搬回 ~\.dsh\sessions\。

.EXAMPLE
    pwsh -File link-sessions.ps1 -DryRun
    pwsh -File link-sessions.ps1
    pwsh -File link-sessions.ps1 -Rollback
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Rollback
)

$ErrorActionPreference = 'Stop'
$Root     = Split-Path $PSScriptRoot -Parent
$Sessions = Join-Path $env:USERPROFILE '.dsh\sessions'
$ProjName = '--C-Artherine-DSH--'
$Link     = Join-Path $Sessions $ProjName
$Real     = Join-Path $Root 'sessions'

function Is-Junction($path) {
    if (-not (Test-Path $path)) { return $false }
    $i = Get-Item $path -Force
    return [bool]($i.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

# ---------- 收集检查 ----------
$checks = New-Object System.Collections.ArrayList
function Add-Check($name, $ok, $detail) {
    [void]$checks.Add([PSCustomObject]@{ Name = $name; Ok = $ok; Detail = $detail })
}

$procs = @(Get-Process -Name 'DSH Desktop' -ErrorAction SilentlyContinue)
Add-Check 'DSH 已完全退出' ($procs.Count -eq 0) $(if ($procs.Count) { "$($procs.Count) 个进程还在（Id: $($procs.Id -join ',')）" } else { '3 个进程都没了' })

if (-not $Rollback) {
    Add-Check '源目录存在' (Test-Path $Link) $Link
    $src = if (Test-Path $Link) {
        $m = Get-ChildItem $Link -Recurse -File -Force | Measure-Object Length -Sum
        Add-Check '源目录有内容' ($m.Count -gt 0) ("{0} 文件 / {1:N1} MB" -f $m.Count, ($m.Sum / 1MB))
        $m
    } else { $null }
    Add-Check '源不是 junction' (-not (Is-Junction $Link)) $(if (Is-Junction $Link) { '已经是 junction 了' } else { '是普通目录' })
    Add-Check '目标不存在或为空' (-not (Test-Path $Real) -or -not (Get-ChildItem $Real -Force -ErrorAction SilentlyContinue)) $Real
    Add-Check 'mklink 可用' ([bool](Get-Command cmd.exe -ErrorAction SilentlyContinue)) 'cmd /c mklink /J'
} else {
    Add-Check '源是 junction' (Is-Junction $Link) $Link
    Add-Check '真实目录存在' (Test-Path $Real) $Real
}

Write-Host "`n=== 检查 ===" -ForegroundColor Cyan
foreach ($c in $checks) {
    $mark = if ($c.Ok) { '✓' } else { '✗' }
    $color = if ($c.Ok) { 'Green' } else { 'Red' }
    Write-Host ("  {0} {1,-16} {2}" -f $mark, $c.Name, $c.Detail) -ForegroundColor $color
}

$failed = @($checks | Where-Object { -not $_.Ok })

# ---------- 计划 ----------
$plan = if (-not $Rollback) {
    @(
        "Move-Item   $Link  →  $Real",
        "mklink /J   $Link  →  $Real",
        '核对：经 junction 读到的文件数与字节数必须和搬之前一致',
        '不做：任何 git 操作（那是下一步，由你决定）'
    )
} else {
    @(
        "rmdir       $Link  （只删 junction，不删文件）",
        "Move-Item   $Real  →  $Link",
        '核对：文件数与字节数'
    )
}

Write-Host "`n=== 计划 ===" -ForegroundColor Cyan
$plan | ForEach-Object { Write-Host "  $_" }

if ($DryRun) {
    Write-Host "`n[DryRun] 什么都没动。" -ForegroundColor Yellow
    if ($failed.Count) {
        Write-Host ("有 {0} 项检查未通过 —— 真跑会拒绝执行：" -f $failed.Count) -ForegroundColor Red
        $failed | ForEach-Object { Write-Host ("  · {0}: {1}" -f $_.Name, $_.Detail) -ForegroundColor Red }
    } else {
        Write-Host '所有检查通过 —— 去掉 -DryRun 就会执行。' -ForegroundColor Green
    }
    return
}

if ($failed.Count) {
    throw ("{0} 项检查未通过，拒绝执行。先跑 -DryRun 看清每一条。" -f $failed.Count)
}

# ---------- 执行 ----------
if (-not $Rollback) {
    '=== 正向：搬进仓库 + 建 junction ==='
    $before = (Get-ChildItem $Link -Recurse -File -Force | Measure-Object Length -Sum)
    Move-Item $Link $Real
    Write-Host "  已搬 → $Real" -ForegroundColor Green
    & cmd /c mklink /J "$Link" "$Real" | Out-Null
    if (-not (Test-Path $Link)) { throw "junction 建失败。目录已搬到 $Real，手工建链接或 -Rollback。" }
    Write-Host "  已建 junction: $Link → $Real" -ForegroundColor Green
    $after = (Get-ChildItem $Link -Recurse -File -Force | Measure-Object Length -Sum)
    Write-Host ("  经 junction 读到: {0} 文件 / {1:N1} MB（搬前 {2} / {3:N1} MB）" -f $after.Count, ($after.Sum/1MB), $before.Count, ($before.Sum/1MB))
    if ($after.Count -ne $before.Count -or $after.Sum -ne $before.Sum) { throw '数量对不上！关 DSH 后 -Rollback 退回。' }
    Write-Host "`n  下一步：" -ForegroundColor Cyan
    Write-Host '    1. 开 DSH，确认这个会话能打开、历史在'
    Write-Host "    2. cd $Root; git add -A; git commit -m 'sessions: 纳入版本管理'"
    Write-Host '    3. git push origin HEAD:refs/heads/hub-sync'
    Write-Host "`n  若 DSH 认不出这个会话：关 DSH → pwsh -File link-sessions.ps1 -Rollback" -ForegroundColor Yellow
}
else {
    '=== 反向：删 junction + 搬回去 ==='
    & cmd /c rmdir "$Link" | Out-Null
    Write-Host '  已删 junction' -ForegroundColor Green
    Move-Item $Real $Link
    Write-Host "  已搬回 → $Link" -ForegroundColor Green
    $n = (Get-ChildItem $Link -Recurse -File -Force | Measure-Object Length -Sum)
    Write-Host ("  验: {0} 文件 / {1:N1} MB" -f $n.Count, ($n.Sum/1MB))
}