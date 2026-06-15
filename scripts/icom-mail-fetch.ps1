# icom-mail-fetch — read local inbox (private, on this machine only)
param(
    [string]$From,
    [switch]$UnreadOnly,
    [switch]$MarkRead
)

. "$PSScriptRoot\icom-mail-common.ps1"

$inbox = Join-Path $script:MailRoot "inbox"
$files = Get-ChildItem $inbox -Filter "*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime

if (-not $files) {
    Write-Host "Inbox empty."
    return
}

foreach ($f in $files) {
    $m = Read-MailFile $f.FullName
    if ($From -and $m.from -ne $From) { continue }
    if ($UnreadOnly -and $m.read) { continue }

    Write-Host ""
    Write-Host "=== $($m.id) ==="
    Write-Host "From:    $($m.from)"
    Write-Host "To:      $($m.to)"
    Write-Host "Subject: $($m.subject)"
    Write-Host "Date:    $($m.timestamp)"
    Write-Host "---"
    Write-Host (Decode-MailBody $m.body_b64)

    if ($MarkRead) {
        $m.read = $true
        ($m | ConvertTo-Json -Depth 4) | Set-Content $f.FullName -Encoding UTF8
    }
}
