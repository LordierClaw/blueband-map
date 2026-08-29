# Secrets and logging

Never commit or print AuthKeys, phone/watch nonces, derived keys, Apple passwords, app-specific passwords, signing keys, provisioning profiles, private RPK keys, full device identifiers, or raw captures.

The iOS UI converts errors to fixed boundary-safe messages. Production RPK logging is off. The protocol lab accepts secrets only through standard input and refuses command-line secret arguments. Repository and CI secret scanners are mandatory.

Allowed diagnostics are stage names, typed error categories, redacted identifiers, dependency versions, artifact hashes, and pass/fail outcomes. If exposure occurs, stop sharing the artifact, assume the value is compromised, rotate where possible, and sanitize history only with coordinated repository-owner action.
