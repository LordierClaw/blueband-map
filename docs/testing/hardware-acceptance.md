# Hardware acceptance: Xiaomi Smart Band 10

Automated tests do not constitute hardware acceptance. Record only versions, artifact hashes, pass/fail stages, and sanitized error categories—never AuthKeys or device identifiers.

Status: **not yet executed for this new foundation**.

| Stage | Expected result | Result |
|---|---|---|
| Verify IPA/RPK SHA-256 | Matches workflow `SHA256SUMS` | Not run |
| Install unsigned iOS app | Launches under free Apple ID provisioning | Not run |
| Clean-install RPK | Shows `RPK 0.1.0` | Not run |
| Foreground scan | Band 10 is selectable | Not run |
| FE95/5E/5F discovery | SPP configuration succeeds | Not run |
| Auth and proof | Model, firmware, battery populated | Not run |
| RPK handshake | State becomes `applicationReady` | Not run |
| iOS → band echo | Band renders once and ACKs | Not run |
| Band → iOS echo | iOS renders once and ACKs | Not run |
| Duplicate delivery | ACK twice, render once | Not run |
| Disconnect | Offline status/cleanup; BLE closes | Not run |
| Changed fingerprint | Rejected until deliberate reset | Not run |
| Resume Mi Fitness | Normal ownership resumes after disconnect | Not run |

Test with the supported matrix only: one iPhone running iOS 17 or later, one Xiaomi Smart Band 10 on the documented firmware, the exact IPA/RPK hashes, and Mi Fitness closed during the direct session.
