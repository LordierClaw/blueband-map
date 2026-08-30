#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo 'usage: prepare-poc-handoff.sh --poc NAME --commit REV --handoff PATH [--ipa PATH] [--rpk PATH]' >&2
  exit 2
}

poc=''
revision=''
handoff=''
ipa=''
rpk=''

while [ "$#" -gt 0 ]; do
  case "$1" in
    --poc|--commit|--handoff|--ipa|--rpk)
      [ "$#" -ge 2 ] || usage
      case "$1" in
        --poc) poc=$2 ;;
        --commit) revision=$2 ;;
        --handoff) handoff=$2 ;;
        --ipa) ipa=$2 ;;
        --rpk) rpk=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done

[ -n "$poc" ] && [ -n "$revision" ] && [ -n "$handoff" ] || usage
[[ "$poc" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]] || {
  echo 'invalid POC name' >&2
  exit 2
}

repository_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --show-toplevel)
full_commit=$(git -C "$repository_root" rev-parse --verify "${revision}^{commit}")
git -C "$repository_root" merge-base --is-ancestor "$full_commit" HEAD || {
  echo 'commit must be an ancestor of HEAD' >&2
  exit 2
}
short_commit=$(git -C "$repository_root" rev-parse --short=7 "$full_commit")

case "$handoff" in
  /*)
    echo 'handoff path must be repository-relative' >&2
    exit 2
    ;;
esac
handoff_path="$repository_root/$handoff"
[ -f "$handoff_path" ] && [ ! -L "$handoff_path" ] || {
  echo 'handoff must be a regular file' >&2
  exit 2
}
git -C "$repository_root" ls-files --error-unmatch -- "$handoff" >/dev/null 2>&1 || {
  echo 'handoff must be tracked' >&2
  exit 2
}
git -C "$repository_root" diff --quiet -- "$handoff" &&
  git -C "$repository_root" diff --cached --quiet -- "$handoff" || {
    echo 'handoff must be clean' >&2
    exit 2
  }

validate_artifact() {
  local kind=$1
  local path=$2
  [ -n "$path" ] || return 0
  [ -f "$path" ] && [ ! -L "$path" ] && [ -s "$path" ] || {
    printf '%s must be a non-empty regular file\n' "$kind" >&2
    exit 2
  }
  case "$kind:$path" in
    ipa:*.ipa|rpk:*.rpk) ;;
    *)
      printf '%s has the wrong extension\n' "$kind" >&2
      exit 2
      ;;
  esac
}

validate_artifact ipa "$ipa"
validate_artifact rpk "$rpk"

destination_parent="$repository_root/artifacts/$poc"
destination="$destination_parent/$short_commit"
[ ! -e "$destination" ] || {
  echo 'destination already exists' >&2
  exit 2
}
mkdir -p "$repository_root/artifacts" "$destination_parent"
temporary=$(mktemp -d "$repository_root/artifacts/.tmp-${poc}-${short_commit}.XXXXXX")
cleanup() {
  [ -z "${temporary:-}" ] || rm -rf -- "$temporary"
}
trap cleanup EXIT

cp -- "$handoff_path" "$temporary/HANDOFF.md"
for artifact in "$ipa" "$rpk"; do
  [ -n "$artifact" ] || continue
  cp -- "$artifact" "$temporary/$(basename "$artifact")"
done

mapfile -t artifact_names < <(
  find "$temporary" -maxdepth 1 -type f \( -name '*.ipa' -o -name '*.rpk' \) \
    -printf '%f\n' | LC_ALL=C sort
)
: >"$temporary/SHA256SUMS"
for artifact_name in "${artifact_names[@]}"; do
  (cd "$temporary" && sha256sum -- "$artifact_name")
done >"$temporary/SHA256SUMS"
if [ "${#artifact_names[@]}" -gt 0 ]; then
  (cd "$temporary" && sha256sum -c SHA256SUMS)
fi

mv -- "$temporary" "$destination"
temporary=''
printf 'bundle=artifacts/%s/%s\n' "$poc" "$short_commit"
for artifact_name in "${artifact_names[@]}"; do
  size=$(stat -c '%s' "$destination/$artifact_name")
  digest=$(sha256sum "$destination/$artifact_name" | awk '{print $1}')
  printf 'artifact=%s bytes=%s sha256=%s\n' "$artifact_name" "$size" "$digest"
done
