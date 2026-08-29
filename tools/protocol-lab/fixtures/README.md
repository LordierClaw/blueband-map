# Sanitized interconnect fixtures

Only reviewed JSON fixtures may be committed here. Raw HCI captures, AuthKeys, session keys, authentication nonces/HMACs, device serials, MAC addresses, Xiaomi account data, signing private keys, and unrelated traffic belong under ignored `protocol-lab/captures/` or `protocol-lab/private/`.

Every accepted fixture has this shape:

```json
{
  "synthetic": false,
  "direction": "phone-to-band",
  "phase": "interconnect-online",
  "commandType": 20,
  "commandSubtype": 7,
  "decryptedPayloadHex": "actual sanitized bytes; never an empty placeholder",
  "decodedFields": [],
  "redactions": ["device identifiers removed"]
}
```

Before committing, run the payload through `redactFixture` with the real AuthKey, derived keys, nonces, and HMACs supplied as local `denylistedHex` values. Review the diff manually after sanitization. A fixture is useful only when the protobuf parser consumes the complete decrypted payload with no trailing bytes and the controlled transcript identifies its semantic fields.

Required accepted fixtures are `interconnect-online.json`, `phone-message.json`, `rpk-echo.json`, and `rpk-ping.json`. Each must come from the deterministic transcript in `../CAPTURE.md`; filenames do not authorize empty placeholders.

Before accepting any of them, decrypt and decode a known battery response from the same BLE session. This positive control proves nonce ordering, packet boundaries, direction, and session-key selection. Record only `battery-positive-control: passed` in the review note—do not commit the battery packet or device value.

Do not anonymize by modifying bytes inside `decryptedPayloadHex`, because that can create a false wire map. Remove an identifying protobuf field entirely, explain it in `redactions`, and confirm the remaining bytes still form a complete message suitable for the asserted field mapping.
