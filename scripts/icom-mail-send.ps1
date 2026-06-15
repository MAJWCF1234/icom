# icom-mail-send — compose mail to outbox (delivered when peer is online)
param(
    [Parameter(Mandatory = $true)][string]$From,
    [Parameter(Mandatory = $true)][string]$To,
    [Parameter(Mandatory = $true)][string]$Subject,
    [Parameter(Mandatory = $true)][string]$Body
)

. "$PSScriptRoot\icom-mail-common.ps1"

$mail = @{
    id        = New-MailId
    from      = $From
    to        = $To
    subject   = $Subject
    body_b64  = Encode-MailBody $Body
    timestamp = (Get-Date -Format o)
    status    = "pending"
}

$path = Save-MailFile "outbox" $mail
Write-MailLog "QUEUED $($mail.id) $From -> $To : $Subject"
Write-Host "Mail queued: $path"
Write-Host "Run icom-mail-sync.ps1 to deliver when peer is online."
