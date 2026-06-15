# icom shared — mail + file transfer (all content base64 on the wire)
$script:IcomRoot = Join-Path $env:USERPROFILE ".icom"
$script:MailRoot = Join-Path $script:IcomRoot "mail"
$script:FilesRoot = Join-Path $script:IcomRoot "files"
$script:MailPort = 7756
$script:LogDir = Join-Path $script:IcomRoot "logs"
$script:ChunkBytes = 49152   # 48KB raw -> ~64KB base64 per line
$script:InlineMaxBytes = 262144  # 256KB — embed in mail JSON, else chunked file transfer

function Initialize-IcomStore {
    foreach ($d in @("inbox", "outbox", "sent", "failed")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $script:MailRoot $d) | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $script:FilesRoot $d) | Out-Null
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $script:FilesRoot "received") | Out-Null
    New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
}

function Get-NodeInfo {
    param([string]$Node)
    $nodesPath = Join-Path $PSScriptRoot "..\nodes.json"
    $nodes = Get-Content $nodesPath -Raw | ConvertFrom-Json
    return $nodes.nodes.$Node
}

function New-IcomId { return [guid]::NewGuid().ToString("n").Substring(0, 12) }

function Encode-B64([byte[]]$Bytes) { return [Convert]::ToBase64String($Bytes) }
function Encode-TextB64([string]$Text) { return Encode-B64 ([Text.Encoding]::UTF8.GetBytes($Text)) }
function Decode-TextB64([string]$B64) { return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($B64)) }

function Write-IcomLog([string]$Msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Msg"
    Add-Content -Path (Join-Path $script:LogDir "icom.log") -Value $line
    Write-Host $line
}
function Write-MailLog([string]$Msg) { Write-IcomLog $Msg }

function Get-MimeType([string]$Path) {
    $ext = [IO.Path]::GetExtension($Path).ToLower()
    $map = @{
        ".png" = "image/png"; ".jpg" = "image/jpeg"; ".jpeg" = "image/jpeg"
        ".gif" = "image/gif"; ".webp" = "image/webp"; ".pdf" = "application/pdf"
        ".txt" = "text/plain"; ".md" = "text/markdown"; ".json" = "application/json"
        ".zip" = "application/zip"; ".docx" = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        ".xlsx" = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        ".mp4" = "video/mp4"; ".mp3" = "audio/mpeg"
    }
    if ($map.ContainsKey($ext)) { return $map[$ext] }
    return "application/octet-stream"
}

function Save-Json([string]$Root, [string]$Dir, [object]$Obj) {
    $folder = Join-Path $Root $Dir
    $path = Join-Path $folder "$($Obj.id).json"
    ($Obj | ConvertTo-Json -Depth 8) | Set-Content $path -Encoding UTF8
    return $path
}

function Read-Json([string]$Path) { return Get-Content $Path -Raw | ConvertFrom-Json }

# --- Mail helpers ---
function Save-MailFile([string]$Dir, $Mail) { Save-Json $script:MailRoot $Dir $Mail }
function Read-MailFile([string]$Path) { Read-Json $Path }

function Format-MailLine($Mail) {
    $subj = ($Mail.subject -replace '\|', '/')
    $attachCount = if ($Mail.attachments) { $Mail.attachments.Count } else { 0 }
    if ($attachCount -gt 0) {
        return "MAIL|v1|$($Mail.id)|$($Mail.from)|$($Mail.to)|$subj|$($Mail.body_b64)|$attachCount"
    }
    return "MAIL|v1|$($Mail.id)|$($Mail.from)|$($Mail.to)|$subj|$($Mail.body_b64)"
}

function Parse-MailLine([string]$Line) {
    $p = $Line -split '\|', 8
    if ($p.Count -lt 7 -or $p[0] -ne 'MAIL') { return $null }
    $attachCount = if ($p.Count -ge 8 -and $p[7] -match '^\d+$') { [int]$p[7] } else { 0 }
    return [ordered]@{
        id = $p[2]; from = $p[3]; to = $p[4]; subject = $p[5]
        body_b64 = $p[6]; attachments = @(); expectedAttachments = $attachCount
        timestamp = (Get-Date -Format o)
    }
}

function Complete-MailDelivery($Mail, [string]$Node, $Writer) {
    if ($Mail.to -ne $Node) { return }
    $Mail.status = "delivered"
    $Mail.received = (Get-Date -Format o)
    if ($Mail.PSObject.Properties.Name -contains 'expectedAttachments') {
        $Mail.PSObject.Properties.Remove('expectedAttachments')
    }
    Save-MailFile "inbox" $Mail
    $Writer.WriteLine("ACK|v1|$($Mail.id)")
    Write-IcomLog "OUT ACK mail $($Mail.id)"
}

function Send-MailTransfer($Mail, $Writer, $Reader) {
    $line = Format-MailLine $Mail
    $Writer.WriteLine($line)
    Write-IcomLog "OUT $($line.Substring(0, [Math]::Min(80, $line.Length)))..."
    $attachCount = if ($Mail.attachments) { $Mail.attachments.Count } else { 0 }
    for ($i = 0; $i -lt $attachCount; $i++) {
        $a = $Mail.attachments[$i]
        $name = ($a.filename -replace '\|', '/')
        $aline = "ATTACH|v1|$($Mail.id)|$i|$name|$($a.mime)|$($a.size)|$($a.data_b64)"
        $Writer.WriteLine($aline)
        Write-IcomLog "OUT ATTACH|v1|$($Mail.id)|$i|$name ($($a.size) bytes)"
    }
    $ack = $Reader.ReadLine()
    Write-IcomLog "IN  $ack"
    return ($ack -match "^ACK\|v1\|$($Mail.id)")
}

# --- File helpers ---
function Save-FileManifest([string]$Dir, $Manifest) { Save-Json $script:FilesRoot $Dir $Manifest }
function Read-FileManifest([string]$Path) { Read-Json $Path }

function Queue-FileTransfer {
    param([string]$From, [string]$To, [string]$FilePath)
    if (-not (Test-Path $FilePath)) { throw "File not found: $FilePath" }
    $bytes = [IO.File]::ReadAllBytes($FilePath)
    $id = New-IcomId
    $name = [IO.Path]::GetFileName($FilePath)
    $manifest = [ordered]@{
        id = $id; type = "file"; from = $From; to = $To
        filename = $name; mime = (Get-MimeType $FilePath)
        size = $bytes.Length; timestamp = (Get-Date -Format o); status = "pending"
    }
    $chunkDir = Join-Path $script:FilesRoot "outbox\$id.chunks"
    New-Item -ItemType Directory -Force -Path $chunkDir | Out-Null
    $total = [Math]::Ceiling($bytes.Length / $script:ChunkBytes)
    $manifest.chunks = $total
    for ($i = 0; $i -lt $total; $i++) {
        $start = $i * $script:ChunkBytes
        $len = [Math]::Min($script:ChunkBytes, $bytes.Length - $start)
        $slice = New-Object byte[] $len
        [Array]::Copy($bytes, $start, $slice, 0, $len)
        $b64 = Encode-B64 $slice
        Set-Content (Join-Path $chunkDir "$i.b64") $b64 -NoNewline -Encoding ASCII
    }
    $path = Save-FileManifest "outbox" $manifest
    Write-IcomLog "FILE QUEUED $id $From -> $To : $name ($($bytes.Length) bytes, $total chunks)"
    return $manifest
}

function Build-InlineAttachment([string]$FilePath) {
    $bytes = [IO.File]::ReadAllBytes($FilePath)
    if ($bytes.Length -gt $script:InlineMaxBytes) {
        throw "File too large for mail attachment ($($bytes.Length) bytes). Use icom-files-send.ps1 (max inline $script:InlineMaxBytes)."
    }
    return [ordered]@{
        filename = [IO.Path]::GetFileName($FilePath)
        mime = (Get-MimeType $FilePath)
        size = $bytes.Length
        data_b64 = (Encode-B64 $bytes)
    }
}

function Save-ReceivedFile($Manifest, [string]$ChunkDir) {
    $destDir = Join-Path $script:FilesRoot "received\$($Manifest.from)"
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $dest = Join-Path $destDir $Manifest.filename
    $fs = [IO.File]::Create($dest)
    try {
        for ($i = 0; $i -lt $Manifest.chunks; $i++) {
            $b64 = Get-Content (Join-Path $ChunkDir "$i.b64") -Raw -Encoding ASCII
            $bytes = [Convert]::FromBase64String($b64)
            $fs.Write($bytes, 0, $bytes.Length)
        }
    } finally { $fs.Close() }
    $Manifest.status = "delivered"
    $Manifest.received = (Get-Date -Format o)
    $Manifest.local_path = $dest
    Save-FileManifest "inbox" $Manifest
    return $dest
}

function Send-FileTransfer($Manifest, $Writer, $Reader, [string]$OutboxDir) {
    $name = ($Manifest.filename -replace '\|', '/')
    $meta = "FILEMETA|v1|$($Manifest.id)|$($Manifest.from)|$($Manifest.to)|$name|$($Manifest.mime)|$($Manifest.size)|$($Manifest.chunks)"
    $Writer.WriteLine($meta)
    Write-IcomLog "OUT $meta"
    $chunkDir = Join-Path $OutboxDir "$($Manifest.id).chunks"
    for ($i = 0; $i -lt $Manifest.chunks; $i++) {
        $b64 = Get-Content (Join-Path $chunkDir "$i.b64") -Raw -Encoding ASCII
        $line = "FILECHUNK|v1|$($Manifest.id)|$i/$($Manifest.chunks)|$b64"
        $Writer.WriteLine($line)
    }
    $ack = $Reader.ReadLine()
    Write-IcomLog "IN  $ack"
    return ($ack -match "^ACK\|v1\|$($Manifest.id)")
}

function Receive-IcomLine {
    param([string]$Line, [string]$Node, $Writer, [string]$Remote,
           [hashtable]$FileRecv = $null, [hashtable]$MailPending = $null)

    if ($Line -match '^MAIL\|') {
        $parsed = Parse-MailLine $Line
        if (-not $parsed -or $parsed.to -ne $Node) { return }
        if ($parsed.expectedAttachments -eq 0) {
            Complete-MailDelivery $parsed $Node $Writer
        } else {
            $MailPending[$parsed.id] = $parsed
            Write-IcomLog "RECV MAIL $($parsed.id) awaiting $($parsed.expectedAttachments) attachment(s)"
        }
        return
    }

    if ($Line -match '^FILEMETA\|v1\|([^|]+)\|([^|]+)\|([^|]+)\|([^|]+)\|([^|]+)\|(\d+)\|(\d+)') {
        $id = $Matches[1]
        $FileRecv[$id] = [ordered]@{
            id = $id; from = $Matches[2]; to = $Matches[3]
            filename = $Matches[4]; mime = $Matches[5]
            size = [int]$Matches[6]; chunks = [int]$Matches[7]
            chunkDir = Join-Path $script:FilesRoot "inbox\_recv\$id"
        }
        New-Item -ItemType Directory -Force -Path $FileRecv[$id].chunkDir | Out-Null
        Write-IcomLog "RECV META $id $($FileRecv[$id].filename)"
        return
    }

    if ($Line -match '^FILECHUNK\|v1\|([^|]+)\|(\d+)/(\d+)\|(.+)$') {
        $id = $Matches[1]; $idx = [int]$Matches[2]; $total = [int]$Matches[3]
        if (-not $FileRecv.ContainsKey($id)) { return }
        Set-Content (Join-Path $FileRecv[$id].chunkDir "$idx.b64") $Matches[4] -NoNewline -Encoding ASCII
        if ($idx + 1 -eq $total) {
            $m = $FileRecv[$id]
            if ($m.to -eq $Node) {
                $dest = Save-ReceivedFile $m $m.chunkDir
                Remove-Item $m.chunkDir -Recurse -Force -ErrorAction SilentlyContinue
                $Writer.WriteLine("ACK|v1|$id")
                Write-IcomLog "OUT ACK file $id -> $dest"
            }
            $FileRecv.Remove($id)
        }
        return
    }

    if ($Line -match '^ATTACH\|v1\|([^|]+)\|(\d+)\|([^|]+)\|([^|]+)\|(\d+)\|(.+)$') {
        $mailId = $Matches[1]
        if (-not $MailPending.ContainsKey($mailId)) { return }
        $MailPending[$mailId].attachments += [ordered]@{
            filename = $Matches[3]; mime = $Matches[4]
            size = [int]$Matches[5]; data_b64 = $Matches[6]
        }
        Write-IcomLog "RECV ATTACH $mailId $($Matches[3])"
        if ($MailPending[$mailId].attachments.Count -eq $MailPending[$mailId].expectedAttachments) {
            $mail = $MailPending[$mailId]
            $MailPending.Remove($mailId)
            Complete-MailDelivery $mail $Node $Writer
        }
        return
    }
}

function Finalize-ReceivedFiles([hashtable]$FileRecv, [string]$Node, $Writer) {
    foreach ($id in @($FileRecv.Keys)) {
        $m = $FileRecv[$id]
        if ($m.to -ne $Node) { continue }
        $dest = Save-ReceivedFile $m $m.chunkDir
        Remove-Item $m.chunkDir -Recurse -Force -ErrorAction SilentlyContinue
        $Writer.WriteLine("ACK|v1|$id")
        Write-IcomLog "OUT ACK file $id (finalize) -> $dest"
        $FileRecv.Remove($id)
    }
}

Initialize-IcomStore
function New-MailId { New-IcomId }
function Encode-MailBody([string]$Text) { Encode-TextB64 $Text }
function Decode-MailBody([string]$B64) { Decode-TextB64 $B64 }
function Write-MailLog([string]$Msg) { Write-IcomLog $Msg }
