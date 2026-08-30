#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
fixture_root=$(mktemp -d /tmp/blueband-handoff-test.XXXXXX)
trap 'rm -rf -- "$fixture_root"' EXIT

repo="$fixture_root/repo"
sources="$fixture_root/sources"
mkdir -p "$repo/scripts" "$repo/docs/testing/handoffs" "$sources"
cp "$project_root/scripts/prepare-poc-handoff.sh" "$repo/scripts/prepare-poc-handoff.sh"
chmod 0755 "$repo/scripts/prepare-poc-handoff.sh"

git -C "$repo" init -q
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.invalid
printf '# M1 handoff\n\nKhông có IPA.\n' >"$repo/docs/testing/handoffs/m1.md"
git -C "$repo" add scripts/prepare-poc-handoff.sh docs/testing/handoffs/m1.md
git -C "$repo" commit -qm base
initial_branch=$(git -C "$repo" branch --show-current)
full_commit=$(git -C "$repo" rev-parse HEAD)
short_commit=$(git -C "$repo" rev-parse --short=7 HEAD)

printf 'rpk-fixture-without-secrets\n' >"$sources/blueband.rpk"
printf 'ipa-fixture-without-secrets\n' >"$sources/blueband.ipa"

output=$("$repo/scripts/prepare-poc-handoff.sh" \
  --poc m1 --commit "$full_commit" \
  --handoff docs/testing/handoffs/m1.md \
  --ipa "$sources/blueband.ipa" --rpk "$sources/blueband.rpk")
bundle="$repo/artifacts/m1/$short_commit"
test -f "$bundle/HANDOFF.md"
test -f "$bundle/blueband.ipa"
test -f "$bundle/blueband.rpk"
test -f "$bundle/SHA256SUMS"
cmp -s "$repo/docs/testing/handoffs/m1.md" "$bundle/HANDOFF.md"
(cd "$bundle" && sha256sum -c SHA256SUMS)
test "$(sed -n '1p' "$bundle/SHA256SUMS" | awk '{print $2}')" = "blueband.ipa"
test "$(sed -n '2p' "$bundle/SHA256SUMS" | awk '{print $2}')" = "blueband.rpk"
grep -q "bundle=artifacts/m1/$short_commit" <<<"$output"
if grep -q 'fixture-without-secrets' <<<"$output"; then
  echo 'packager printed artifact content' >&2
  exit 1
fi

"$repo/scripts/prepare-poc-handoff.sh" \
  --poc rpk-only --commit HEAD --handoff docs/testing/handoffs/m1.md \
  --rpk "$sources/blueband.rpk"
rpk_only_bundle="$repo/artifacts/rpk-only/$short_commit"
test -f "$rpk_only_bundle/blueband.rpk"
test ! -e "$rpk_only_bundle/blueband.ipa"
test "$(wc -l <"$rpk_only_bundle/SHA256SUMS")" -eq 1
(cd "$rpk_only_bundle" && sha256sum -c SHA256SUMS)

"$repo/scripts/prepare-poc-handoff.sh" \
  --poc ipa-only --commit HEAD --handoff docs/testing/handoffs/m1.md \
  --ipa "$sources/blueband.ipa"
ipa_only_bundle="$repo/artifacts/ipa-only/$short_commit"
test -f "$ipa_only_bundle/blueband.ipa"
test ! -e "$ipa_only_bundle/blueband.rpk"
test "$(wc -l <"$ipa_only_bundle/SHA256SUMS")" -eq 1
(cd "$ipa_only_bundle" && sha256sum -c SHA256SUMS)

"$repo/scripts/prepare-poc-handoff.sh" \
  --poc docs-only --commit HEAD --handoff docs/testing/handoffs/m1.md
docs_only_bundle="$repo/artifacts/docs-only/$short_commit"
test -f "$docs_only_bundle/HANDOFF.md"
test -f "$docs_only_bundle/SHA256SUMS"
test ! -s "$docs_only_bundle/SHA256SUMS"
test -z "$(find "$docs_only_bundle" -maxdepth 1 -type f \( -name '*.ipa' -o -name '*.rpk' \) -print -quit)"

set +e
existing_output=$("$repo/scripts/prepare-poc-handoff.sh" \
  --poc m1 --commit HEAD --handoff docs/testing/handoffs/m1.md \
  --rpk "$sources/blueband.rpk" 2>&1)
existing_status=$?
set -e
test "$existing_status" -ne 0
grep -q 'destination already exists' <<<"$existing_output"

printf '\nlocal dirty change\n' >>"$repo/docs/testing/handoffs/m1.md"
set +e
dirty_output=$("$repo/scripts/prepare-poc-handoff.sh" \
  --poc dirty --commit HEAD --handoff docs/testing/handoffs/m1.md 2>&1)
dirty_status=$?
set -e
test "$dirty_status" -ne 0
grep -q 'handoff must be clean' <<<"$dirty_output"
git -C "$repo" checkout -q -- docs/testing/handoffs/m1.md

printf 'wrong extension\n' >"$sources/not-rpk.bin"
: >"$sources/empty.rpk"
ln -s "$sources/blueband.rpk" "$sources/link.rpk"

for case_name in wrong empty symlink; do
  case "$case_name" in
    wrong) source_path="$sources/not-rpk.bin" ;;
    empty) source_path="$sources/empty.rpk" ;;
    symlink) source_path="$sources/link.rpk" ;;
  esac
  set +e
  validation_output=$("$repo/scripts/prepare-poc-handoff.sh" \
    --poc "$case_name" --commit HEAD --handoff docs/testing/handoffs/m1.md \
    --rpk "$source_path" 2>&1)
  validation_status=$?
  set -e
  test "$validation_status" -ne 0
  test ! -e "$repo/artifacts/$case_name/$short_commit"
done

git -C "$repo" checkout -q --orphan unrelated
git -C "$repo" rm -q -rf .
printf 'unrelated\n' >"$repo/unrelated.txt"
git -C "$repo" add unrelated.txt
git -C "$repo" commit -qm unrelated
unrelated_commit=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" checkout -q "$initial_branch"
set +e
ancestor_output=$("$repo/scripts/prepare-poc-handoff.sh" \
  --poc unrelated --commit "$unrelated_commit" \
  --handoff docs/testing/handoffs/m1.md 2>&1)
ancestor_status=$?
set -e
test "$ancestor_status" -ne 0
grep -q 'commit must be an ancestor' <<<"$ancestor_output"

if find "$repo/artifacts" -maxdepth 1 -name '.tmp-*' -print -quit | grep -q .; then
  echo 'temporary packaging directory leaked' >&2
  exit 1
fi
