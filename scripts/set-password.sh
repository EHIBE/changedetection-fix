#!/usr/bin/env bash
# Asks for a password and stores its hash in .env as SALTED_PASS.
# The hash format matches changedetection.io's own check_password():
# base64(32 byte salt + PBKDF2-SHA256(password, salt, 100000 rounds))
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || cp .env.example .env

read -rsp "New password: " pw; echo
read -rsp "Repeat it:    " pw2; echo
[ "$pw" = "$pw2" ] || { echo "Passwords don't match." >&2; exit 1; }
[ ${#pw} -ge 12 ] || { echo "Use at least 12 characters." >&2; exit 1; }

version="$(grep -E '^CHANGEDETECTION_VERSION=' .env | cut -d= -f2 || true)"
image="ghcr.io/dgtlmoon/changedetection.io:${version:-0.55.8}"
hash="$(PW="$pw" docker run --rm -e PW "$image" python -c '
import base64, hashlib, os, secrets
salt = secrets.token_bytes(32)
key = hashlib.pbkdf2_hmac("sha256", os.environ["PW"].encode(), salt, 100000)
print(base64.b64encode(salt + key).decode())')"

if grep -q '^SALTED_PASS=' .env; then
  sed -i.bak "s|^SALTED_PASS=.*|SALTED_PASS=${hash}|" .env && rm -f .env.bak
else
  echo "SALTED_PASS=${hash}" >> .env
fi

echo "Saved. Run 'docker compose up -d' (again) to apply it."
