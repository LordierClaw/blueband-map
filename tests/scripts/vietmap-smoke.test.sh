#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
fixture_root=$(mktemp -d /tmp/blueband-vietmap-smoke.XXXXXX)
trap 'rm -rf -- "$fixture_root"' EXIT
secret='vietmap-test-secret-never-print'
printf '%s' "$secret" >"$fixture_root/key"
chmod 600 "$fixture_root/key"
calls="$fixture_root/calls"
: >"$calls"

fake_curl="$fixture_root/curl"
cat >"$fake_curl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
config=$(cat)
grep -Fq "${FAKE_KEY:?}" <<<"$config"
printf '%s\n' "${FAKE_MODE:?}" >>"${FAKE_CALLS:?}"
while (($#)); do
  case "$1" in
    --dump-header) headers=$2; shift 2 ;;
    --output) body=$2; shift 2 ;;
    *) shift ;;
  esac
done
printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n' >"$headers"
if [[ "$FAKE_MODE" == route ]]; then
  printf '{"code":"OK","paths":[{"points":"abc","instructions":[]}]}' >"$body"
else
  printf '{"version":8}' >"$body"
fi
FAKE
chmod 700 "$fake_curl"

for mode in route style; do
  output=$(CURL_BIN="$fake_curl" FAKE_MODE="$mode" FAKE_CALLS="$calls" FAKE_KEY="$secret" \
    scripts/vietmap-smoke.sh "$mode" "$fixture_root/key")
  grep -Fq "mode=$mode" <<<"$output"
  grep -Fq 'content_type=application/json' <<<"$output"
  ! grep -Fq "$secret" <<<"$output"
  record=$(sed -n 's/^record=//p' <<<"$output")
  [[ "$record" == "$project_root/local/provider-smoke/"* ]]
  ! grep -Fq "$secret" "$record"
  rm -f -- "$record"
done
[[ $(wc -l <"$calls") -eq 2 ]]

chmod 640 "$fixture_root/key"
! scripts/vietmap-smoke.sh route "$fixture_root/key" >/dev/null 2>&1
[[ $(wc -l <"$calls") -eq 2 ]]
echo 'vietmap smoke script tests passed'
