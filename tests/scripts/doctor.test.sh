#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
output=$("$project_root/scripts/doctor.sh")

grep -q '^PASS  git ' <<<"$output"
grep -q '^PASS  docker ' <<<"$output"
grep -q '^PASS  compose ' <<<"$output"
grep -q '^PASS  make ' <<<"$output"
grep -q '^INFO  xcode unavailable on Linux (expected)$' <<<"$output"
grep -q '^SUMMARY pass=' <<<"$output"
