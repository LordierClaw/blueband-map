# ADR 0002: Linux-first toolchains

- Status: Accepted
- Date: 2026-08-29

## Decision

Dockerized Swift 6.3.3 and Node 20.19.5 on Ubuntu are canonical. Standard public GitHub-hosted macOS runners provide the Apple-only boundary.

## Consequences

Routine feedback is local and free. Apple compilation is asynchronous and must remain narrow, path-filtered, and reproducible.
