# icom-mail-sync — deliver outbox + pickup inbox from peer
param(
    [Parameter(Mandatory = $true)][string]$Node,
    [string]$PeerIP,
    [string]$PeerNode
)

. "$PSScriptRoot\icom-mail-common.ps1"

if (-not $PeerIP) {
    $info = Get-NodeInfo -Node $(if ($Node -eq "majwcf-1") { "majwcf-2" } else { "majwcf-1" })
    $PeerIP = $info.tailscale_ip
    $PeerNode = if ($Node -eq "majwcf-1") { "majwcf-2" } else { "majwcf-1" }
}

$MyIP = (tailscale ip -4).Trim()
Write-MailLog "SYNC $Node -> $PeerNode ($PeerIP)"

$tcp = New-Object Net.Sockets.TcpClient
$tcp.ReceiveTimeout = 60000
$tcp.Connect($PeerIP, $script:MailPort)
$stream = $tcp.GetStream()
$reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $false, 65536, $true)
$writer = New-Object IO.StreamWriter($stream, [Text.Encoding]::UTF8, 65536, $true)
$writer.AutoFlush = $true

$ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$writer.WriteLine("SYNC|v1|$Node|$MyIP|$ts")
$ready = $reader.ReadLine()
Write-MailLog "IN  $ready"
if ($ready -notmatch '^READY\|') { throw "Bad sync: $ready" }

# Push our outbox
$outbox = Join-Path $script:MailRoot "outbox"
$count = 0
foreach ($f in Get-ChildItem $outbox -Filter "*.json" -ErrorAction SilentlyContinue) {
    $m = Read-MailFile $f.FullName
    if ($m.to -ne $PeerNode) { continue }
    $writer.WriteLine((Format-MailLine $m))
    Write-MailLog "OUT MAIL $($m.id)"
    $ack = $reader.ReadLine()
    Write-MailLog "IN  $ack"
    if ($ack -match "^ACK\|v1\|$($m.id)") {
        $m.status = "sent"
        $m.sent = (Get-Date -Format o)
        Save-MailFile "sent" $m
        Remove-Item $f.FullName -Force
        $count++
    }
}
$writer.WriteLine("DONE|v1|push-complete")
Write-MailLog "Pushed $count message(s)"

# Receive peer mail
while ($true) {
    $line = $reader.ReadLine()
    if (-not $line) { break }
    Write-MailLog "IN  $($line.Substring(0, [Math]::Min(80, $line.Length)))"
    if ($line -match '^DONE\|') { break }
    if ($line -match '^MAIL\|') {
        $parsed = Parse-MailLine $line
        if ($parsed -and $parsed.to -eq $Node) {
            $parsed.status = "delivered"
            $parsed.received = (Get-Date -Format o)
            Save-MailFile "inbox" $parsed
            $writer.WriteLine("ACK|v1|$($parsed.id)")
            Write-MailLog "OUT ACK $($parsed.id)"
        }
    }
}

$tcp.Close()
Write-MailLog "SYNC COMPLETE"
Write-Host "Sync complete. Run icom-mail-fetch.ps1 to read inbox."
