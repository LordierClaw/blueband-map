# Ubuntu development setup

Ubuntu 26.04 with Docker Engine and Compose v2 is the canonical workstation. No host Swift, Node, Xcode, or Vela toolkit installation is required.

```bash
git clone https://github.com/LordierClaw/blueband-map.git
cd blueband-map
make doctor
make bootstrap
make test
make lint
```

Pinned containers provide Swift 6.3.3 on Noble and Node 20.19.5. `make test-swift`, `make test-rpk`, `make test-lab`, and `make test-ios-metadata` run focused suites. Generated Xcode projects, dependencies, builds, local secrets, raw captures, and signing data are ignored.

Linux validates portable code and builds the real RPK. It cannot compile CoreBluetooth, Security, SwiftUI, or an iPhone app; the public macOS CI job is that boundary.
