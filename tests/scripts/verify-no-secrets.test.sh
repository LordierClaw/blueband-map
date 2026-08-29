#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
fixture_root=$(mktemp -d /tmp/blueband-secret-test.XXXXXX)
trap 'rm -rf -- "$fixture_root"' EXIT

git -C "$fixture_root" init -q
printf 'safe=true\n' >"$fixture_root/config.txt"
git -C "$fixture_root" add config.txt
"$project_root/scripts/verify-no-secrets.sh" "$fixture_root"

printf 'AUTH_KEY=00112233445566778899aabbccddeeff\n' >"$fixture_root/unsafe.env"
git -C "$fixture_root" add -f unsafe.env
set +e
output=$("$project_root/scripts/verify-no-secrets.sh" "$fixture_root" 2>&1)
status=$?
set -e

test "$status" -ne 0
grep -q 'unsafe.env' <<<"$output"
if grep -q '00112233445566778899aabbccddeeff' <<<"$output"; then
  echo 'secret gate printed matched secret content' >&2
  exit 1
fi
