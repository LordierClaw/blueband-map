# Application envelope v1

Message:

```json
{"v":1,"id":"i-a1b2c3","src":"ios","type":"message","topic":"system.echo","body":{"text":"PING"}}
```

Acknowledgement:

```json
{"v":1,"id":"i-a1b2c3","src":"band","type":"ack"}
```

Contract:

- Encoded UTF-8 JSON is at most 512 bytes; `v` is exactly integer `1`.
- `id` is 1–32 printable ASCII bytes.
- `src` is `ios` or `band`; receivers accept only the opposite source.
- `type` is `message` or `ack`.
- A message has a lowercase dotted ASCII topic of 1–64 bytes and a JSON object body.
- An ACK reuses the message ID and omits topic and body.
- Every valid incoming message is ACKed, including duplicates.
- Duplicate content is emitted once; the newest 64 incoming IDs are retained per session.
- A caller that waits for delivery retries the exact same command and message ID once after one second without an ACK. The retry gets a final three-second ACK window; duplicate IDs are ACKed without applying the message twice.
- A caller that does not wait for delivery keeps the original five-second failure window and does not retry.

`system.echo` is the only registered sample topic.
