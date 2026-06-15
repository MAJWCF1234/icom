# icom-files-send — queue images, documents, any file (base64 chunked)
param(
    [Parameter(Mandatory = $true)][string]$From,
    [Parameter(Mandatory = $true)][string]$To,
    [Parameter(Mandatory = $true)][string]$Path
)

. "$PSScriptRoot\icom-mail-common.ps1"

if (Test-Path $Path -PathType Container) {
    $zip = Join-Path $env:TEMP "icom-send-$(New-IcomId).zip"
    Compress-Archive -Path (Join-Path $Path "*") -DestinationPath $zip -Force
    $manifest = Queue-FileTransfer -From $From -To $To -FilePath $zip
    Remove-Item $zip -Force
    Write-Host "Folder zipped and queued as $($manifest.filename)"
} else {
    $manifest = Queue-FileTransfer -From $From -To $To -FilePath $Path
    Write-Host "File queued: $($manifest.filename) ($($manifest.size) bytes)"
}
Write-Host "Run icom-mail-sync.ps1 to deliver."
