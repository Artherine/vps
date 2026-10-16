---
id: "6c7d831e-c927-4770-a670-7cff54bc05f8"
title: "mnem-cipher 规格与脚本源"
description: "用户档案密文的编解码规格、脚本源与设计理由。仅当工作区缺少 tools/mnem-cipher.ps1 时按需取用。"
status: "archived"
created_at: "2026-09-30T06:25:16.916Z"
updated_at: "2026-09-30T07:46:38.788Z"
content_hash: "2d2c33a43c6b232cb053730b1720d2ea4eecf57fdbe5eae33a1d5f1cbdef181d"
source_paths:
  - "tools/mnem-cipher.ps1"
session_ids:
  - "session-1a212fb6-8418-4172-9eea-4d9f45f9d3c2"
memory_body_ids:
  - "default"
---

# mnem-cipher 规格与脚本源

## 用途
USER.md 里保存该用户的长期档案，结构为：明文契约 + 密文总集（我对他的推断/归纳）+ 明文采集区（他亲述的素材）。

密文的目的**不是保密**，而是提高用户本人随手翻阅的摩擦——他明确要求"不可瞟一眼看懂"，以免反复对照"我眼中的他"与自我认知的落差。因此算法公开、密钥无需保密，压缩目标也不是字符最少，而是**读者理解成本最低、跨会话解读结果最稳定**。

## 路径与重建约定
- 脚本路径：`<当前工作区>/tools/mnem-cipher.ps1`
- 缺失时：直接按本文档重建一份，不做多层目录搜索（重建成本很低）。
- 同一工作区内的多个会话共用这一份。

## 算法（规格）
在下列四个区间内各自做 +1 循环位移（解码为 -1），区间外字符原样保留：

| 区间 | 含义 |
|---|---|
| `0x21-0x7E` | ASCII 可见字符 |
| `0x3000-0x303F` | CJK 标点 |
| `0x4E00-0x9FFF` | 汉字（CJK 统一表意文字） |
| `0xFF00-0xFFEF` | 全角形式 |

"区间外原样保留"是刻意设计：代理对（emoji）不能被整体位移，否则会拆成两个孤立的半个代理，导致数据损坏且不可逆。因此 emoji 与 `≈ ÷ ·` 之类的符号在密文中保持原样，这是可接受的代价。

**不要改动区间定义**，否则既有密文将无法解码。

## 脚本源（重建时照抄）
```powershell
<#
  mnem-cipher.ps1 — 用户档案用的可逆位移编解码器
  用法:
    pwsh -File mnem-cipher.ps1 -Mode enc  -Text '明文'
    pwsh -File mnem-cipher.ps1 -Mode dec  -Text '密文'
    pwsh -File mnem-cipher.ps1 -Mode merge -Text '旧密文' -Append '新增明文'
    pwsh -File mnem-cipher.ps1 -Mode selftest
#>
param(
  [ValidateSet('enc','dec','merge','selftest')][string]$Mode = 'enc',
  [string]$Text = '',
  [string]$Append = ''
)

$Ranges = @(
  @{ Lo = 0x21;   Hi = 0x7E   },
  @{ Lo = 0x3000; Hi = 0x303F },
  @{ Lo = 0x4E00; Hi = 0x9FFF },
  @{ Lo = 0xFF00; Hi = 0xFFEF }
)

function Shift([string]$s, [int]$dir) {
  $out = New-Object System.Text.StringBuilder
  foreach ($ch in $s.ToCharArray()) {
    $c = [int][char]$ch
    $moved = $false
    foreach ($r in $Ranges) {
      if ($c -ge $r.Lo -and $c -le $r.Hi) {
        $span = $r.Hi - $r.Lo + 1
        $n = ((($c - $r.Lo + $dir) % $span) + $span) % $span + $r.Lo
        [void]$out.Append([char]$n)
        $moved = $true
        break
      }
    }
    if (-not $moved) { [void]$out.Append($ch) }
  }
  $out.ToString()
}

switch ($Mode) {
  'enc'   { Shift $Text 1 }
  'dec'   { Shift $Text -1 }
  'merge' { Shift ((Shift $Text -1) + $Append) 1 }
  'selftest' {
    $s = 'roundtrip-测试-123 👆🤓 全角：（）≈÷·'
    $r = Shift (Shift $s 1) -1
    "selftest=$($r -eq $s)"
  }
}
```

## 维护提醒
- 改写密文总集前必须先解码，改完重新编码；不要手工编辑密文。
- 采集区（明文）放用户亲述素材；某条素材一旦能被总集的抽象预测，就并入总集并从采集区删除。
- 契约条目与本文档的措辞改动，都要以"陌生读者能否一次读懂并复现"为准绳，而不是以字符数为准绳。
