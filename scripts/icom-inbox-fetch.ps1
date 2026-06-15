# icom-inbox-fetch.ps1 — pull repo and show messages TO this node
param(
    [Parameter(Mandatory = $true)][string]$Node,
    [string]$RepoDir = (Join-Path $env:USERPROFILE "icom")
)

$inFile = if ($Node -eq "majwcf-1") { "inbox/majwcf-2-to-majwcf-1.md" } else { "inbox/majwcf-1-to-majwcf-2.md" }

if (-not (Test-Path $RepoDir)) {
    git clone https://github.com/MAJWCF1234/icom.git $RepoDir
}

Push-Location $RepoDir
git pull --rebase 2>&1
Pop-Location

$path = Join-Path $RepoDir $inFile
if (Test-Path $path) {
    Write-Host "=== INBOX for $Node ($inFile) ==="
    Get-Content $path
} else {
    Write-Host "No messages yet in $inFile"
}
