<#
.SYNOPSIS
    把该上云的那几样（hub\ / tools\ / AGENTS.md / story / roscoe）同步到云仓库的一个分支上。

.DESCRIPTION
    架构：**hub\ 不是 git 仓库**，`.sync-staging\` 才是。
    原因：projects\ 有 9.5 GB，把工作区整体交给 git 会让每次 status 扫全树；
          而真正要上云只有 hub\（约 120 KB）。

    分工（重要）：
      · 本脚本能 **stage / status / pull**（都在本地或只读）
      · **push 必须由人来**——沙箱里没有 GitHub 凭据，且 credential helper 调 sh.exe 会撞命名管道限制

.PARAMETER Action
    init   —— 建暂存区并挂远端（一次性）
    stage  —— 把 hub\ 复制进暂存区，add + commit（本地）
    status —— 看最近提交与未提交改动
    push   —— 打印应该由人执行的命令（本脚本不推）
    pull   —— fetch 远端分支并列出差异（只读）

.EXAMPLE
    pwsh -File hub-sync.ps1 -Action init
    pwsh -File hub-sync.ps1 -Action stage
    pwsh -File hub-sync.ps1 -Action status
#>
[CmdletBinding()]
param(
    [ValidateSet('init', 'stage', 'status', 'push', 'pull')]
    [string]$Action = 'stage'
)

$ErrorActionPreference = 'Stop'
$Root    = Split-Path $PSScriptRoot -Parent          # 工作区根 = tools\ 的父目录
$hub     = Join-Path $Root 'hub'
$stage   = Join-Path $Root '.sync-staging'
$remote  = 'https://github.com/Artherine/vps.git'
$branch  = 'hub-sync'

function Need-Git { if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw '找不到 git' } }

switch ($Action) {

    'init' {
        Need-Git
        if (-not (Test-Path $hub)) { throw "hub\ 不存在: $hub" }
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        Push-Location $stage
        try {
            if (-not (Test-Path (Join-Path $stage '.git'))) { & git init -q }
            & git config user.name  'dsh-hub-sync'
            & git config user.email 'hub@localhost'
            $r = & git remote 2>&1
            if ($r -notmatch 'origin') { & git remote add origin $remote }
            # 验：读回来，读到的才写进日志。别把"我设了这个变量"当成"这件事成了"
            $rv = (& git remote -v 2>&1) -join "`n"
            if ($rv -notmatch 'origin') { throw "origin 没加上。检查 $stage 的 git 配置，别照着一行‘成功日志’去 push。" }
            Write-Host "`n暂存区: $stage"
            Write-Host "远端（读回来的）:"
            $rv -split "`n" | ForEach-Object { Write-Host "  $_" }
            Write-Host "分支: $branch" -ForegroundColor Green
        } finally { Pop-Location }
    }

    'stage' {
        Need-Git
        if (-not (Test-Path (Join-Path $stage '.git'))) { throw "暂存区还没初始化，先跑 -Action init" }
        # 清空暂存区内容（保留 .git），再镜像"该上云的那几样"
        # 判据见 hub\README.md 那张表：本体 ✓ / 作品 ✓ / 参考资料 ✗ / 可重建 ✗
        Get-ChildItem $stage -Force | Where-Object { $_.Name -ne '.git' } | Remove-Item -Recurse -Force
        $maps = @(
            @{ src = $hub;                                         dst = 'hub' },
            @{ src = (Join-Path $Root 'tools');                    dst = 'tools' },
            @{ src = (Join-Path $Root 'AGENTS.md');                dst = 'AGENTS.md' },
            @{ src = (Join-Path $Root 'projects\story');           dst = 'projects\story' },
            @{ src = (Join-Path $Root 'projects\roscoe-halfside'); dst = 'projects\roscoe-halfside' }
        )
        foreach ($m in $maps) {
            if (-not (Test-Path $m.src)) { Write-Host "跳过（不存在）: $($m.dst)" -ForegroundColor Yellow; continue }
            $target = Join-Path $stage $m.dst
            $parent = Split-Path $target -Parent
            if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item $m.src $target -Recurse -Force
        }
        # 会话日志（~\.dsh\sessions）不在本脚本范围：它 29.5 MB 且每回合追加，见 ledger 里关于多端的讨论
        Push-Location $stage
        try {
            & git add -A
            $st = & git status --porcelain
            if (-not $st) { Write-Host '没有变化，无需提交' -ForegroundColor Yellow }
            else {
                $msg = 'sync: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')
                & git commit -q -m $msg
                Write-Host "已提交: $msg" -ForegroundColor Green
                & git log --oneline -3
            }
        } finally { Pop-Location }
    }

    'status' {
        Need-Git
        if (-not (Test-Path (Join-Path $stage '.git'))) { throw '暂存区还没初始化' }
        Write-Host '=== 暂存区最近提交 ==='
        & git -C $stage log --oneline -5
        Write-Host "`n=== 未提交的改动 ==="
        $s = & git -C $stage status --porcelain
        if ($s) { $s } else { '（无）' }
        Write-Host "`n=== 暂存区里的内容 ==="
        Get-ChildItem (Join-Path $stage 'hub') -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum | ForEach-Object { '  {0} 个文件，{1:N1} KB' -f $_.Count, ($_.Sum / 1KB) }
    }

    'push' {
        Write-Host @"
**这一步得由你来。** 原因是两条硬的：

  1. 沙箱里没有 GitHub 凭据（`fatal: could not read Username`）；
  2. `credential.helper = manager` 会调 `sh.exe`，撞上沙箱的命名管道限制。

要跑的命令：

  cd "$stage"
  git push origin HEAD:refs/heads/$branch

第一次推会自动在远端创建 `$branch` 分支。推完可以核对：

  git ls-remote --heads $remote

"@ -ForegroundColor Cyan
    }

    'pull' {
        Need-Git
        if (-not (Test-Path (Join-Path $stage '.git'))) { throw '暂存区还没初始化' }
        Push-Location $stage
        try {
            # 用显式 HTTPS URL，不依赖 remote 配置——SSH 在沙箱里会崩（命名管道）
            & git fetch $remote $branch 2>&1 | Write-Host
            if ($LASTEXITCODE -ne 0) { Write-Host '远端还没有这个分支（第一次推之前是正常的）' -ForegroundColor Yellow; return }
            Write-Host "`n=== 远端有、本地没有的提交 ==="
            $d = & git log --oneline HEAD..FETCH_HEAD 2>&1
            if ($d) { $d } else { '（无差异）' }
            Write-Host "`n**本脚本不自动合并**——先看差异，再决定。" -ForegroundColor Yellow
        } finally { Pop-Location }
    }
}
