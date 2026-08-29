# ADR 0005: CommonCrypto production AES provider

- Status: Accepted
- Date: 2026-08-29

## Decision

Keep CTR/CCM composition portable behind `AESBlockCipher`; use CommonCrypto for the iOS production AES-128 block operation. CryptoSwift is test-only.

## Consequences

Linux validates composition with independent vectors while Apple CI validates the production boundary. Runtime code does not gain a second AES implementation.
