# ADR 0003: No unsupported macOS virtualization

- Status: Accepted
- Date: 2026-08-29

## Decision

Do not build or document a macOS KVM/Hackintosh guest on non-Apple Ubuntu hardware. Do not use paid hosted Macs under the project's zero-cost constraint.

## Consequences

There is no local Xcode execution. Portable coverage is maximized on Linux and public standard GitHub macOS runners compile/test the Apple layer.
