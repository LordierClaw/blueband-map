# Contributing

1. Read the approved design and relevant architecture decisions.
2. Run `make doctor`, then `make test` before opening a pull request.
3. Add a failing behavioral test before changing implementation.
4. Keep protocol changes byte-exact and attach independent vectors.
5. Never include an AuthKey, raw device capture, device identifier, signing key, or Apple credential.
6. State which hardware acceptance cases must be repeated for hardware-facing changes.

Use focused commits. Generated Xcode projects, dependency directories, and build artifacts are not committed.
