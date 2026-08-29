# ADR 0007: TOFU RPK fingerprint continuity

- Status: Accepted
- Date: 2026-08-29

## Decision

Pin the exact RPK package and enroll its full fingerprint on first valid handshake. Later handshakes compare in constant time. Trust reset is explicit and stored separately from AuthKey and remembered-band data.

## Consequences

Unexpected replacement is detected after enrollment. First-use authenticity and certificate-chain validation are not provided.
