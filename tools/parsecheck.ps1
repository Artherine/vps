param([string]$Path)
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errs)
if ($errs -and $errs.Count -gt 0) { $errs | ForEach-Object { '  ERR L' + $_.Extent.StartLineNumber + ': ' + $_.Message }; exit 1 }
'PARSE OK (PS 5.1)'
