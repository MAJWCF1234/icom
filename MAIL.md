# icom-mail — local P2P mail (NOT on GitHub)

Private email-like messaging between icom nodes. Mail is stored **only on each machine** under `%USERPROFILE%\.icom\mail\`.

## Local storage (never committed to git)

```
%USERPROFILE%\.icom\mail\
  inbox/     <- received mail
  outbox/    <- waiting to send
  sent/      <- delivered copies
  failed/    <- delivery failures
```

## Port

**7756** TCP over Tailscale (separate from realtime icom on 7755)

## Protocol

```
Client -> Server:  SYNC|v1|<node>|<ip>|<timestamp>
Server -> Client:  READY|v1|<node>|<ip>|<timestamp>
Client -> Server:  MAIL|v1|<id>|<from>|<to>|<subject>|<base64-body>
Server -> Client:  ACK|v1|<id>
... repeat ...
Either side:       DONE|v1|...
```

Bidirectional: both sides push outbox and ACK incoming mail in one session.

## Usage

```powershell
# Terminal 1 — mail server (leave running)
powershell -NoProfile -File scripts\icom-mail-server.ps1 -Node majwcf-1

# Send mail (queues locally, delivers on sync)
powershell -NoProfile -File scripts\icom-mail-send.ps1 `
  -From majwcf-1 -To majwcf-2 `
  -Subject "Hello" -Body "Message body here"

# Sync with peer (run anytime — works even if they were offline when you sent)
powershell -NoProfile -File scripts\icom-mail-sync.ps1 -Node majwcf-1

# Read inbox
powershell -NoProfile -File scripts\icom-mail-fetch.ps1
powershell -NoProfile -File scripts\icom-mail-fetch.ps1 -From majwcf-2 -MarkRead
```

## Offline behavior

1. Compose with `icom-mail-send.ps1` — sits in **outbox**
2. When peer comes online, run `icom-mail-sync.ps1` (or their server receives your sync)
3. Mail moves to **sent** on sender, **inbox** on receiver
4. Either side can sync — whoever is up first delivers pending mail

## Security

- Mail never touches GitHub
- Stays on local disk + Tailscale encrypted tunnel only
- Do not put message content in git commits
