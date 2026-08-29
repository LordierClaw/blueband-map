# ThirdPartyApp bridge

The authenticated Xiaomi command envelope uses type `20` and body field `22`.

- Subtype `6`: RPK status request. Body field `5` contains basic identity.
- Subtype `7`: phone status reply. Body field `8` contains identity and status `1` connected or `2` disconnected.
- Subtype `8`: phone-to-wear message. Body field `9` contains identity field `1` and content field `2`.
- Subtype `9`: wear-to-phone message with the same identity/content shape.

Basic identity contains UTF-8 package field `1` and non-empty fingerprint bytes field `2`. The only accepted package is `dev.lordierclaw.bluebandmap.band`. Content is an application-envelope-v1 UTF-8 JSON document.

Package pinning routes the expected app. The full fingerprint is then enrolled or checked according to [TOFU policy](../security/threat-model.md).
