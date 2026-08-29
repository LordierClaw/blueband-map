# Runtime state machine

The visible state sequence is:

```text
idle → scanning → connecting → discoveringGatt → configuringSpp
     → authenticating → readingDeviceProof → waitingForRpk
     → applicationReady → disconnecting → idle
```

Authentication success alone is not presented as a usable connection. Device information and battery responses must first prove the encrypted command path. `applicationReady` requires a valid expected-package ThirdPartyApp status request and successful TOFU continuity check.

One reconnect is permitted only after the first watch-HMAC mismatch. Other failures close the active transport and return to `idle`. Explicit disconnect cancels receiver and delivery tasks, best-effort sends offline status, clears keys and session deduplication state, closes BLE, then returns to `idle`.
