# icom Files — images, documents, any binary (base64)

All file content is **base64 encoded** on the wire and in local staging. Nothing goes to GitHub.

## Local folders

```
%USERPROFILE%\.icom\
  mail\          <- text mail + small inline attachments (< 256KB)
  files\
    outbox\      <- queued file transfers + .chunks/
    inbox\       <- delivery manifests
    sent\        <- sent copies
    received\    <- extracted files land here
      majwcf-2\  <- organized by sender
      mail-attachments\
```

## Two ways to send files

### Small files in email (< 256 KB)
Attach to mail — embedded as base64 in the mail JSON.

```powershell
powershell -NoProfile -File scripts\icom-mail-send.ps1 `
  -From majwcf-1 -To majwcf-2 `
  -Subject "Photos" -Body "See attached" `
  -AttachPath @("C:\path\photo.png", "C:\path\notes.txt")
```

### Any file size (chunked base64)
Images, PDFs, videos, zips — chunked at 48KB per line.

```powershell
# Single file
powershell -NoProfile -File scripts\icom-files-send.ps1 `
  -From majwcf-1 -To majwcf-2 -Path "C:\path\document.pdf"

# Entire folder (auto-zipped)
powershell -NoProfile -File scripts\icom-files-send.ps1 `
  -From majwcf-1 -To majwcf-2 -Path "C:\path\myfolder"
```

## Sync and fetch

```powershell
# Deliver everything (mail + files) — works when peer is offline first
powershell -NoProfile -File scripts\icom-mail-sync.ps1 -Node majwcf-1

# Read mail + extract inline attachments
powershell -NoProfile -File scripts\icom-mail-fetch.ps1 -ExtractAttachments

# List received files
powershell -NoProfile -File scripts\icom-files-fetch.ps1
powershell -NoProfile -File scripts\icom-files-fetch.ps1 -OpenFolder
```

## Wire protocol (port 7756)

```
FILEMETA|v1|<id>|<from>|<to>|<filename>|<mime>|<size>|<chunk-count>
FILECHUNK|v1|<id>|<index>/<total>|<base64-bytes>
ACK|v1|<id>          <- sent immediately after last chunk (not after DONE)
```

Inline mail attachments (< 256 KB):

```
MAIL|v1|<id>|<from>|<to>|<subject>|<base64-body>|<attach-count>
ATTACH|v1|<mail-id>|<index>|<filename>|<mime>|<size>|<base64-data>
ACK|v1|<mail-id>
```

## Supported types

PNG, JPG, GIF, WEBP, PDF, TXT, MD, JSON, ZIP, DOCX, XLSX, MP4, MP3, and anything else as `application/octet-stream`.

## Security

- Files stay on local disk + Tailscale tunnel only
- Never commit `%USERPROFILE%\.icom\` to git
