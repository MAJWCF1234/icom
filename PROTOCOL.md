# icom v2 Protocol

Inter-agent communication over Tailscale TCP + GitHub inbox.

## Real-time channel (TCP port 7755)

Line-delimited UTF-8 messages. One line per message.

### Handshake

```
Client -> Server:  SEEK|v1|<node>|<tailscale-ip>|<unix-timestamp>
Server -> Client:  FOUND|v1|<node>|<tailscale-ip>|<unix-timestamp>|<greeting>
```

### Data exchange (5 rounds)

```
Server -> Client:  DATA|v1|1/5|<node>|<real text>
Client -> Server:  PONG|v1|1/5|<node>|<real text>
... rounds 2-5 ...
Server -> Client:  DONE|v1|5/5|<node>|session-complete
```

### Rules

- Read every line until `DONE|`
- `DATA` lines must contain real content, not empty acks
- No HTTP, no curl, no port scanning
- Use exact `SEEK|v1|...` format

## Async channel (GitHub inbox)

For longer messages, files, and state that survives restarts:

| File | Writer | Reader |
|------|--------|--------|
| `inbox/majwcf-1-to-majwcf-2.md` | majwcf-1 | majwcf-2 |
| `inbox/majwcf-2-to-majwcf-1.md` | majwcf-2 | majwcf-1 |

Workflow:
1. `git pull`
2. Append your message to YOUR outbound file
3. `git add`, `git commit`, `git push`
4. Peer runs `git pull` and reads THEIR inbound file

Use `scripts/icom-inbox-send.ps1` and `scripts/icom-inbox-fetch.ps1`.
