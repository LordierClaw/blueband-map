# POC Handoff and Artifact Packaging Design

## Status

Approved in conversation on 2026-08-30. This design standardizes the final developer handoff for M1 and every later POC. It does not change the hardware-acceptance meaning of `PASS-HW`.

## Goal

At the end of every POC, the project owner receives one concise handoff that answers three questions without searching build directories:

1. What changed and what remains unproven?
2. What exact steps must be run on the target hardware?
3. Where are the corresponding IPA and RPK files, if those artifacts exist?

The handoff must never invent an artifact path, digest, build result, hardware result or provider result.

## Required outputs

Each POC handoff has two representations.

### Local artifact bundle

Generated binaries live under:

```text
artifacts/<poc>/<short-commit>/
```

For example:

```text
artifacts/m1/5e7ff51/
├── HANDOFF.md
├── SHA256SUMS
├── BlueBandMap-unsigned.ipa          # only when available
└── dev.lordierclaw.bluebandmap.rpk  # only when available
```

`artifacts/` is ignored by Git. A commit-specific directory is immutable: the packaging command refuses to overwrite an existing bundle. A changed build or feedback revision receives a new commit and therefore a new directory.

`SHA256SUMS` lists every IPA or RPK actually copied into the bundle. It is present even when no binary exists, in which case it is empty and `HANDOFF.md` explains why each expected artifact is unavailable.

### Committed handoff record

The durable project record lives under:

```text
docs/testing/handoffs/<poc>-<short-commit>.md
```

It contains the same user-facing summary and test procedure, plus repository-relative local artifact paths. Binary files are never committed. A missing artifact is written as `Không có`, followed by the concrete reason and the command or CI boundary needed to create it.

## Handoff content contract

Every `HANDOFF.md` and committed handoff record contains these sections in this order:

1. **Identity** — POC name, full Git commit, short build ID, declared iOS/RPK versions and generation timestamp.
2. **Tóm tắt đã làm** — core behavior implemented, important reliability/security work and deliberate out-of-scope items.
3. **Artifact bàn giao** — path, version, byte size and SHA-256 for every existing IPA/RPK; explicit absence and reason otherwise.
4. **Điều kiện trước khi test** — target device/OS/firmware recording, Mi Fitness state, masked configuration health and API-call budget.
5. **Các bước test** — numbered owner actions with an observable expected result for each step.
6. **Điều kiện dừng và phục hồi** — rate limit, corruption, crash, secret exposure, unsafe interaction and previous known-good recovery.
7. **Kết quả cần phản hồi** — `PASS-HW`, `FAIL-HW`, `BLOCKED-ENV` or `NEEDS-MEASURE`, first failed step and redacted evidence.
8. **Giới hạn xác nhận** — automated/Linux/CI evidence is separated from owner hardware evidence.

The detailed POC test packet remains authoritative when it exists. The handoff links to it and may provide a shorter execution checklist, but must not contradict or silently omit its call budgets, stop conditions or required evidence.

## Packaging command

A repository script packages a handoff from explicit inputs. Its interface is:

```text
scripts/prepare-poc-handoff.sh \
  --poc <name> \
  --commit <git-revision> \
  --handoff <committed-markdown-path> \
  [--ipa <ipa-path>] \
  [--rpk <rpk-path>]
```

The script:

- resolves and records the full and short commit;
- requires a clean, tracked handoff document;
- accepts only explicit regular, non-symlink, non-empty `.ipa` and `.rpk` inputs;
- copies through a temporary directory, computes SHA-256 after copying and then publishes the final directory atomically;
- copies the committed record as local `HANDOFF.md`;
- refuses an existing destination instead of overwriting evidence;
- logs paths, sizes and hashes but never file contents, keys, UUIDs, signing material or environment values.

The command may package only the RPK when no IPA exists, or only the IPA when no RPK exists. Artifact absence must already be explained in the handoff document.

## M1 initial handoff

The first bundle uses commit `5e7ff511b0b51e7ca3cbf8514217bc1ccbb5f6f8` and POC `m1`.

- The Linux-built debug RPK currently exists at `apps/band/dist/dev.lordierclaw.bluebandmap.band.debug.0.2.0.rpk` and is eligible for the local M1 bundle after verification.
- No IPA currently exists. Ubuntu cannot run the Apple build boundary; the handoff records `Không có` and points to the macOS CI/release workflow needed to produce it.
- The authoritative hardware procedure remains `docs/testing/results/2026-08-29-m1-test-packet.md`.

## Security and repository policy

- `artifacts/` and temporary packaging directories are Git-ignored.
- No AuthKey, Vietmap key, raw BLE capture, peripheral UUID, Apple credential, provisioning profile, private signing key, `.env`, dependency tree or generated Xcode project is copied by the packaging command.
- The committed record may contain hashes, sizes, versions, stable error codes and redacted evidence identifiers only.
- An IPA/RPK hash proves artifact identity, not correct hardware behavior.

## Verification

Behavioral shell tests cover:

- complete RPK-only, IPA-only and dual-artifact bundles;
- exact destination naming and handoff copy;
- deterministic `SHA256SUMS` ordering and hash verification;
- missing, empty, symlinked, wrong-extension and duplicate inputs;
- dirty or untracked handoff rejection;
- existing-destination refusal and temporary-directory cleanup;
- no secret value echoed in output.

Canonical project checks remain `make test`, `make lint` and `git diff --check`. The M1 bundle is additionally verified by recomputing its RPK digest from the final destination.

## Definition of done for every POC

A POC implementation is ready for owner testing only when:

- implementation and canonical checks pass at a named commit;
- the committed handoff record exists;
- the local commit-specific artifact bundle exists;
- every available IPA/RPK has a verified path and SHA-256;
- every unavailable artifact is explicitly identified with its build boundary;
- the owner test steps and expected feedback are included;
- the status is no stronger than the available automated, CI and hardware evidence.
