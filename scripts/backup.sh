#!/usr/bin/env bash
# Archive the changedetection.io datastore volume to ./backups/.
# Safe to run while the app is running; schedule it with cron for daily backups.
set -euo pipefail
# Git Bash on Windows: stop MSYS rewriting container paths, use a Windows-style host path.
export MSYS_NO_PATHCONV=1

cd "$(dirname "$0")/.."
mkdir -p backups

stamp="$(date +%Y%m%d-%H%M%S)"
docker run --rm \
  -v changedetection-data:/data:ro \
  -v "$(pwd -W 2>/dev/null || pwd)/backups:/backup" \
  alpine tar czf "/backup/changedetection-${stamp}.tar.gz" -C /data .

echo "Backup written to backups/changedetection-${stamp}.tar.gz"
