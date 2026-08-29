# Troubleshooting

| Symptom | Check |
|---|---|
| Docker test cannot write cache | Remove only `.ci-cache/` after checking ownership; local Compose normally uses named volumes |
| No BLE devices | Bluetooth permission and powered-on state; scanning intentionally has no name filter |
| FE95/5E/5F missing | Confirm the selected device is Xiaomi Smart Band 10 |
| HMAC mismatch | Re-enter the correct 32-hex AuthKey; the session retries once only |
| Proof timeout | Close Mi Fitness, reconnect, keep both apps foregrounded |
| RPK remains waiting | Open BlueBandMap RPK and press `CHECK CONNECTION` |
| Fingerprint mismatch | Reinstall the known RPK; reset trust only after confirming that change |
| Old RPK UI appears | Uninstall the RPK, reinstall the newly hashed artifact, and confirm displayed version |
| Free sideload expired | Re-sign/reinstall with the same Apple ID workflow |
| Apple CI fails but Linux passes | Read the macOS job first; Linux parse checks cannot type-check Apple frameworks |
