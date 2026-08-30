#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
workflows_root="$project_root/.github/workflows"

if [[ -e "$workflows_root/linux-checks.yml" ]]; then
  echo 'legacy linux-checks.yml must be removed' >&2
  exit 1
fi

grep -q 'make test-ci-metadata && make lint' "$workflows_root/repo-checks.yml"
grep -q "packages/BlueBandKit/\*\*" "$workflows_root/swift-checks.yml"
grep -q "apps/band/\*\*" "$workflows_root/band-checks.yml"
grep -q "tools/protocol-lab/\*\*" "$workflows_root/protocol-lab-checks.yml"

if grep -Eq 'docker compose|runs-on: macos' "$workflows_root/repo-checks.yml"; then
  echo 'repo-checks must not use Docker Compose or a macOS runner' >&2
  exit 1
fi

grep -q 'weak var weakSession = session' \
  "$project_root/packages/BlueBandKit/Tests/BlueBandCoreTests/InterconnectSessionTests.swift"
