# icom-mail-server — listen for mail sync on port 7756
param([Parameter(Mandatory = $true)][string]$Node)

. "$PSScriptRoot\icom-mail-common.ps1"

$MyIP = (tailscale ip -4).Trim()
Write-MailLog "MAIL SERVER | $Node @ $MyIP`:$script:MailPort"

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $script:MailPort)
$listener.Start()

while ($true) {
    try {
        if (-not $listener.Pending()) { Start-Sleep 100; continue }

        $client = $listener.AcceptTcpClient()
        $remote = $client.Client.RemoteEndPoint.ToString()
        $stream = $client.GetStream()
        $stream.ReadTimeout = 60000
        $stream.WriteTimeout = 60000
        $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $false, 65536, $true)
        $writer = New-Object IO.StreamWriter($stream, [Text.Encoding]::UTF8, 65536, $true)
        $writer.AutoFlush = $true

        $line = $reader.ReadLine()
        Write-MailLog "IN  $remote | $line"

        if ($line -notmatch '^SYNC\|v1\|([^|]+)\|') {
            $writer.WriteLine("ERROR|v1|send SYNC|v1|<node>|<ip>|<ts>")
            $client.Close(); continue
        }
        $peerNode = $Matches[1]

        $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $writer.WriteLine("READY|v1|$Node|$MyIP|$ts")
        Write-MailLog "OUT READY to $peerNode"

        # Receive mail from peer
        while ($true) {
            $line = $reader.ReadLine()
            if (-not $line) { break }
            Write-MailLog "IN  $remote | $($line.Substring(0, [Math]::Min(80, $line.Length)))"
            if ($line -match '^DONE\|') { break }
            if ($line -match '^MAIL\|') {
                $parsed = Parse-MailLine $line
                if ($parsed -and $parsed.to -eq $Node) {
                    $parsed.status = "delivered"
                    $parsed.received = (Get-Date -Format o)
                    Save-MailFile "inbox" $parsed
                    $writer.WriteLine("ACK|v1|$($parsed.id)")
                    Write-MailLog "OUT ACK $($parsed.id) -> inbox"
                }
            }
        }

        # Push our outbox mail addressed to peer
        $outbox = Join-Path $script:MailRoot "outbox"
        foreach ($f in Get-ChildItem $outbox -Filter "*.json" -ErrorAction SilentlyContinue) {
            $m = Read-MailFile $f.FullName
            if ($m.to -ne $peerNode) { continue }
            $writer.WriteLine((Format-MailLine $m))
            Write-MailLog "OUT MAIL $($m.id) to $peerNode"
            $ack = $reader.ReadLine()
            Write-MailLog "IN  $ack"
            if ($ack -match "^ACK\|v1\|$($m.id)") {
                $m.status = "sent"
                $m.sent = (Get-Date -Format o)
                Save-MailFile "sent" $m
                Remove-Item $f.FullName -Force
            }
        }

        $writer.WriteLine("DONE|v1|mail-sync-complete")
        Write-MailLog "SESSION DONE $remote"
        $client.Close()
    } catch {
        Write-MailLog "ERR $_"
        Start-Sleep 1
    }
}
