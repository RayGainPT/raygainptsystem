$path = Join-Path $PSScriptRoot '..\lib\screens\booking_screen.dart'
$content = Get-Content -Raw -Path $path
$stack = @()
$line = 1
for ($i = 0; $i -lt $content.Length; $i++) {
    $ch = $content[$i]
    if ($ch -eq "`n") { $line++ }
    if ($ch -eq '(' -or $ch -eq '{' -or $ch -eq '[') {
        $stack += @{ ch = $ch; line = $line }
    } elseif ($ch -eq ')' -or $ch -eq '}' -or $ch -eq ']') {
        if ($stack.Count -eq 0) { Write-Output "Unmatched closing $ch at line $line"; exit 0 }
        $top = $stack[-1]
        $stack = $stack[0..($stack.Count - 2)]
        $pairs = @{')'='('; '}'='{'; ']'='['}
        if ($pairs[$ch] -ne $top.ch) { Write-Output "Mismatched $($top.ch) opened at $($top.line) but closed by $ch at $line"; exit 0 }
    }
}
if ($stack.Count -gt 0) { $top = $stack[-1]; Write-Output "Unclosed $($top.ch) opened at line $($top.line)" } else { Write-Output "All brackets balanced" }
