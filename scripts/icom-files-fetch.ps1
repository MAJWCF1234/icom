# icom-files-fetch — list and open received files
param(
    [string]$From,
    [switch]$OpenFolder
)

. "$PSScriptRoot\icom-mail-common.ps1"

$received = Join-Path $script:FilesRoot "received"
$inbox = Join-Path $script:FilesRoot "inbox"

Write-Host "=== Received files ==="
if (Test-Path $received) {
    Get-ChildItem $received -Recurse -File -EA SilentlyContinue | ForEach-Object {
        $rel = $_.FullName.Substring($received.Length).TrimStart('\')
        if ($From -and $rel -notlike "$From*") { return }
        Write-Host "  $rel  ($([Math]::Round($_.Length/1KB, 1)) KB)"
    }
}

Write-Host "`n=== Inbox manifests ==="
Get-ChildItem $inbox -Filter "*.json" -EA SilentlyContinue | ForEach-Object {
    $m = Read-FileManifest $_.FullName
    if ($From -and $m.from -ne $From) { return }
    Write-Host "  $($m.id) from $($m.from): $($m.filename) ($($m.size) bytes)"
    if ($m.local_path) { Write-Host "    -> $($m.local_path)" }
}

if ($OpenFolder -and (Test-Path $received)) {
    explorer.exe $received
}
