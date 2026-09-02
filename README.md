# BlueBand Map

BlueBand Map is a Linux-first foundation for direct communication between a custom iPhone app and a custom Xiaomi Smart Band 10 Vela RPK.

The Xiaomi BLE v2, SPP v2, authentication, encrypted command, ThirdPartyApp, and `system.interconnect` path is derived from the hardware-confirmed [BlueBand POC handover](https://github.com/LordierClaw/blueband-ios/blob/main/BASE_FROM_THIS_PROJECT.md). This is an independent, unofficial Xiaomi protocol implementation—not an official Xiaomi iOS SDK.

## Scope

- Xiaomi Smart Band 10 only.
- Foreground BLE and explicit disconnect.
- One iPhone companion and `dev.lordierclaw.bluebandmap.band` RPK.
- Versioned, acknowledged application messages.
- Foreground Vietmap Route v4 navigation rendered by the pinned Vietmap iOS Map SDK as a full-screen 212×520 indexed PNG.
- No AuthKey extraction, cloud service, automatic background reconnect, or Mi Fitness replacement.

## Development

Ubuntu and Docker are the canonical local environment:

```bash
make doctor
make bootstrap
make test
```

Portable Swift, RPK, and protocol-lab checks run locally. Public GitHub Actions provides the Apple-only Xcode boundary and produces an unsigned IPA for free Apple ID sideloading.

Never commit an AuthKey, raw capture, Apple credential, provisioning profile, or private RPK signing key. See [SECURITY.md](SECURITY.md).

Focused commands:

```bash
make test-swift
make test-rpk
make test-lab
make test-ios-metadata
make lint
```

The repository intentionally does not support macOS virtualization on non-Apple hardware or paid hosted Macs. See [macOS options](docs/development/macos-options.md).

## Engineering handbook

- [Product overview and POC roadmap](docs/product/overview.md)
- [Map/navigation feasibility review](docs/research/map-navigation-feasibility.md)
- [Architecture overview](docs/architecture/overview.md)
- [Module boundaries](docs/architecture/module-boundaries.md)
- [Runtime state machine](docs/architecture/runtime-state-machine.md)
- [Xiaomi SPP v2](docs/protocol/xiaomi-spp-v2.md)
- [Authentication](docs/protocol/authentication.md)
- [ThirdPartyApp bridge](docs/protocol/third-party-app.md)
- [Application envelope v1](docs/protocol/application-envelope-v1.md)
- [Snapshot route-map protocol](docs/protocol/snapshot-route-map-v1.md)
- [Threat model](docs/security/threat-model.md)
- [Ubuntu setup](docs/development/ubuntu-setup.md)
- [Unsigned free-Apple-ID sideload](docs/release/unsigned-ios-sideload.md)
- [Band 10 hardware acceptance](docs/testing/hardware-acceptance.md)

## Design records

- [Approved foundation design](docs/superpowers/specs/2026-08-29-blueband-map-foundation-design.md)
- [Approved risk-first map/navigation POC design](docs/superpowers/specs/2026-08-29-blueband-map-poc-roadmap-design.md)
- [Implementation plan](docs/superpowers/plans/2026-08-29-blueband-map-foundation.md)
- [Architecture decisions](docs/adr/)

Licensed under Apache-2.0.
