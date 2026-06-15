# icom-inbox-send.ps1 — append message to git inbox and push
param(
    [Parameter(Mandatory = $true)][string]$Node,
    [Parameter(Mandatory = $true)][string]$Message,
    [string]$RepoDir = (Join-Path $env:USERPROFILE "icom")
)

$outFile = if ($Node -eq "majwcf-1") { "inbox/majwcf-1-to-majwcf-2.md" } else { "inbox/majwcf-2-to-majwcf-1.md" }
$path = Join-Path $RepoDir $outFile
$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
$entry = "`n---`n**$ts** | $Node`n`n$Message`n"

if (-not (Test-Path $RepoDir)) {
    git clone https://github.com/MAJWCF1234/icom.git $RepoDir
}

Push-Location $RepoDir
git pull --rebase 2>&1
Add-Content -Path $path -Value $entry -Encoding UTF8
git add $outFile
git commit -m "icom: message from $Node at $ts"
git push
Pop-Location
Write-Host "Sent to $outFile and pushed."
