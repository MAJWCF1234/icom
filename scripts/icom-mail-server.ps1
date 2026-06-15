# icom-mail-server — mail + file sync on port 7756
param([Parameter(Mandatory = $true)][string]$Node)

. "$PSScriptRoot\icom-mail-common.ps1"

$MyIP = (tailscale ip -4).Trim()
Write-IcomLog "ICOM SERVER | $Node @ $MyIP`:$script:MailPort (mail + files)"

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $script:MailPort)
$listener.Start()

while ($true) {
    try {
        if (-not $listener.Pending()) { Start-Sleep 100; continue }

        $client = $listener.AcceptTcpClient()
        $remote = $client.Client.RemoteEndPoint.ToString()
        $stream = $client.GetStream()
        $stream.ReadTimeout = 120000
        $stream.WriteTimeout = 120000
        $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $false, 131072, $true)
        $writer = New-Object IO.StreamWriter($stream, [Text.Encoding]::UTF8, 131072, $true)
        $writer.AutoFlush = $true

        $line = $reader.ReadLine()
        Write-IcomLog "IN  $remote | $line"

        if ($line -notmatch '^SYNC\|v1\|([^|]+)\|') {
            $writer.WriteLine("ERROR|v1|send SYNC|v1|<node>|<ip>|<ts>")
            $client.Close(); continue
        }
        $peerNode = $Matches[1]
        $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $writer.WriteLine("READY|v1|$Node|$MyIP|$ts")

        $fileRecv = @{}
        $mailPending = @{}

        # Receive from peer until DONE
        while ($true) {
            $line = $reader.ReadLine()
            if (-not $line) { break }
            $preview = if ($line.Length -gt 80) { $line.Substring(0, 80) + "..." } else { $line }
            Write-IcomLog "IN  $preview"
            if ($line -match '^DONE\|') { break }
            Receive-IcomLine -Line $line -Node $Node -Writer $writer -Remote $remote -FileRecv $fileRecv -MailPending $mailPending
        }
        Finalize-ReceivedFiles $fileRecv $Node $writer

        # Push mail outbox
        foreach ($f in Get-ChildItem (Join-Path $script:MailRoot "outbox") -Filter "*.json" -EA SilentlyContinue) {
            $m = Read-MailFile $f.FullName
            if ($m.to -ne $peerNode) { continue }
            if (Send-MailTransfer $m $writer $reader) {
                $m.status = "sent"; $m.sent = (Get-Date -Format o)
                Save-MailFile "sent" $m; Remove-Item $f.FullName -Force
            }
        }

        # Push file outbox
        $fileOut = Join-Path $script:FilesRoot "outbox"
        foreach ($f in Get-ChildItem $fileOut -Filter "*.json" -EA SilentlyContinue) {
            $manifest = Read-FileManifest $f.FullName
            if ($manifest.to -ne $peerNode) { continue }
            if (Send-FileTransfer $manifest $writer $reader $fileOut) {
                $manifest.status = "sent"; $manifest.sent = (Get-Date -Format o)
                Save-FileManifest "sent" $manifest
                Remove-Item $f.FullName -Force
                Remove-Item (Join-Path $fileOut "$($manifest.id).chunks") -Recurse -Force -EA SilentlyContinue
            }
        }

        $writer.WriteLine("DONE|v1|sync-complete")
        $client.Close()
    } catch {
        Write-IcomLog "ERR $_"
        Start-Sleep 1
    }
}
