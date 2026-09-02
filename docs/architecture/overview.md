# Architecture overview

BlueBandMap is a Linux-first monorepo with three runtime layers and one investigation tool:

```text
SwiftUI iPhone app → BlueBandCore → BlueBandProtocol + BlueBandCrypto → CoreBluetooth
                                     ↕ Xiaomi ThirdPartyApp
                              Band 10 Vela RPK
Protocol lab (offline inspection only)
```

`BlueBandProtocol`, crypto composition, session state, the RPK, and the protocol lab are tested on Ubuntu in pinned containers. CoreBluetooth, Security, CommonCrypto, SwiftUI, Xcode project generation, simulator tests, and unsigned device builds run on a standard public GitHub-hosted macOS runner.

The iPhone app owns the proprietary Xiaomi session during an explicit user-started navigation session, including supported iOS background execution. Mi Fitness must not own that session concurrently. Hardware acceptance is separate from automated contract verification.

Application topics include `system.echo`, the bounded `render.*`/`map.asset.*` route-card transfer, and `nav.update`. Product features belong above `BlueBandCore`; they must not modify SPP, authentication, or ThirdPartyApp framing.
