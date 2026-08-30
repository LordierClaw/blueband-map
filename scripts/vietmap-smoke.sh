#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 static|style key-file" >&2
  exit 2
}

[[ $# -eq 2 ]] || usage
mode=$1
key_file=$2
case "$mode" in
  static|style) ;;
  *) usage ;;
esac

project_root=$(git rev-parse --show-toplevel)
if [[ ! -f "$key_file" ]]; then
  echo 'key file is missing' >&2
  exit 1
fi

key_mode=$(stat -c %a "$key_file" 2>/dev/null || stat -f %Lp "$key_file")
if [[ "$key_mode" != 600 ]]; then
  echo 'key file must have mode 600' >&2
  exit 1
fi

key=$(<"$key_file")
case "$key" in
  '')
    echo 'key file is empty' >&2
    exit 1
    ;;
  *$'\n'*|*$'\r'*|*$'\t'*|*'"'*|*'\\'*)
    echo 'key file contains unsupported characters' >&2
    exit 1
    ;;
esac

curl_bin=${CURL_BIN:-curl}
if [[ "$curl_bin" == */* ]]; then
  [[ -x "$curl_bin" ]] || { echo 'curl executable is unavailable' >&2; exit 1; }
else
  command -v "$curl_bin" >/dev/null 2>&1 || { echo 'curl executable is unavailable' >&2; exit 1; }
fi

output_dir="$project_root/local/provider-smoke"
mkdir -p "$output_dir"
temp_dir=$(mktemp -d "$output_dir/.tmp.XXXXXX")
cleanup() {
  rm -rf -- "$temp_dir"
}
trap cleanup EXIT

headers="$temp_dir/headers"
body="$temp_dir/body"
curl_log="$temp_dir/curl.log"

if [[ "$mode" == static ]]; then
  expected_content_type='image/png'
  maximum_bytes=$((64 * 1024))
  endpoint='https://maps.vietmap.vn/api/maps/statics/tm'
  request_method='POST'
  config_lines=(
    "url = \"$endpoint\""
    "request = \"$request_method\""
    'form = "lat=10.759157"'
    'form = "lng=106.675859"'
    "form = \"apikey=$key\""
    'form = "zoom=17"'
    'form = "size=212x360"'
  )
else
  expected_content_type='application/json'
  maximum_bytes=$((2 * 1024 * 1024))
  endpoint="https://maps.vietmap.vn/maps/styles/tm/style.json?apikey=$key"
  config_lines=(
    "url = \"$endpoint\""
    'request = "GET"'
  )
fi

set +e
{
  printf '%s\n' "${config_lines[@]}"
} | "$curl_bin" \
  --silent \
  --show-error \
  --config - \
  --dump-header "$headers" \
  --output "$body" \
  --connect-timeout 5 \
  --max-time 20 \
  --max-filesize "$maximum_bytes" \
  --max-redirs 0 \
  2>"$curl_log"
curl_status=$?
set -e
if [[ $curl_status -ne 0 ]]; then
  echo 'provider request failed' >&2
  exit 1
fi

http_status=$(awk '/^HTTP\/[0-9.]+[[:space:]]+[0-9]+/ { status=$2 } END { print status }' "$headers")
if [[ ! "$http_status" =~ ^[0-9]+$ ]] || ((http_status < 200 || http_status > 299)); then
  echo 'provider returned a non-success status' >&2
  exit 1
fi

content_type=$(awk '
  tolower($1) == "content-type:" { sub(/^[^:]*:[[:space:]]*/, ""); print }
' "$headers" | tail -n 1)
content_type=${content_type%%;*}
content_type=$(printf '%s' "$content_type" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
if [[ "$content_type" != "$expected_content_type" ]]; then
  echo 'provider returned an unexpected content type' >&2
  exit 1
fi

byte_count=$(wc -c <"$body" | tr -d '[:space:]')
if [[ ! "$byte_count" =~ ^[0-9]+$ ]] || ((byte_count > maximum_bytes)); then
  echo 'provider response exceeded the configured byte limit' >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  digest=$(sha256sum "$body" | awk '{print $1}')
else
  digest=$(shasum -a 256 "$body" | awk '{print $1}')
fi

dimensions='not-applicable'
if [[ "$mode" == static ]]; then
  signature=$(od -An -tx1 -N8 "$body" | tr -d '[:space:]')
  if [[ "$signature" != '89504e470d0a1a0a' ]]; then
    echo 'provider returned an invalid PNG signature' >&2
    exit 1
  fi
  read -r p0 p1 p2 p3 p4 p5 p6 p7 < <(od -An -tu1 -j16 -N8 "$body")
  width=$(( (p0 << 24) | (p1 << 16) | (p2 << 8) | p3 ))
  height=$(( (p4 << 24) | (p5 << 16) | (p6 << 8) | p7 ))
  if ((width <= 0 || height <= 0)); then
    echo 'provider returned invalid PNG dimensions' >&2
    exit 1
  fi
  dimensions="${width}x${height}"
fi

record_path=$(mktemp "$output_dir/${mode}.XXXXXX")
{
  printf 'mode=%s\n' "$mode"
  printf 'status=%s\n' "$http_status"
  printf 'content_type=%s\n' "$content_type"
  printf 'bytes=%s\n' "$byte_count"
  printf 'dimensions=%s\n' "$dimensions"
  printf 'sha256=%s\n' "$digest"
} >"$record_path"

printf 'record=%s\n' "$record_path"
printf 'mode=%s\n' "$mode"
printf 'status=%s\n' "$http_status"
printf 'content_type=%s\n' "$content_type"
printf 'bytes=%s\n' "$byte_count"
printf 'dimensions=%s\n' "$dimensions"
printf 'sha256=%s\n' "$digest"
