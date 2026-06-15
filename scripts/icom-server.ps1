# icom-server v2
param([string]$Node = "majwcf-1", [int]$Port = 7755)

$nodes = Get-Content (Join-Path $PSScriptRoot "..\nodes.json") | ConvertFrom-Json
$MyIP = (tailscale ip -4).Trim()
$MyHost = $Node
$BaseDir = Join-Path $env:USERPROFILE ".icom"
$Log = Join-Path $BaseDir "icom-server.log"
New-Item -ItemType Directory -Force -Path $BaseDir | Out-Null

function Log($m) {
    $l = "$(Get-Date -Format 'HH:mm:ss') $m"
    Add-Content $Log $l
    Write-Host $l
}

$DataPayload = @(
    "I am $Node at $MyIP. icom v2 online. Repo: https://github.com/MAJWCF1234/icom"
    "Real-time: TCP port $Port. Async: git inbox in this repo."
    "Read inbox/$(if($Node -eq 'majwcf-1'){'majwcf-2-to-majwcf-1.md'}else{'majwcf-1-to-majwcf-2.md'}) after git pull."
    "Write to inbox/$(if($Node -eq 'majwcf-1'){'majwcf-1-to-majwcf-2.md'}else{'majwcf-2-to-majwcf-1.md'}) then push."
    "Protocol spec: PROTOCOL.md in repo. Use icom-client.ps1 -PeerIP <peer> to connect."
)

function Is-Seek([string]$line) { return $line -and $line -match '(?i)^seek' }

Log "SERVER LIVE | $MyHost @ $MyIP`:$Port"
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
$listener.Start()

while ($true) {
    try {
        if (-not $listener.Pending()) { Start-Sleep -Milliseconds 100; continue }
        $client = $listener.AcceptTcpClient()
        $remote = $client.Client.RemoteEndPoint.ToString()
        $stream = $client.GetStream()
        $stream.ReadTimeout = 15000
        $stream.WriteTimeout = 15000
        $reader = New-Object System.IO.StreamReader($stream, [Text.Encoding]::UTF8, $false, 8192, $true)
        $writer = New-Object System.IO.StreamWriter($stream, [Text.Encoding]::UTF8, 8192, $true)
        $writer.AutoFlush = $true
        $line = $reader.ReadLine()
        Log "IN  $remote | $line"
        if (-not (Is-Seek $line)) {
            $writer.WriteLine("ERROR|v1|send SEEK|v1|$Node|$MyIP|<unix-timestamp>")
            $client.Close(); continue
        }
        $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $found = "FOUND|v1|$MyHost|$MyIP|$ts|$Node-ready"
        $writer.WriteLine($found)
        Log "OUT $found"
        for ($n = 1; $n -le 5; $n++) {
            $data = "DATA|v1|$n/5|$MyHost|$($DataPayload[$n - 1])"
            $writer.WriteLine($data)
            Log "OUT $data"
            try { $r = $reader.ReadLine(); if ($r) { Log "IN  $remote | $r" } } catch { }
        }
        $writer.WriteLine("DONE|v1|5/5|$MyHost|session-complete")
        Log "SESSION COMPLETE $remote"
        $client.Close()
    } catch { Log "ERR $_"; Start-Sleep 1 }
}
