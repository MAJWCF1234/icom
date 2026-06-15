# icom-mail-sync — deliver mail + files, pickup from peer
param(
    [Parameter(Mandatory = $true)][string]$Node,
    [string]$PeerIP,
    [string]$PeerNode
)

. "$PSScriptRoot\icom-mail-common.ps1"

if (-not $PeerIP) {
    $peer = if ($Node -eq "majwcf-1") { "majwcf-2" } else { "majwcf-1" }
    $info = Get-NodeInfo -Node $peer
    $PeerIP = $info.tailscale_ip
    $PeerNode = $peer
}

$MyIP = (tailscale ip -4).Trim()
Write-IcomLog "SYNC $Node -> $PeerNode ($PeerIP)"

$tcp = New-Object Net.Sockets.TcpClient
$tcp.ReceiveTimeout = 120000
$tcp.Connect($PeerIP, $script:MailPort)
$stream = $tcp.GetStream()
$reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $false, 131072, $true)
$writer = New-Object IO.StreamWriter($stream, [Text.Encoding]::UTF8, 131072, $true)
$writer.AutoFlush = $true

$ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$writer.WriteLine("SYNC|v1|$Node|$MyIP|$ts")
$ready = $reader.ReadLine()
if ($ready -notmatch '^READY\|') { throw "Bad sync: $ready" }

$fileRecv = @{}
$mailPending = @{}

# Push mail
$mailCount = 0
foreach ($f in Get-ChildItem (Join-Path $script:MailRoot "outbox") -Filter "*.json" -EA SilentlyContinue) {
    $m = Read-MailFile $f.FullName
    if ($m.to -ne $PeerNode) { continue }
    if (Send-MailTransfer $m $writer $reader) {
        $m.status = "sent"; Save-MailFile "sent" $m; Remove-Item $f.FullName -Force
        $mailCount++
    }
}

# Push files
$fileCount = 0
$fileOut = Join-Path $script:FilesRoot "outbox"
foreach ($f in Get-ChildItem $fileOut -Filter "*.json" -EA SilentlyContinue) {
    $manifest = Read-FileManifest $f.FullName
    if ($manifest.to -ne $PeerNode) { continue }
    if (Send-FileTransfer $manifest $writer $reader $fileOut) {
        $manifest.status = "sent"; Save-FileManifest "sent" $manifest
        Remove-Item $f.FullName -Force
        Remove-Item (Join-Path $fileOut "$($manifest.id).chunks") -Recurse -Force -EA SilentlyContinue
        $fileCount++
    }
}

$writer.WriteLine("DONE|v1|push-complete")

# Receive from peer
while ($true) {
    $line = $reader.ReadLine()
    if (-not $line) { break }
    if ($line -match '^DONE\|') { break }
    Receive-IcomLine -Line $line -Node $Node -Writer $writer -FileRecv $fileRecv -MailPending $mailPending
}
Finalize-ReceivedFiles $fileRecv $Node $writer

$tcp.Close()
Write-IcomLog "SYNC DONE - mail:$mailCount files:$fileCount"
Write-Host "Sync complete. icom-mail-fetch.ps1 / icom-files-fetch.ps1 to read."
