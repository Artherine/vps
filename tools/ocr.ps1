<#
  ocr.ps1 — 用 Windows 内建 OCR 读出图片里的文字（零安装）

  ⚠ 必须用 Windows PowerShell 5.1 运行，不能用 pwsh：
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\ocr.ps1 -Paths a.jpg,b.jpg
    PowerShell 7 没有 WinRT 投影，Add-Type System.Runtime.WindowsRuntime 之后
    连 GetMethods() 都会报 "Operation is not supported on this platform"。

  ⚠ 沙箱是低完整性令牌，StorageFile.GetFileFromPathAsync 会被挡
    （Await 抛 "One or more errors occurred"）。所以这里走 .NET 文件流 + AsRandomAccessStream。

  用法：
    powershell.exe -File tools\ocr.ps1 -Paths chat_img1.jpg,chat_img2.jpg
    powershell.exe -File tools\ocr.ps1 -Paths *.png -OutFile out.txt   # 建议带 -OutFile，
                                                                       # 控制台编码常把中文搞乱
#>
param(
  [Parameter(Mandatory = $true)][string[]]$Paths,
  [string]$OutFile
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq "IAsyncOperation``1" })[0]
function Await($t, $rt) {
  $m = $asTaskGeneric.MakeGenericMethod($rt); $nt = $m.Invoke($null, @($t)); $nt.Wait(-1) | Out-Null; $nt.Result
}
[void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
[void][Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]

$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if (-not $engine) {
  $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language "zh-Hans-CN"))
}
if (-not $engine) { throw "没有可用的 OCR 引擎" }

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("OCR 引擎: " + $engine.RecognizerLanguage.LanguageTag)
foreach ($p in $Paths) {
  $full = (Resolve-Path -LiteralPath $p).Path
  $fs = [System.IO.File]::OpenRead($full)
  try {
    $ras = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($fs)
    $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($ras)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $bmp = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $res = Await ($engine.RecognizeAsync($bmp)) ([Windows.Media.Ocr.OcrResult])
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("===== " + [System.IO.Path]::GetFileName($full) + "  " + $decoder.PixelWidth + "x" + $decoder.PixelHeight + " =====")
    if ([string]::IsNullOrWhiteSpace($res.Text)) { [void]$sb.AppendLine("(未识别到文字)") } else { [void]$sb.AppendLine($res.Text) }
    $ras.Dispose()
  } finally { $fs.Dispose() }
}
$text = $sb.ToString()
if ($OutFile) {
  [System.IO.File]::WriteAllText($OutFile, $text, (New-Object System.Text.UTF8Encoding($false)))
  Write-Output ("写好了: " + $OutFile)
} else {
  Write-Output $text
}
