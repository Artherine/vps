<#
.SYNOPSIS
    工作区仓库的日常操作：commit / pull / push / status。

.DESCRIPTION
    架构（2026-10-27 起）：**工作区根本身就是 git 仓库。**

    · 曾经有 `.sync-staging\` 镜像层，**已拆除**——它带来的"哪边是权威"问题比它解决的问题多。
    · **fetch 走 HTTPS**（沙箱里能用）；**push 走 SSH**（只有人能推——沙箱里 ssh.exe 崩在命名管道上）。
      一个 remote 两个 URL 就能同时满足，别改成同一个。
    · `.gitignore` 排除 `projects\` 的工程与运行时。进版本管理的只有：
      `hub\` / `tools\` / `AGENTS.md` / `projects\story` / `projects\roscoe-halfside`。
    · **会话日志（`~\.dsh\sessions\`）不在本仓库内**，它是活件、每回合追加，不进 git。

.PARAMETER Action
    commit —— 把工作副本的改动 add + commit（本地）
    pull   —— fetch 并比较：本地干净且远端领先 → fast-forward；两边都动过 → 停下报告
    push   —— 只打印人该执行的命令（本脚本不推）
    status —— 状态与最近提交

.EXAMPLE
    pwsh -File hub-sync.ps1 -Action status
    pwsh -File hub-sync.ps1 -Action pull
#>
[CmdletBinding()]
param(
    [ValidateSet('commit', 'pull', 'push', 'status')]
    [string]$Action = 'status'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$Branch = 'hub-sync'

function Need-Repo {
    if (-not (Test-Path (Join-Path $Root '.git'))) { throw "工作区根不是 git 仓库: $Root" }
    Set-Location $Root
    $cur = (& git rev-parse --abbrev-ref HEAD).Trim()
    if ($cur -ne $Branch) { Write-Host "注意：当前分支是 $cur，不是 $Branch" -ForegroundColor Yellow }
}

function Get-Count($range) {
    $v = (& git rev-list --count $range 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $v) { return -1 }
    return [int]$v
}

switch ($Action) {

    'commit' {
        Need-Repo
        & git add -A
        $st = & git status --porcelain
        if (-not $st) { Write-Host '没有变化' -ForegroundColor Yellow }
        else {
            $n = @($st).Count
            $msg = 'sync: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + "  ($n 个文件)"
            & git commit -q -m $msg
            Write-Host "已提交 $n 个文件: $msg" -ForegroundColor Green
            & git log --oneline -3
        }
    }

    'pull' {
        Need-Repo
        Write-Host '=== fetch（HTTPS） ===' -ForegroundColor Cyan
        & git fetch origin
        $behind = Get-Count "HEAD..origin/$Branch"
        $ahead  = Get-Count "origin/$Branch..HEAD"
        Write-Host ("本地领先 {0} / 落后 {1}" -f $ahead, $behind)
        if ($behind -le 0) { Write-Host '远端没有新东西' -ForegroundColor Green; break }
        $dirty = & git status --porcelain
        if ($dirty) {
            Write-Host '本地有未提交改动，且远端有新提交 —— 停下。' -ForegroundColor Red
            Write-Host '先 -Action commit，或人工处理冲突。'
            & git log --oneline "HEAD..origin/$Branch"
            break
        }
        if ($ahead -gt 0) {
            Write-Host '两边都动过（本地领先也有提交）—— 停下，需要人工决定。' -ForegroundColor Red
            & git log --oneline "origin/$Branch..HEAD"
            break
        }
        Write-Host '可以 fast-forward，正在合并……' -ForegroundColor Cyan
        & git merge --ff-only "origin/$Branch"
        & git log --oneline -3
        Write-Host '合并完成。建议先读 hub\ledger\index.md 的「最近五条」。' -ForegroundColor Green
    }

    'push' {
        Need-Repo
        Write-Host "`n**这一步得由你来。** 原因是两条硬的：`n" -ForegroundColor Yellow
        Write-Host '  1. 沙箱里 ssh.exe 起不来（could not create signal pipe）；'
        Write-Host '  2. 沙箱里没有 GitHub 凭据。'
        Write-Host "`n要跑的命令：`n"
        Write-Host "  cd `"$Root`""
        Write-Host "  git push origin HEAD:refs/heads/$Branch`n"
        Write-Host '推完可以核对：'
        Write-Host ("  git ls-remote --heads https://github.com/Artherine/vps.git`n")
        $behind = Get-Count "HEAD..origin/$Branch"
        $ahead  = Get-Count "origin/$Branch..HEAD"
        Write-Host ("本地领先 {0} / 落后 {1}" -f $ahead, $behind)
    }

    'status' {
        Need-Repo
        Write-Host '=== 最近提交 ===' -ForegroundColor Cyan
        & git log --oneline -5
        Write-Host "`n=== 未提交的改动 ==="
        $s = & git status --porcelain
        if ($s) { $s } else { '（无）' }
        Write-Host "`n=== 被跟踪的文件 ==="
        $f = & git ls-files
        Write-Host ("{0} 个" -f @($f).Count)
    }
}