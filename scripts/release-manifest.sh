#!/usr/bin/env bash
set -euo pipefail

output_dir="${1:-}"
commit_sha="${2:-}"
if [[ -z "$output_dir" || -z "$commit_sha" || ! -d "$output_dir" ]]; then
  echo "usage: $0 OUTPUT_DIR COMMIT_SHA" >&2
  exit 2
fi

ios_version=$(awk '/MARKETING_VERSION:/ { print $2; exit }' apps/ios/project.yml)
rpk_version=$(node -e 'process.stdout.write(require("./apps/band/src/manifest.json").versionName)')
python3 - "$output_dir/release-manifest.json" "$ios_version" "$rpk_version" "$commit_sha" <<'PY'
import json, pathlib, sys
path, ios, rpk, commit = sys.argv[1:]
payload = {
    "product": "BlueBandMap",
    "iosVersion": ios,
    "rpkVersion": rpk,
    "applicationEnvelopeVersion": 1,
    "commit": commit,
    "signed": False,
}
pathlib.Path(path).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
