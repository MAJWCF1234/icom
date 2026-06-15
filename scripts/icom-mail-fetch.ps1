# icom-mail-fetch — read mail + extract inline base64 attachments
param(
    [string]$From,
    [switch]$UnreadOnly,
    [switch]$MarkRead,
    [switch]$ExtractAttachments
)

. "$PSScriptRoot\icom-mail-common.ps1"

$inbox = Join-Path $script:MailRoot "inbox"
$attachDir = Join-Path $script:FilesRoot "received\mail-attachments"
New-Item -ItemType Directory -Force -Path $attachDir | Out-Null

$files = Get-ChildItem $inbox -Filter "*.json" -EA SilentlyContinue | Sort-Object LastWriteTime
if (-not $files) { Write-Host "Inbox empty."; return }

foreach ($f in $files) {
    $m = Read-MailFile $f.FullName
    if ($From -and $m.from -ne $From) { continue }
    if ($UnreadOnly -and $m.read) { continue }

    Write-Host "`n=== $($m.id) ==="
    Write-Host "From: $($m.from)  Subject: $($m.subject)  Date: $($m.timestamp)"
    Write-Host (Decode-MailBody $m.body_b64)

    if ($m.attachments) {
        foreach ($a in $m.attachments) {
            $out = Join-Path $attachDir "$($m.id)-$($a.filename)"
            [IO.File]::WriteAllBytes($out, [Convert]::FromBase64String($a.data_b64))
            Write-Host "  [attachment] $($a.filename) ($($a.size) bytes) -> $out"
        }
    }

    if ($MarkRead) {
        $m | Add-Member -NotePropertyName read -NotePropertyValue $true -Force
        ($m | ConvertTo-Json -Depth 8) | Set-Content $f.FullName -Encoding UTF8
    }
}
