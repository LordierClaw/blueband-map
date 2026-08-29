# Architecture overview

BlueBandMap is a Linux-first monorepo with three runtime layers and one investigation tool:

```text
SwiftUI iPhone app → BlueBandCore → BlueBandProtocol + BlueBandCrypto → CoreBluetooth
                                     ↕ Xiaomi ThirdPartyApp
                              Band 10 Vela RPK
Protocol lab (offline inspection only)
```

`BlueBandProtocol`, crypto composition, session state, the RPK, and the protocol lab are tested on Ubuntu in pinned containers. CoreBluetooth, Security, CommonCrypto, SwiftUI, Xcode project generation, simulator tests, and unsigned device builds run on a standard public GitHub-hosted macOS runner.

The iPhone app owns the proprietary Xiaomi session only while foregrounded. Mi Fitness must not own that session concurrently. Hardware acceptance is separate from automated contract verification.

The only sample application topic is `system.echo`. Product features belong above `BlueBandCore`; they must not modify SPP, authentication, or ThirdPartyApp framing.
