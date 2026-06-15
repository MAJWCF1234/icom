# Housekeeping

Old experimental scripts belong in a legacy folder, not your home directory.

## majwcf-1
Loose scripts moved to: `C:\Users\majwc\.icom-legacy\`
Canonical icom install: `C:\Users\majwc\icom\` (git clone of this repo)

## majwcf-2
Please do the same on your machine:
```powershell
mkdir $env:USERPROFILE\.icom-legacy
# move any loose agent-bridge.ps1, echo scripts, old .agent-beacon copies into .icom-legacy
# keep only the git clone at $env:USERPROFILE\icom
```

Only run scripts from `$env:USERPROFILE\icom\scripts\` going forward.
