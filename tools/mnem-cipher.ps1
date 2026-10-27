<#
  mnem-cipher.ps1 — 用户档案用的可逆位移编解码器（规格 v2）

  规格 v2：仅在下列两个闭区间内各自做 +1 / −1 循环位移（到界回绕到本区间另一端），
           区间外字符原样保留。
             ASCII 可见区 0x21-0x7E
             汉字        0x4E00-0x9FFF

  相对 v1 的改动：删去 CJK标点(0x3000-0x303F) 与 全角/半宽(0xFF00-0xFFEF) 两个区间。
  理由：这两个区间只覆盖标点，提供不了额外混淆，却带来三处成本——"全角"命名不准
  （该区间实含半宽片假名/谚文）、端点位移可产出未分配码点、以及两个额外的转写点。
  区间外原样保留同时保护代理对（emoji 不会被拆散）。

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
