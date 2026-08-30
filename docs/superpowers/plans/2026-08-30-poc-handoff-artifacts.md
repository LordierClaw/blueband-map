# POC Handoff Artifacts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a tested, immutable local artifact-bundling workflow and produce the first complete M1 developer handoff with an RPK path, verified digest, explicit missing-IPA status and owner test steps.

**Architecture:** A Bash command accepts explicit artifact and committed-handoff inputs, validates them against the current repository, stages copies under ignored `artifacts/`, writes deterministic SHA-256 evidence and atomically publishes `artifacts/<poc>/<short-commit>/`. A committed Markdown record remains the durable, binary-free history; the M1 record links to the authoritative hardware packet and identifies the Linux/macOS build boundary.

**Tech Stack:** Bash with strict mode, Git, POSIX file utilities, `sha256sum`, Make, Markdown, existing shell-test conventions.

---

## File structure

- `scripts/prepare-poc-handoff.sh`: the only artifact-packaging entry point; validates explicit inputs and atomically publishes one immutable bundle.
- `tests/scripts/prepare-poc-handoff.test.sh`: isolated temporary-Git-repository behavioral tests for successful bundles, validation, immutability, cleanup and output secrecy.
- `.gitignore`: ignores all local handoff binaries under `artifacts/`.
- `Makefile`: exposes `make test-handoff` and includes it in `make test`.
- `scripts/verify-no-secrets.sh`: rejects any force-tracked `artifacts/` path.
- `tests/scripts/verify-no-secrets.test.sh`: proves the tracked-artifact gate.
- `docs/testing/handoffs/m1-5e7ff51.md`: durable M1 developer handoff in Vietnamese.
- `docs/testing/hardware-acceptance.md`: makes the developer handoff and artifact-path report mandatory for every POC.
- `artifacts/m1/5e7ff51/`: ignored generated bundle containing `HANDOFF.md`, `SHA256SUMS` and the current debug RPK; no IPA is fabricated.

## Task 1: Define and implement immutable artifact packaging

**Files:**
- Create: `tests/scripts/prepare-poc-handoff.test.sh`
- Create: `scripts/prepare-poc-handoff.sh`
- Modify: `.gitignore`
- Modify: `Makefile`
- Modify: `scripts/verify-no-secrets.sh`
- Modify: `tests/scripts/verify-no-secrets.test.sh`

- [ ] **Step 1: Write the failing packaging contract test**

Create `tests/scripts/prepare-poc-handoff.test.sh` with strict mode. The test creates a temporary Git repository, copies the packaging script into `scripts/`, commits a Vietnamese handoff record, creates non-secret fake IPA/RPK files outside the repository and verifies these behaviors:

```bash
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
```

The implementation file does not exist yet, so create a temporary executable stub containing only strict mode and `exit 1` before the first test run. This keeps the failure attributable to missing behavior rather than a missing command.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
bash tests/scripts/prepare-poc-handoff.test.sh
```

Expected: non-zero exit at the first assertion because no bundle is created.

- [ ] **Step 3: Implement the packaging command**

Replace the stub with this complete structure in `scripts/prepare-poc-handoff.sh`:

```bash
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
  /*) echo 'handoff path must be repository-relative' >&2; exit 2 ;;
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
    *) printf '%s has the wrong extension\n' "$kind" >&2; exit 2 ;;
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
cleanup() { [ -z "${temporary:-}" ] || rm -rf -- "$temporary"; }
trap cleanup EXIT

cp -- "$handoff_path" "$temporary/HANDOFF.md"
for artifact in "$ipa" "$rpk"; do
  [ -n "$artifact" ] || continue
  cp -- "$artifact" "$temporary/$(basename "$artifact")"
done

: >"$temporary/SHA256SUMS"
while IFS= read -r artifact_name; do
  (cd "$temporary" && sha256sum -- "$artifact_name")
done < <(find "$temporary" -maxdepth 1 -type f \( -name '*.ipa' -o -name '*.rpk' \) \
  -printf '%f\n' | LC_ALL=C sort) >"$temporary/SHA256SUMS"
(cd "$temporary" && sha256sum -c SHA256SUMS)

mv -- "$temporary" "$destination"
temporary=''
printf 'bundle=artifacts/%s/%s\n' "$poc" "$short_commit"
while IFS= read -r artifact_name; do
  size=$(stat -c '%s' "$destination/$artifact_name")
  digest=$(sha256sum "$destination/$artifact_name" | awk '{print $1}')
  printf 'artifact=%s bytes=%s sha256=%s\n' "$artifact_name" "$size" "$digest"
done < <(find "$destination" -maxdepth 1 -type f \( -name '*.ipa' -o -name '*.rpk' \) \
  -printf '%f\n' | LC_ALL=C sort)
```

The explicit temporary cleanup uses a task-specific path under `artifacts/`; it never targets the repository root or an environment-variable-derived broad directory.

- [ ] **Step 4: Integrate the contract into canonical checks and repository safety**

Add `artifacts/` to `.gitignore`.

Add `test-handoff` to `.PHONY`, include it in `test`, show it in `help`, and define:

```make
test: test-swift test-rpk test-lab test-ios-metadata test-handoff

test-handoff:
	bash tests/scripts/prepare-poc-handoff.test.sh
```

Extend the forbidden tracked-path case in `scripts/verify-no-secrets.sh`:

```bash
.env|*.p12|*.mobileprovision|*.pem|*.key|captures/raw/*|local/*|sign/*|artifacts/*)
```

Extend `tests/scripts/verify-no-secrets.test.sh` after the existing AuthKey assertion:

```bash
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
```

- [ ] **Step 5: Run focused and canonical shell checks**

Run:

```bash
make test-handoff
bash tests/scripts/verify-no-secrets.test.sh
bash -n scripts/*.sh tests/scripts/*.sh
git diff --check
```

Expected: all commands exit zero; temporary repositories and packaging directories are removed by their traps.

- [ ] **Step 6: Commit the packaging workflow**

```bash
git add .gitignore Makefile scripts/prepare-poc-handoff.sh \
  scripts/verify-no-secrets.sh tests/scripts/prepare-poc-handoff.test.sh \
  tests/scripts/verify-no-secrets.test.sh
git commit -m "feat: package immutable POC handoffs"
```

## Task 2: Create the durable M1 handoff record

**Files:**
- Create: `docs/testing/handoffs/m1-5e7ff51.md`
- Modify: `docs/testing/hardware-acceptance.md`

- [ ] **Step 1: Write the complete M1 handoff record**

Create `docs/testing/handoffs/m1-5e7ff51.md`. It must use these exact identity and artifact facts:

```markdown
# Bàn giao POC M1 — 5e7ff51

## Identity

- POC: M1 — one real Vietmap street PNG
- Source commit: `5e7ff511b0b51e7ca3cbf8514217bc1ccbb5f6f8`
- iOS source version/build: `0.1.0 (1)`
- RPK version/code: `0.2.0 (2)`
- Hardware status: implementation ready for owner hardware acceptance; not hardware-confirmed

## Tóm tắt đã làm

- Lưu AuthKey, Vietmap Service key và TileMap key riêng trong Keychain; nhớ Band đã chọn mà không lưu lộ UUID trong chẩn đoán.
- Chọn Band bằng dialog gọn, hoàn tất proof/RPK handshake và giữ luồng kết nối foreground-only.
- Gọi đúng một Vietmap Static Map request cho mỗi lần bấm M1, kiểm tra MIME, PNG 212×360 và giới hạn 200 KiB.
- Truyền asset theo stop-and-wait ACK với run ID, envelope tối đa 512 byte; Band ghi file, kiểm tra SHA-256, render và trả kết quả tương quan.
- Chặn retry mơ hồ cho tới khi reconnect; dọn file/ownership trước semantic retry; xử lý race ACK cuối/result và giới hạn bộ nhớ ID.
- Chưa triển khai M2 tile grid, pan, rotation, route/navigation, background mode hoặc TileMap request.

## Artifact bàn giao

| Loại | Trạng thái | Đường dẫn | Bytes | SHA-256 |
|---|---|---|---:|---|
| IPA | Không có | Không có | — | — |
| RPK debug | Có | `artifacts/m1/5e7ff51/dev.lordierclaw.bluebandmap.band.debug.0.2.0.rpk` | 18485 | `7acf4ff4e5ae56e612f44d07ff7c8bd0f7015a74b9458927cdf11668d8dfdaae` |

IPA chưa có vì host Ubuntu không thể chạy Xcode/iPhone build. Tạo IPA qua `.github/workflows/release-artifacts.yml` trên macOS, sau đó tạo một bundle bàn giao mới từ commit chứa artifact thực tế; không thay thế hoặc gán hash giả cho bundle này.

## Điều kiện trước khi test

- iPhone 13 Pro Max chạy iOS 26.x; ghi lại phiên bản chính xác.
- Xiaomi Smart Band 10; ghi lại firmware đang cài.
- Đóng hoàn toàn Mi Fitness trong phiên BlueBandMap.
- AuthKey và Vietmap Service key hiển thị trạng thái đã lưu; TileMap key là tùy chọn và M1 không sử dụng.
- Đứng yên khi thao tác; không dùng điện thoại hoặc Band khi điều khiển xe.
- Tối đa năm provider calls cho năm lần bấm M1; đóng/mở RPK không được tạo provider call.

## Các bước test

1. Xác minh commit, version và SHA-256 RPK khớp bảng artifact; nếu dùng IPA thì phải bổ sung identity/hash thật trước khi test.
2. Clean-install RPK 0.2.0 và xác nhận version trên Band.
3. Cài/launch iOS build, mở Config và xác nhận AuthKey/Service key vẫn được lưu nhưng không bị hiển thị.
4. Mở dialog Connect, chọn Band, hoàn tất device proof và RPK handshake tới trạng thái ready.
5. Bấm M1 đúng một lần; chờ `M1 MAP READY`, xác nhận ảnh nhận biết được, hash prefix tám ký tự khớp và không crash.
6. Lặp bước 5 tới đủ năm lần, luôn chờ lần trước hoàn tất; tổng provider calls không vượt quá năm.
7. Không bấm M1, đóng/mở RPK mười lần; provider-call delta phải bằng không và không có corruption/crash.
8. Thực hiện các kiểm tra recovery có fixture theo packet chi tiết, gồm stale run, timeout/reconnect, redirect bound, final ACK/result và cleanup ownership.

Packet đầy đủ và expected result cho từng recovery case: `docs/testing/results/2026-08-29-m1-test-packet.md`.

## Điều kiện dừng và phục hồi

Dừng ngay khi gặp HTTP 429/rate limit, ảnh hỏng hoặc sai hash, crash/hang, lộ secret/UUID hoặc thao tác không an toàn. Không retry provider sau 429 trong test window. Quay lại cặp IPA/RPK known-good có version và SHA-256 đã ghi, clean-install rồi kết nối lại khi đang đứng yên.

## Kết quả cần phản hồi

Trả về đúng một trạng thái `PASS-HW`, `FAIL-HW`, `BLOCKED-ENV` hoặc `NEEDS-MEASURE`; kèm bước lỗi đầu tiên, iOS/firmware thực tế, provider-call count và screenshot/chẩn đoán đã redaction. Không gửi AuthKey, Vietmap key, CoreBluetooth UUID, raw capture hoặc signing material.

## Giới hạn xác nhận

Linux đã kiểm tra package/RPK/protocol-lab và build RPK. XCTest iOS, IPA build và hành vi Xiaomi Smart Band 10 thực tế vẫn cần macOS CI cùng owner hardware acceptance; file RPK và digest chỉ chứng minh identity artifact.
```

- [ ] **Step 2: Make the handoff mandatory for every POC**

In `docs/testing/hardware-acceptance.md`, add a `### Developer handoff bundle` section immediately after `### Required test packet` and before the tester status definitions:

```markdown
### Developer handoff bundle

Every POC ends with both:

- a committed record at `docs/testing/handoffs/<poc>-<short-commit>.md`; and
- an ignored local bundle at `artifacts/<poc>/<short-commit>/` containing `HANDOFF.md`, `SHA256SUMS` and every IPA/RPK that actually exists.

The handoff summarizes completed work, lists numbered owner test steps and reports the exact path, size and SHA-256 of each available IPA/RPK. A missing artifact must be written as `Không có` with its build boundary; a nonexistent path or fabricated hash is forbidden. Run `scripts/prepare-poc-handoff.sh` to create the local bundle. The bundle identifies artifacts but never upgrades automated evidence to `PASS-HW`.
```

- [ ] **Step 3: Validate the record against source metadata and artifact evidence**

Run:

```bash
test "$(git show 5e7ff51:apps/band/src/manifest.json | sed -n 's/.*"versionName": "\([^"]*\)".*/\1/p')" = '0.2.0'
test "$(git show 5e7ff51:apps/ios/project.yml | awk '/MARKETING_VERSION:/ {print $2; exit}')" = '0.1.0'
test "$(stat -c '%s' apps/band/dist/dev.lordierclaw.bluebandmap.band.debug.0.2.0.rpk)" = '18485'
echo '7acf4ff4e5ae56e612f44d07ff7c8bd0f7015a74b9458927cdf11668d8dfdaae  apps/band/dist/dev.lordierclaw.bluebandmap.band.debug.0.2.0.rpk' | sha256sum -c -
rg -n 'Không có|artifacts/m1/5e7ff51|docs/testing/results/2026-08-29-m1-test-packet.md' docs/testing/handoffs/m1-5e7ff51.md
git diff --check
```

Expected: metadata and artifact assertions pass; the record includes explicit missing-IPA status, fixed RPK path and authoritative packet link.

- [ ] **Step 4: Commit the durable handoff record**

```bash
git add docs/testing/handoffs/m1-5e7ff51.md docs/testing/hardware-acceptance.md
git commit -m "docs: add M1 developer handoff"
```

## Task 3: Generate and verify the fixed M1 artifact bundle

**Files:**
- Generate, ignored: `artifacts/m1/5e7ff51/HANDOFF.md`
- Generate, ignored: `artifacts/m1/5e7ff51/SHA256SUMS`
- Generate, ignored: `artifacts/m1/5e7ff51/dev.lordierclaw.bluebandmap.band.debug.0.2.0.rpk`

- [ ] **Step 1: Rebuild and verify the real RPK through the canonical target**

Run:

```bash
make test-rpk
test -s apps/band/dist/dev.lordierclaw.bluebandmap.band.debug.0.2.0.rpk
sha256sum apps/band/dist/dev.lordierclaw.bluebandmap.band.debug.0.2.0.rpk
```

Expected: all 42 Band tests and real RPK verification pass. The digest must equal `7acf4ff4e5ae56e612f44d07ff7c8bd0f7015a74b9458927cdf11668d8dfdaae`; if reproducible output differs, stop and investigate rather than modifying the committed record to hide drift.

- [ ] **Step 2: Package the M1 handoff**

Run:

```bash
scripts/prepare-poc-handoff.sh \
  --poc m1 \
  --commit 5e7ff511b0b51e7ca3cbf8514217bc1ccbb5f6f8 \
  --handoff docs/testing/handoffs/m1-5e7ff51.md \
  --rpk apps/band/dist/dev.lordierclaw.bluebandmap.band.debug.0.2.0.rpk
```

Expected output includes:

```text
bundle=artifacts/m1/5e7ff51
artifact=dev.lordierclaw.bluebandmap.band.debug.0.2.0.rpk bytes=18485 sha256=7acf4ff4e5ae56e612f44d07ff7c8bd0f7015a74b9458927cdf11668d8dfdaae
```

- [ ] **Step 3: Independently verify final bundle identity and Git isolation**

Run:

```bash
test -f artifacts/m1/5e7ff51/HANDOFF.md
test -f artifacts/m1/5e7ff51/SHA256SUMS
test ! -e artifacts/m1/5e7ff51/BlueBandMap-unsigned.ipa
cmp -s docs/testing/handoffs/m1-5e7ff51.md artifacts/m1/5e7ff51/HANDOFF.md
(cd artifacts/m1/5e7ff51 && sha256sum -c SHA256SUMS)
test "$(stat -c '%s' artifacts/m1/5e7ff51/dev.lordierclaw.bluebandmap.band.debug.0.2.0.rpk)" = '18485'
git check-ignore -q artifacts/m1/5e7ff51/dev.lordierclaw.bluebandmap.band.debug.0.2.0.rpk
test -z "$(git status --short)"
```

Expected: all assertions pass; the bundle has one RPK and no IPA; ignored artifacts do not dirty the worktree.

## Task 4: Final review and canonical verification

**Files:**
- Review all files changed by Tasks 1–3.

- [ ] **Step 1: Run the full project checks**

Run exactly:

```bash
make test
make lint
git diff --check
```

Expected: 124 portable Swift tests, 42 Band tests, 19 protocol-lab tests, iOS metadata, handoff packaging tests, shell syntax, secret checks and diff checks all pass. Existing legacy Vela npm audit warnings remain recorded and are not force-upgraded in this workflow.

- [ ] **Step 2: Audit the final handoff requirement by evidence**

Run:

```bash
git status --short
git log -4 --oneline
find artifacts/m1/5e7ff51 -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort
(cd artifacts/m1/5e7ff51 && sha256sum -c SHA256SUMS)
scripts/verify-no-secrets.sh
```

Expected:

```text
HANDOFF.md
SHA256SUMS
dev.lordierclaw.bluebandmap.band.debug.0.2.0.rpk
```

The worktree is clean, no IPA is claimed, the RPK checksum passes, and no tracked artifact or secret path exists.

- [ ] **Step 3: Request final code review**

Review the implementation range from commit `998747680fc6254bf5cb43e1ba2ca39a7cf65660` to final `HEAD` against `docs/superpowers/specs/2026-08-30-poc-handoff-artifacts-design.md`. Critical and Important findings must be fixed and reverified before handoff.

- [ ] **Step 4: Deliver the user-facing M1 handoff**

The final response includes:

- summary of M1 work;
- concise numbered hardware test steps and link to the full packet;
- exact RPK path and SHA-256;
- explicit `IPA: Không có` with the macOS CI reason;
- verification counts and the limitation that M1 is not hardware-confirmed.

## Plan self-review

- **Spec coverage:** Tasks cover the fixed commit-specific directory, immutable atomic packaging, explicit IPA/RPK inputs, deterministic hashes, committed history, missing-artifact reporting, M1 initial bundle, security exclusions, behavioral tests and future POC definition of done.
- **Placeholder scan:** Angle-bracket tokens occur only in documented command syntax and path patterns, not as unfinished implementation values. The M1 record contains concrete commit, versions, RPK path, byte count, digest, test packet and missing-IPA reason.
- **Type/name consistency:** The script name, CLI flags, `artifacts/<poc>/<short-commit>/` destination, `HANDOFF.md`, `SHA256SUMS`, committed handoff path and Make target use one spelling throughout.
- **Scope:** This plan changes handoff packaging and documentation only. It does not build an IPA on Linux, alter M1 runtime behavior, change Xiaomi bytes, upload artifacts, add signing material or start M2.
