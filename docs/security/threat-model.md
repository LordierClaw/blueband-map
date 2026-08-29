# Threat model

Protected material includes the Xiaomi AuthKey, Apple credentials, provisioning data, RPK private signing keys, device identifiers, raw captures, and session nonces/keys.

| Threat | Control | Recovery |
|---|---|---|
| Malicious or replaced RPK | Exact package pin plus full-fingerprint TOFU continuity | Disconnect; verify installation; deliberately reset RPK trust |
| First-use attacker | Authenticated band session and explicit user installation reduce exposure | Reinstall known RPK before first enrollment |
| Leaked AuthKey | Device-only Keychain; no logs, CI inputs, or fixtures | Treat key as compromised and replace/re-pair where possible |
| Raw capture disclosure | Raw directory ignored; redaction and denylist gates | Remove public artifact and rotate exposed material |
| Mi Fitness session collision | Foreground-only, explicit ownership copy, cleanup | Disconnect BlueBandMap before resuming Mi Fitness |
| Dependency compromise | Exact crypto/Vela pins, lockfiles, Dependabot review, checksums | Revert pin and rebuild from reviewed revision |
| Public CI leakage | Workflows accept no credentials or AuthKey inputs | Cancel run, delete artifact/log, rotate exposed secret |

TOFU proves continuity after first enrollment. It does **not** validate a certificate chain or establish the publisher's identity independently.
