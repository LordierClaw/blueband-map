#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
fixture_root=$(mktemp -d /tmp/blueband-secret-test.XXXXXX)
trap 'rm -rf -- "$fixture_root"' EXIT

git -C "$fixture_root" init -q
printf 'safe=true\n' >"$fixture_root/config.txt"
git -C "$fixture_root" add config.txt
"$project_root/scripts/verify-no-secrets.sh" "$fixture_root"

synthetic_key=$(printf 'a%.0s' {1..32})
printf 'AUTH_KEY=%s\n' "$synthetic_key" >"$fixture_root/unsafe.env"
git -C "$fixture_root" add -f unsafe.env
set +e
output=$("$project_root/scripts/verify-no-secrets.sh" "$fixture_root" 2>&1)
status=$?
set -e

test "$status" -ne 0
grep -q 'unsafe.env' <<<"$output"
if grep -q "$synthetic_key" <<<"$output"; then
  echo 'secret gate printed matched secret content' >&2
  exit 1
fi

printf 'binary-placeholder\n' >"$fixture_root/test.rpk"
mkdir -p "$fixture_root/artifacts/m1/build"
mv "$fixture_root/test.rpk" "$fixture_root/artifacts/m1/build/test.rpk"
git -C "$fixture_root" add -f artifacts/m1/build/test.rpk
set +e
artifact_output=$("$project_root/scripts/verify-no-secrets.sh" "$fixture_root" 2>&1)
artifact_status=$?
set -e
test "$artifact_status" -ne 0
grep -q 'artifacts/m1/build/test.rpk' <<<"$artifact_output"
