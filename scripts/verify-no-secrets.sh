#!/usr/bin/env bash
set -euo pipefail

repository_root=${1:-$(git rev-parse --show-toplevel)}

if ! git -C "$repository_root" rev-parse --git-dir >/dev/null 2>&1; then
  echo "not a git repository: $repository_root" >&2
  exit 2
fi

failed=0
auth_assignment_pattern="(auth[_-]?key|AUTH_KEY)[[:space:]]*[:=][[:space:]]*[\"']?[0-9a-fA-F]{32}([\"']|$)"

while IFS= read -r tracked_path; do
  case "$tracked_path" in
    .env|*.p12|*.mobileprovision|*.pem|*.key|captures/raw/*|local/*|sign/*)
      printf 'forbidden tracked secret path: %s\n' "$tracked_path" >&2
      failed=1
      ;;
  esac
done < <(git -C "$repository_root" ls-files)

while IFS= read -r tracked_path; do
  [ -f "$repository_root/$tracked_path" ] || continue
  if grep -Eiq "$auth_assignment_pattern" "$repository_root/$tracked_path"; then
    printf 'possible AuthKey assignment in tracked file: %s\n' "$tracked_path" >&2
    failed=1
  fi
done < <(git -C "$repository_root" ls-files)

exit "$failed"
