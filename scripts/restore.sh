#!/usr/bin/env bash
# Restore a backup made by backup.sh:  ./scripts/restore.sh backups/changedetection-YYYYMMDD-HHMMSS.tar.gz
# Stops the app, replaces the datastore contents, then starts it again.
set -euo pipefail
# Git Bash on Windows: stop MSYS rewriting container paths, use a Windows-style host path.
export MSYS_NO_PATHCONV=1

archive="${1:?Usage: $0 <backup.tar.gz>}"
[ -f "$archive" ] || { echo "File not found: $archive" >&2; exit 1; }

dir="$(cd "$(dirname "$archive")" && (pwd -W 2>/dev/null || pwd))"
file="$(basename "$archive")"
cd "$(dirname "$0")/.."

docker compose stop changedetection
docker run --rm \
  -v changedetection-data:/data \
  -v "${dir}:/backup:ro" \
  alpine sh -c "rm -rf /data/* /data/..?* /data/.[!.]* 2>/dev/null; tar xzf /backup/${file} -C /data"
docker compose start changedetection

echo "Restored ${file}"
