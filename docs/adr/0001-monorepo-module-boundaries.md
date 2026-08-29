# ADR 0001: Monorepo with explicit module boundaries

- Status: Accepted
- Date: 2026-08-29

## Decision

Keep the iOS app, Band RPK, portable Swift packages, protocol lab, CI, and documentation in one repository. Enforce the dependency boundaries in `docs/architecture/module-boundaries.md`.

## Consequences

Protocol and identity changes are reviewed atomically across both peers. The repository is larger, but lockfiles and focused paths keep builds deterministic.
