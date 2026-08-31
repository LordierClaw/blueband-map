#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 2 ]] || { echo "usage: $0 route|style key-file" >&2; exit 2; }
mode=$1
key_file=$2
case "$mode" in route|style) ;; *) exit 2 ;; esac
[[ -f "$key_file" ]] || { echo 'key file is missing' >&2; exit 1; }
key_mode=$(stat -c %a "$key_file" 2>/dev/null || stat -f %Lp "$key_file")
[[ "$key_mode" == 600 ]] || { echo 'key file must have mode 600' >&2; exit 1; }
key=$(<"$key_file")
[[ -n "$key" && "$key" != *$'\n'* && "$key" != *$'\r'* && "$key" != *$'\t'* && "$key" != *'"'* && "$key" != *'\'* ]] || {
  echo 'key file contains unsupported characters' >&2; exit 1;
}

project_root=$(git rev-parse --show-toplevel)
output_dir="$project_root/local/provider-smoke"
mkdir -p "$output_dir"
temp_dir=$(mktemp -d "$output_dir/.tmp.XXXXXX")
trap 'rm -rf -- "$temp_dir"' EXIT
headers="$temp_dir/headers"
body="$temp_dir/body"
curl_log="$temp_dir/curl.log"
curl_bin=${CURL_BIN:-curl}

if [[ "$mode" == route ]]; then
  endpoint="https://maps.vietmap.vn/api/route/v4?apikey=$key&point=10.759157,106.675859&point=10.771000,106.690000&points_encoded=true&vehicle=motorcycle"
  maximum_bytes=$((256 * 1024))
else
  endpoint="https://maps.vietmap.vn/maps/styles/tm/style.json?apikey=$key"
  maximum_bytes=$((2 * 1024 * 1024))
fi

set +e
printf 'url = "%s"\nrequest = "GET"\n' "$endpoint" | "$curl_bin" \
  --silent --show-error --config - --dump-header "$headers" --output "$body" \
  --connect-timeout 5 --max-time 20 --max-filesize "$maximum_bytes" --max-redirs 0 2>"$curl_log"
curl_status=$?
set -e
[[ $curl_status -eq 0 ]] || { echo 'provider request failed' >&2; exit 1; }

http_status=$(awk '/^HTTP\/[0-9.]+[[:space:]]+[0-9]+/ { status=$2 } END { print status }' "$headers")
[[ "$http_status" =~ ^2[0-9][0-9]$ ]] || { echo 'provider returned a non-success status' >&2; exit 1; }
content_type=$(awk 'tolower($1) == "content-type:" { sub(/^[^:]*:[[:space:]]*/, ""); print }' "$headers" | tail -n 1)
content_type=$(printf '%s' "${content_type%%;*}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
[[ "$content_type" == application/json ]] || { echo 'provider returned an unexpected content type' >&2; exit 1; }

python3 - "$mode" "$body" <<'PY'
import json, sys
mode, path = sys.argv[1:]
with open(path, "rb") as handle:
    payload = json.load(handle)
if mode == "route":
    paths = payload.get("paths")
    if payload.get("code") != "OK" or not isinstance(paths, list) or len(paths) != 1:
        raise SystemExit("invalid route response")
    route = paths[0]
    if not isinstance(route.get("points"), str) or not isinstance(route.get("instructions"), list):
        raise SystemExit("invalid route response")
elif payload.get("version") != 8:
    raise SystemExit("invalid style response")
PY

byte_count=$(wc -c <"$body" | tr -d '[:space:]')
[[ "$byte_count" =~ ^[0-9]+$ && "$byte_count" -le "$maximum_bytes" ]] || {
  echo 'provider response exceeded the configured byte limit' >&2
  exit 1
}
digest=$(sha256sum "$body" | awk '{print $1}')
record_path=$(mktemp "$output_dir/${mode}.XXXXXX")
printf 'mode=%s\nstatus=%s\ncontent_type=%s\nbytes=%s\nsha256=%s\n' \
  "$mode" "$http_status" "$content_type" "$byte_count" "$digest" >"$record_path"
printf 'record=%s\nmode=%s\nstatus=%s\ncontent_type=%s\nbytes=%s\nsha256=%s\n' \
  "$record_path" "$mode" "$http_status" "$content_type" "$byte_count" "$digest"
