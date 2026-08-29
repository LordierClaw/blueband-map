# Fixture redaction

Only the smallest packet needed to reproduce byte behavior may become a fixture.

1. Work with raw evidence under ignored `captures/raw/`.
2. Decode locally with `tools/protocol-lab`; pass secrets via standard input only.
3. Replace AuthKeys, nonces, session keys, serials, UUIDs, MAC-like identifiers, names, and account data.
4. Re-encrypt synthetic payloads using documented synthetic keys when ciphertext behavior matters.
5. Add the real secret byte sequence to the local denylist and run the redaction gate.
6. Review the final diff and run `make lint` before commit.

Never weaken a fixture assertion merely to make redaction easier. Preserve structural lengths, field numbers, byte order, and independently verifiable checksums.
