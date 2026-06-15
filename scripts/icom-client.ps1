# icom-client v2
param(
    [Parameter(Mandatory = $true)][string]$PeerIP,
    [string]$Node = "majwcf-1",
    [int]$Port = 7755
)

$MyIP = (tailscale ip -4).Trim()
$MyHost = $Node
$BaseDir = Join-Path $env:USERPROFILE ".icom"
$Log = Join-Path $BaseDir "icom-client.log"
New-Item -ItemType Directory -Force -Path $BaseDir | Out-Null

function Log($m) {
    $l = "$(Get-Date -Format 'HH:mm:ss') $m"
    Add-Content $Log $l
    Write-Host $l
}

Log "CONNECTING to ${PeerIP}:${Port} from $MyHost ($MyIP)"
$tcp = New-Object System.Net.Sockets.TcpClient
$tcp.ReceiveTimeout = 30000
$tcp.Connect($PeerIP, $Port)
$stream = $tcp.GetStream()
$reader = New-Object System.IO.StreamReader($stream, [Text.Encoding]::UTF8, $false, 8192, $true)
$writer = New-Object System.IO.StreamWriter($stream, [Text.Encoding]::UTF8, 8192, $true)
$writer.AutoFlush = $true

$ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$seek = "SEEK|v1|$MyHost|$MyIP|$ts"
$writer.WriteLine($seek)
Log "OUT | $seek"

$lines = @()
while ($true) {
    $line = $reader.ReadLine()
    if (-not $line) { break }
    $lines += $line
    Log "IN  | $line"
    if ($line -match '^DONE\|') { break }
    if ($line -match '^DATA\|v1\|(\d+)/5\|') {
        $n = [int]$Matches[1]
        $pong = "PONG|v1|$n/5|$MyHost|ack-round-$n-from-$Node"
        $writer.WriteLine($pong)
        Log "OUT | $pong"
    }
}
$tcp.Close()
Log "DONE - $($lines.Count) lines from $PeerIP"
$lines
