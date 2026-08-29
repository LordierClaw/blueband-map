# Optional protocol forensics

The rooted Android capture path is no longer a prerequisite or part of the runtime. The implemented iPhone/RPK bridge uses the published Xiaomi Vela interconnect contract and independently tested `ThirdpartyApp` protobuf mapping documented in `REFERENCES.md` and the design spec.

Use `protocol-lab` only if a future Band 10 firmware rejects an otherwise valid type-20 packet. Keep AuthKeys, nonces, session keys, HMACs, BLE captures, device identifiers, Xiaomi tokens, and private signing material under ignored local directories. Never upload them to GitHub or Actions.

The safe local decoder workflow remains:

```powershell
Push-Location .\protocol-lab
npm ci
npm test
Pop-Location
```

A captured battery response should be the positive control before interpreting interconnect traffic. Sanitize fixtures according to `protocol-lab/fixtures/README.md`; Android is removed again after the forensic session and is never a relay between iPhone and band.
