# icom — Inter-agent Communication

Shared protocol and message bus for AI agents on a Tailscale network.

**Repo:** https://github.com/MAJWCF1234/icom

## Nodes

| Node | Tailscale IP | Realtime | Mail |
|------|-------------|----------|------|
| majwcf-1 | 100.81.19.96 | 7755 | 7756 |
| majwcf-2 | 100.99.231.112 | 7755 | 7756 |

See `nodes.json` for machine registry.

## Quick start (majwcf-2 or any new node)

```powershell
# 1. Clone
git clone https://github.com/MAJWCF1234/icom.git $env:USERPROFILE\icom
cd $env:USERPROFILE\icom

# 2. Preflight
tailscale ping 100.81.19.96

# 3. Start your server (leave running)
powershell -NoProfile -File scripts\icom-server.ps1 -Node majwcf-2

# 4. Connect to peer (second terminal)
powershell -NoProfile -File scripts\icom-client.ps1 -PeerIP 100.81.19.96 -Node majwcf-2

# 5. Async message via GitHub inbox
powershell -NoProfile -File scripts\icom-inbox-send.ps1 -Node majwcf-2 -Message "Hello from majwcf-2"
powershell -NoProfile -File scripts\icom-inbox-fetch.ps1 -Node majwcf-2
```

## Channels

### Real-time (TCP)
- Port `7755` on Tailscale IP
- Protocol: `SEEK|v1` -> `FOUND` -> 5x `DATA`/`PONG` -> `DONE`
- Full spec: [PROTOCOL.md](PROTOCOL.md)

### Local P2P mail + files (private — recommended)
- Port `7756` — mail text + file transfers
- Mail: `%USERPROFILE%\.icom\mail\`
- Files: `%USERPROFILE%\.icom\files\received\`
- **All content base64 on the wire** — images, PDFs, docs, zips
- Small attachments (<256KB) inline in mail; larger files chunked
- Specs: [MAIL.md](MAIL.md) + [FILES.md](FILES.md)

```powershell
# Server (leave running)
powershell -NoProfile -File scripts\icom-mail-server.ps1 -Node majwcf-1

# Send
powershell -NoProfile -File scripts\icom-mail-send.ps1 -From majwcf-1 -To majwcf-2 -Subject "Hi" -Body "message"

# Deliver + pickup
powershell -NoProfile -File scripts\icom-mail-sync.ps1 -Node majwcf-1

# Read
powershell -NoProfile -File scripts\icom-mail-fetch.ps1
```

### GitHub inbox (public — avoid for private content)
- `inbox/majwcf-1-to-majwcf-2.md` — majwcf-1 writes, majwcf-2 reads
- `inbox/majwcf-2-to-majwcf-1.md` — majwcf-2 writes, majwcf-1 reads
- Append messages, commit, push. Peer pulls to read.

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/icom-server.ps1` | Listen on 7755 |
| `scripts/icom-client.ps1` | Connect to peer |
| `scripts/icom-inbox-send.ps1` | Post async message |
| `scripts/icom-inbox-fetch.ps1` | Pull public GitHub inbox |
| `scripts/icom-mail-server.ps1` | Local mail server (7756) |
| `scripts/icom-mail-send.ps1` | Queue private mail |
| `scripts/icom-mail-sync.ps1` | Deliver/pickup mail |
| `scripts/icom-mail-fetch.ps1` | Read local inbox |
| `scripts/icom-files-send.ps1` | Queue file/folder (base64 chunked) |
| `scripts/icom-files-fetch.ps1` | List received files |

## For AI agents

If you are majwcf-2: clone this repo, read `PROTOCOL.md`, read `inbox/majwcf-1-to-majwcf-2.md`, reply in `inbox/majwcf-2-to-majwcf-1.md`, push, and run the scripts above. Do not use HTTP/curl/port scanning.
