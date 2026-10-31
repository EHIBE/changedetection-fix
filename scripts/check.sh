#!/usr/bin/env bash
# End-to-end test of the two things that were wrong:
#   1. strangers could open and edit the dashboard
#   2. data has to survive the containers being recreated
#
# Usage: ./scripts/check.sh   (asks for the password you set)
set -euo pipefail
cd "$(dirname "$0")/.."

grep -qE '^SALTED_PASS=.+' .env 2>/dev/null || { echo "No password set yet. Run ./scripts/set-password.sh first." >&2; exit 1; }
port="$(grep -E '^PORT=' .env | cut -d= -f2 || true)"
url="http://127.0.0.1:${port:-5000}"
jar="$(mktemp)"; trap 'rm -f "$jar" "$jar.log"' EXIT
read -rsp "Password: " pw; echo

ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1" >&2; exit 1; }

page()   { curl -s -b "$jar" -c "$jar" "$url/"; }
status() { curl -s -o /dev/null -w '%{http_code}' -b "$jar" -c "$jar" "$@"; }
csrf() {
  local html; html="$(curl -s -b "$jar" -c "$jar" "$1")"
  [[ $html =~ name=\"csrf_token\"\ value=\"([^\"]*)\" ]] && echo "${BASH_REMATCH[1]}"
}

wait_up() {
  for _ in $(seq 60); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "$url/login")" = "200" ] && return
    sleep 2
  done
  fail "app did not start on $url"
}

login() {
  rm -f "$jar"
  local token; token="$(csrf "$url/login")"
  curl -s -o /dev/null -b "$jar" -c "$jar" --data-urlencode "csrf_token=$token" \
       --data-urlencode "password=$1" "$url/login"
}

up() { docker compose up -d >/dev/null 2>"$jar.log" || { cat "$jar.log" >&2; fail "docker compose up failed"; }; }

echo "Starting stack..."
up
wait_up

echo "Access:"
rm -f "$jar"
[ "$(status "$url/")" = "302" ]         && ok "dashboard redirects anonymous visitors to /login" || fail "dashboard is open without a login"
[ "$(status "$url/settings")" = "302" ] && ok "settings page is locked too"                     || fail "settings page is open without a login"

login "definitely-not-the-password"
[ "$(status "$url/")" = "302" ] && ok "wrong password is refused" || fail "wrong password got in"

login "$pw"
[ "$(status "$url/")" = "200" ] || fail "correct password was refused (did you run set-password.sh and restart?)"
ok "correct password logs in"

echo "Persistence:"
test_url="https://example.com/?persistence-check=$(date +%s)"
token="$(csrf "$url/")"
curl -s -o /dev/null -b "$jar" -c "$jar" \
  --data-urlencode "csrf_token=$token" --data-urlencode "url=$test_url" \
  --data-urlencode "processor=text_json_diff" --data-urlencode "watch_submit_button=Watch" \
  "$url/form/add/quickwatch"
[[ "$(page)" == *"$test_url"* ]] && ok "added test watch $test_url" || fail "could not add a watch"

echo "  ..    docker compose down && up (containers are destroyed and recreated)"
docker compose down >/dev/null 2>&1
up
wait_up

login "$pw"
[[ "$(page)" == *"$test_url"* ]] && ok "watch is still there after recreate" || fail "watch was lost"

echo
echo "All good. You can delete the example.com test watch in the UI."
