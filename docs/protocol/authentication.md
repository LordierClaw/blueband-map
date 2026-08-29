# Xiaomi authentication

The user supplies a 16-byte AuthKey as exactly 32 hexadecimal characters. It is stored with Keychain accessibility `WhenUnlockedThisDeviceOnly` and never logged.

1. iOS sends a fresh 16-byte phone nonce in command type/subtype `1/26`.
2. Band returns a 16-byte watch nonce and 32-byte HMAC.
3. `PRK = HMAC-SHA256(message: AuthKey, key: phoneNonce || watchNonce)`.
4. HKDF-expand with info `miwear-auth` produces 64 bytes. Bytes `0..<16` are decrypt key, `16..<32` encrypt key, `32..<36` decrypt nonce, and `36..<40` encrypt nonce.
5. Watch proof is constant-time compared with `HMAC-SHA256(watchNonce || phoneNonce, decryptKey)`.
6. iOS proof is `HMAC-SHA256(phoneNonce || watchNonce, encryptKey)`.
7. Device information is AES-128-CCM encrypted with nonce `encryptNonce || eight zero bytes` and a four-byte tag, then sent in subtype `27`.
8. Post-authentication protobuf commands use the Xiaomi AES-128-CTR rule with the 16-byte session key as initial counter.

CommonCrypto supplies the production AES block primitive. Portable composition and independent test vectors run on Linux.
