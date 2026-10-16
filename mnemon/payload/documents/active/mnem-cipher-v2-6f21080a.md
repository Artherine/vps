---
id: "6f21080a-3dde-452d-9fb0-491bee037a18"
title: "mnem-cipher 规格 v2（现行）与四轮验证记录"
description: "现行规格 v2（两区间位移）、脚本源、四轮陌生读者验证结果与规格设计教训。取代此前两份已过期的同主题文档。"
status: "active"
created_at: "2026-09-30T06:38:31.014Z"
updated_at: "2026-09-30T06:38:31.014Z"
content_hash: "c18311581154e5d0539ec3356730199820e8561c6e92bcc44e41214cc5fdad4b"
source_paths:
  []
session_ids:
  - "session-1a212fb6-8418-4172-9eea-4d9f45f9d3c2"
memory_body_ids:
  []
---

# mnem-cipher 规格 v2（现行）与四轮验证记录

> 本文档取代此前两份：《mnem-cipher 规格与脚本源》（记 v1 算法，已过期）与《用户档案契约的陌生读者解读实测（3 探针）与规格修正》（仅含第 1 轮）。旧两份可在获得 root 授权后归档。

## 一、用途与设计目标
USER.md 保存该用户的长期档案：明文契约（规则层）+ 密文总集（我对他的推断/归纳）+ 明文采集区（他亲述的素材）。

密文**不是保密措施**，而是提高用户本人随手翻阅的摩擦——他明确要求"瞟一眼看不懂"，以免反复对照"我眼中的他"与自我认知的落差。因此算法公开、密钥无需保密。压缩的准绳是**陌生读者一次读懂并能复现**，不是字符最少。

## 二、现行规格 v2

**处理单位**：Unicode 码点，逐字符独立处理（非 UTF-16 码元、非字节）。

**两个闭区间（含端点）**，各自独立循环位移，不跨区间、不与 Unicode 全域回绕：

| 区间 | 含义 |
|---|---|
| `0x21–0x7E` | ASCII 可见字符 |
| `0x4E00–0x9FFF` | 汉字（CJK 统一表意文字；**不含扩展区与兼容汉字，属有意**） |

**方向**：编码 = +1，解码 = −1；到区间上界再加则回绕到本区间下界，反之亦然。

**区间外一律原样**：emoji、空格（U+0020）、中文/全角标点、U+3003 等。
⚠️ **注意**：ASCII 标点（`! " # … ~`）落在 ASCII 区间**之内**，照常参与位移——"标点不位移"只对中文/全角标点成立。

**字面算术**：不对输出做规范化或字符替换；位移落点若为未分配码点，也照原样输出，不跳过、不替换。

**为什么不能整体 +1**：emoji 是代理对，逐码元位移会拆出孤立半代理，数据损坏且不可逆。

### v2 相对 v1 的改动
v1 使用四个区间（多出 CJK标点 0x3000–0x303F 与 全角/半宽 0xFF00–0xFFEF）。这两个区间只覆盖标点，提供不了额外混淆，却带来三处成本：`0xFF00–0xFFEF` 命名不实（实含半宽片假名/谚文）、端点位移会产出未分配码点、以及两个额外转写点。v2 删除它们。

## 三、脚本与路径
- 路径：`<当前工作区>/tools/mnem-cipher.ps1`；缺失即按本文档重建，不做多层目录搜索。
- 重建后**必须先跑 `-Mode selftest` 确认往返成功**再使用（转写丢失是静默的）。
- 接口：`enc` / `dec` / `merge` / `selftest`；`merge` 作用于单条密文＝`enc(dec(该条) + 新明文)`。
- 同工作区的多个会话共用这一份。

```powershell
<#
  mnem-cipher.ps1 — 用户档案用的可逆位移编解码器（规格 v2）
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
  @{ Lo = 0x4E00; Hi = 0x9FFF }
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
    $s = 'roundtrip-测试-123 👆🤓 （）≈÷·'
    $r = Shift (Shift $s 1) -1
    "selftest=$($r -eq $s)"
  }
}
```

## 四、四轮陌生读者验证（每轮 3 个无上下文子代理）
| 轮 | 规格 | 结果 |
|---|---|---|
| 1 | v0（四区间，方向未写明） | 3/3 解对，但 **3/3 指出"方向"未写明**、靠样本反推；1/3 转写时静默丢掉 emoji |
| 2 | v1 | 端到端自举成功（能检索档案、重建脚本、自检、解码）；纯散文复现全对但指出多处可猜；降级情形挖出**"区间内未分配码点"歧义** |
| 3 | v1 + 补丁 | 3/3 全对，含端点回绕新向量；未分配码点规则 3/3 复述一致 |
| 4 | v2（两区间） | 3/3 全对；抓到**"含标点"措辞不准确**（ASCII 标点在区间内会位移）与**测试向量文案过期**（写着"四区间"而 v2 只有两个） |

## 五、可复用的规格设计教训
1. **方向、区间端点、回绕范围必须显式写出**，不能靠示例反推——示例只能验证，不能定义。
2. **往返自检只是必要条件**：任何双射置换都满足，连恒等映射都满足。更强的判据是"重编码回原密文逐字符相等"＋"明文语义通顺"。
3. **自举式工具要内置往返自检**：转写错误是静默的（已实测发生）。
4. **压缩的准绳是陌生读者的理解成本与解读稳定性**，不是字符数。
5. **规格作者自审无效**：让无上下文读者去复现，才能暴露作者看不见的歧义。
6. **测试向量也会过期**：规格改版后，向量里的示例文案要一起改，否则读者会把它当成规格矛盾。
7. 措辞里的括注尤其危险：一句"含标点"就与区间算术自相矛盾。
