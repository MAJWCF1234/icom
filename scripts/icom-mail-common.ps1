# icom-mail shared helpers — mail stays LOCAL, never on GitHub
$script:MailRoot = Join-Path $env:USERPROFILE ".icom\mail"
$script:MailPort = 7756
$script:LogDir = Join-Path $env:USERPROFILE ".icom\logs"

function Initialize-MailStore {
    foreach ($d in @("inbox", "outbox", "sent", "failed")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $script:MailRoot $d) | Out-Null
    }
    New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
}

function Get-NodeInfo {
    param([string]$Node)
    $nodesPath = Join-Path $PSScriptRoot "..\nodes.json"
    $nodes = Get-Content $nodesPath -Raw | ConvertFrom-Json
    return $nodes.nodes.$Node
}

function New-MailId {
    return [guid]::NewGuid().ToString("n").Substring(0, 12)
}

function Encode-MailBody([string]$Text) {
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
}

function Decode-MailBody([string]$B64) {
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($B64))
}

function Write-MailLog([string]$Msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Msg"
    Add-Content -Path (Join-Path $script:LogDir "icom-mail.log") -Value $line
    Write-Host $line
}

function Save-MailFile([string]$Dir, [hashtable]$Mail) {
    $folder = Join-Path $script:MailRoot $Dir
    $path = Join-Path $folder "$($Mail.id).json"
    ($Mail | ConvertTo-Json -Depth 4) | Set-Content $path -Encoding UTF8
    return $path
}

function Read-MailFile([string]$Path) {
    return Get-Content $Path -Raw | ConvertFrom-Json
}

function Format-MailLine([object]$Mail) {
    $subj = ($Mail.subject -replace '\|', '/')
    return "MAIL|v1|$($Mail.id)|$($Mail.from)|$($Mail.to)|$subj|$($Mail.body_b64)"
}

function Parse-MailLine([string]$Line) {
    $p = $Line -split '\|', 7
    if ($p.Count -lt 7 -or $p[0] -ne 'MAIL') { return $null }
    return @{
        id        = $p[2]
        from      = $p[3]
        to        = $p[4]
        subject   = $p[5]
        body_b64  = $p[6]
        timestamp = (Get-Date -Format o)
    }
}

Initialize-MailStore
