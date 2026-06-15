# icom-mail-send — text + optional attachments (base64, inline if < 256KB)
param(
    [Parameter(Mandatory = $true)][string]$From,
    [Parameter(Mandatory = $true)][string]$To,
    [Parameter(Mandatory = $true)][string]$Subject,
    [Parameter(Mandatory = $true)][string]$Body,
    [string[]]$AttachPath = @()
)

. "$PSScriptRoot\icom-mail-common.ps1"

$mail = [ordered]@{
    id = New-MailId; from = $From; to = $To; subject = $Subject
    body_b64 = Encode-MailBody $Body; timestamp = (Get-Date -Format o); status = "pending"
    attachments = @()
}

foreach ($ap in $AttachPath) {
    if (-not (Test-Path $ap)) { Write-Warning "Skip missing: $ap"; continue }
    $mail.attachments += (Build-InlineAttachment $ap)
}

$path = Save-MailFile "outbox" $mail
Write-IcomLog "QUEUED mail $($mail.id) + $($mail.attachments.Count) attachment(s)"
Write-Host "Mail queued: $path"
Write-Host "Large files: use icom-files-send.ps1 instead. Then icom-mail-sync.ps1"
