# Xiaomi BLE and SPP v2

Band 10 endpoints:

- Service: `0000FE95-0000-1000-8000-00805F9B34FB`
- Notify: `0000005E-0000-1000-8000-00805F9B34FB`
- Write: `0000005F-0000-1000-8000-00805F9B34FB`

Scanning is foreground-only and intentionally unfiltered; a selected device is accepted only after FE95 and both characteristics are discovered.

An SPP frame is `A5 A5`, packet type/flags, sequence, little-endian payload length, little-endian CRC-16/ARC, then payload. Only the low type nibble is interpreted: `1` ACK, `2` session configuration, `3` data. CRC covers payload only. Incoming data is transport-ACKed using its sequence. Fragmented and coalesced notifications are reassembled with bounded resynchronization.

The literal session request payload is:

```text
01 01 03 00 01 00 00 02 02 00 00 FC 03 02 00 20 00 04 02 00 10 27
```

A data payload starts with masked channel then opcode. BlueBandMap uses channel `1`; plaintext command opcode is `1`, authenticated encrypted command opcode is `2`.
