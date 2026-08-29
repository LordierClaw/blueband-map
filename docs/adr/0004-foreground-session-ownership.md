# ADR 0004: Foreground-only session ownership

- Status: Accepted
- Date: 2026-08-29

## Decision

BlueBandMap owns Xiaomi's proprietary session only while foregrounded and provides explicit disconnect. No `UIBackgroundModes` entitlement is present.

## Consequences

The lifecycle is simpler and conflicts with Mi Fitness are visible. Background reconnect and monitoring are out of scope.
