# ADR 0006: Application envelope version 1

- Status: Accepted
- Date: 2026-08-29

## Decision

Use the bounded topic-based JSON contract in `docs/protocol/application-envelope-v1.md`, including ACK correlation, 64-ID deduplication, five-second failure, and no retry.

## Consequences

Future features add topic handlers without changing Xiaomi framing. Breaking envelope changes require a new explicit version.
