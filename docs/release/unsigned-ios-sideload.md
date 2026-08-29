# Unsigned iOS sideload with a free Apple ID

The release workflow emits an **unsigned** IPA. It never asks for an Apple password, certificate, provisioning profile, AuthKey, or signing secret.

1. Download the artifact and verify `SHA256SUMS` before extracting it.
2. Confirm `release-manifest.json` versions and commit match the intended run.
3. Use [Sideloadly](https://sideloadly.io/) on a trusted supported computer to sign the IPA locally with your own free Apple ID. Do not upload the Xiaomi AuthKey to any signing service.
4. Connect the iPhone, install, enable Developer Mode if iOS requests it, and trust the developer identity in Settings.
5. Free provisioning commonly expires after seven days; re-sign and reinstall when it expires. Apple policy can change, so confirm the current limit in the signing tool and Apple documentation.
6. Install the verified RPK separately. For upgrades, uninstall the old RPK first and confirm `RPK 0.1.0` on screen.

After installation, close Mi Fitness, run the [hardware acceptance matrix](../testing/hardware-acceptance.md), explicitly disconnect BlueBandMap, then confirm Mi Fitness can resume. The IPA's lack of embedded signature/provisioning is checked before publication; local signing necessarily changes the installed app artifact.
