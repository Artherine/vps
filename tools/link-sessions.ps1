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

    **必须在 DSH 完全关闭时运行。** 脚本会检查；有三个以上 DSH Desktop 进程就拒绝
    （含托盘驻留时进程仍在）。

.PARAMETER Rollback
    反向操作：删 junction，把目录搬回 ~\.dsh\sessions\。

.EXAMPLE
    pwsh -File link-sessions.ps1
    pwsh -File link-sessions.ps1 -Rollback
#>
[CmdletBinding()]
param([switch]$Rollback)

$ErrorActionPreference = 'Stop'
$Root     = Split-Path $PSScriptRoot -Parent
$Sessions = Join-Path $env:USERPROFILE '.dsh\sessions'
$ProjName = '--C-Artherine-DSH--'
$Link     = Join-Path $Sessions $ProjName
$Real     = Join-Path $Root 'sessions'

function Assert-DshClosed {
    $procs = @(Get-Process -Name 'DSH Desktop' -ErrorAction SilentlyContinue)
    if ($procs.Count -gt 0) {
        $procs | Format-Table Id, ProcessName -AutoSize | Out-String | Write-Host
        throw "还有 $($procs.Count) 个 DSH Desktop 进程。**完全退出（含托盘）之后再跑**——台账在内存里，退出时会回写。"
    }
    Write-Host '  DSH 已完全退出 ✓' -ForegroundColor Green
}

function Is-Junction($path) {
    if (-not (Test-Path $path)) { return $false }
    $i = Get-Item $path -Force
    return [bool]($i.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

if (-not $Rollback) {
    '=== 正向：搬进仓库 + 建 junction ==='
    Assert-DshClosed

    if (-not (Test-Path $Link)) { throw "源目录不存在: $Link" }
    if (Test-Path $Real) {
        $n = @(Get-ChildItem $Real -Force -ErrorAction SilentlyContinue).Count
        throw "目标已存在且非空: $Real（$n 项）。先确认它是什么，或 -Rollback 后再试。"
    }
    if (Is-Junction $Link) { throw "源已经是 junction 了，不需要再做: $Link" }

    $src = (Get-ChildItem $Link -Recurse -File -Force | Measure-Object Length -Sum)
    Write-Host ("  源: {0} 文件 / {1:N1} MB" -f $src.Count, ($src.Sum / 1MB))

    # 1) 搬
    Move-Item $Link $Real
    Write-Host "  已搬 → $Real" -ForegroundColor Green

    # 2) 建 junction（mklink /J 不需要管理员）
    & cmd /c mklink /J "$Link" "$Real" | Out-Null
    if (-not (Test-Path $Link)) { throw "junction 建失败。目录已搬到 $Real，手工建链接或把目录搬回去。" }
    Write-Host "  已建 junction: $Link → $Real" -ForegroundColor Green

    # 3) 验
    $after = (Get-ChildItem $Link -Recurse -File -Force | Measure-Object Length -Sum)
    Write-Host ("  经 junction 读到: {0} 文件 / {1:N1} MB" -f $after.Count, ($after.Sum / 1MB))
    if ($after.Count -ne $src.Count) { throw "数量对不上！先别开 DSH，用 -Rollback 退回。" }

    Write-Host ''
    Write-Host '  下一步：' -ForegroundColor Cyan
    Write-Host "    1. 开 DSH，确认这个会话能打开、历史在"
    Write-Host "    2. cd $Root; git add -A; git commit -m 'sessions: 纳入版本管理'"
    Write-Host "    3. git push origin HEAD:refs/heads/hub-sync"
    Write-Host ''
    Write-Host '  如果 DSH 认不出这个会话（路径规范化可能破掉 junction）：' -ForegroundColor Yellow
    Write-Host '    关 DSH → pwsh -File link-sessions.ps1 -Rollback → 它会恢复原样'
}
else {
    '=== 反向：删 junction + 搬回去 ==='
    Assert-DshClosed
    if (-not (Is-Junction $Link)) { throw "源不是 junction，没什么可回滚: $Link" }
    if (-not (Test-Path $Real)) { throw "真实目录不存在: $Real" }
    & cmd /c rmdir "$Link" | Out-Null
    Write-Host '  已删 junction' -ForegroundColor Green
    Move-Item $Real $Link
    Write-Host "  已搬回 → $Link" -ForegroundColor Green
    $n = (Get-ChildItem $Link -Recurse -File -Force | Measure-Object Length -Sum)
    Write-Host ("  验: {0} 文件 / {1:N1} MB" -f $n.Count, ($n.Sum / 1MB))
}