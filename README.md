# BlueBand Map

BlueBand Map is a Linux-first foundation for direct communication between a custom iPhone app and a custom Xiaomi Smart Band 10 Vela RPK.

The Xiaomi BLE v2, SPP v2, authentication, encrypted command, ThirdPartyApp, and `system.interconnect` path is derived from the hardware-confirmed [BlueBand POC handover](https://github.com/LordierClaw/blueband-ios/blob/main/BASE_FROM_THIS_PROJECT.md). This is an independent, unofficial Xiaomi protocol implementation—not an official Xiaomi iOS SDK.

## Scope

- Xiaomi Smart Band 10 only.
- Foreground BLE and explicit disconnect.
- One iPhone companion and `dev.lordierclaw.bluebandmap.band` RPK.
- Versioned, acknowledged application messages.
- No AuthKey extraction, cloud service, background BLE, or Mi Fitness replacement.

## Development

Ubuntu and Docker are the canonical local environment:

```bash
make doctor
make bootstrap
make test
```

Portable Swift, RPK, and protocol-lab checks run locally. Public GitHub Actions provides the Apple-only Xcode boundary and produces an unsigned IPA for free Apple ID sideloading.

Never commit an AuthKey, raw capture, Apple credential, provisioning profile, or private RPK signing key. See [SECURITY.md](SECURITY.md).

## Design

- [Approved foundation design](docs/superpowers/specs/2026-08-29-blueband-map-foundation-design.md)
- [Implementation plan](docs/superpowers/plans/2026-08-29-blueband-map-foundation.md)

Licensed under Apache-2.0.
