#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
fixture_root=$(mktemp -d /tmp/blueband-vietmap-smoke.XXXXXX)
trap 'rm -rf -- "$fixture_root"' EXIT

secret='vietmap-test-secret-never-print'
printf '%s' "$secret" >"$fixture_root/service-key"
chmod 600 "$fixture_root/service-key"

base64_png='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
printf '%s' "$base64_png" | base64 -d >"$fixture_root/map.png"

fake_curl="$fixture_root/curl"
cat >"$fake_curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail

config=$(cat)
printf '%s\n' "${FAKE_CURL_MODE:?}" >>"${FAKE_CURL_CALLS:?}"
grep -Fq "${FAKE_CURL_EXPECTED_KEY:?}" <<<"$config"

dump_headers=''
output_file=''
while (($# > 0)); do
  case "$1" in
    --dump-header|-D) dump_headers=$2; shift 2 ;;
    --output|-o) output_file=$2; shift 2 ;;
    *) shift ;;
  esac
done

case "$FAKE_CURL_MODE" in
  static)
    printf 'HTTP/1.1 200 OK\r\nContent-Type: image/png; charset=binary\r\n\r\n' >"$dump_headers"
    cp "$FAKE_CURL_PNG_FILE" "$output_file"
    ;;
  wrong-content-type)
    printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n' >"$dump_headers"
    printf '{}' >"$output_file"
    ;;
  style)
    printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\n\r\n' >"$dump_headers"
    printf '{"version":8}' >"$output_file"
    ;;
  *)
    echo "unknown fake curl mode" >&2
    exit 1
    ;;
esac
FAKE_CURL
chmod 700 "$fake_curl"

calls="$fixture_root/calls"
: >"$calls"

run_static=$(
  CURL_BIN="$fake_curl" \
  FAKE_CURL_MODE=static \
  FAKE_CURL_CALLS="$calls" \
  FAKE_CURL_EXPECTED_KEY="$secret" \
  FAKE_CURL_PNG_FILE="$fixture_root/map.png" \
  scripts/vietmap-smoke.sh static "$fixture_root/service-key"
)
test "$(wc -l <"$calls")" = 1
grep -Fq 'content_type=image/png' <<<"$run_static"
grep -Fq 'dimensions=1x1' <<<"$run_static"
grep -Fq 'bytes=' <<<"$run_static"
grep -Fq 'sha256=' <<<"$run_static"
static_record=$(sed -n 's/^record=//p' <<<"$run_static")
test -n "$static_record"
case "$static_record" in
  "$project_root/local/provider-smoke/"*) ;;
  *) echo 'static record escaped provider-smoke directory' >&2; exit 1 ;;
esac
test -f "$static_record"
! grep -Fq "$secret" <<<"$run_static"
! grep -Fq "$secret" "$static_record"

set +e
wrong_output=$(
  CURL_BIN="$fake_curl" \
  FAKE_CURL_MODE=wrong-content-type \
  FAKE_CURL_CALLS="$calls" \
  FAKE_CURL_EXPECTED_KEY="$secret" \
  FAKE_CURL_PNG_FILE="$fixture_root/map.png" \
  scripts/vietmap-smoke.sh static "$fixture_root/service-key" 2>&1
)
wrong_status=$?
set -e
test "$wrong_status" -ne 0
test "$(wc -l <"$calls")" = 2
! grep -Fq "$secret" <<<"$wrong_output"

run_style=$(
  CURL_BIN="$fake_curl" \
  FAKE_CURL_MODE=style \
  FAKE_CURL_CALLS="$calls" \
  FAKE_CURL_EXPECTED_KEY="$secret" \
  FAKE_CURL_PNG_FILE="$fixture_root/map.png" \
  scripts/vietmap-smoke.sh style "$fixture_root/service-key"
)
test "$(wc -l <"$calls")" = 3
grep -Fq 'content_type=application/json' <<<"$run_style"
grep -Fq 'dimensions=not-applicable' <<<"$run_style"
grep -Fq 'bytes=' <<<"$run_style"
grep -Fq 'sha256=' <<<"$run_style"
style_record=$(sed -n 's/^record=//p' <<<"$run_style")
test -f "$style_record"
case "$style_record" in
  "$project_root/local/provider-smoke/"*) ;;
  *) echo 'style record escaped provider-smoke directory' >&2; exit 1 ;;
esac
! grep -Fq "$secret" <<<"$run_style"
! grep -Fq "$secret" "$style_record"

set +e
missing_output=$(scripts/vietmap-smoke.sh static "$fixture_root/missing-key" 2>&1)
missing_status=$?
set -e
test "$missing_status" -ne 0
test "$(wc -l <"$calls")" = 3
! grep -Fq "$secret" <<<"$missing_output"

chmod 640 "$fixture_root/service-key"
set +e
permission_output=$(scripts/vietmap-smoke.sh static "$fixture_root/service-key" 2>&1)
permission_status=$?
set -e
test "$permission_status" -ne 0
test "$(wc -l <"$calls")" = 3
! grep -Fq "$secret" <<<"$permission_output"

rm -f -- "$static_record" "$style_record"
echo 'vietmap smoke script tests passed'
