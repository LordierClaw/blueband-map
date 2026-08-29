# Repository Instructions

- Treat `/home/hainn/blue/code/blueband-ios` as a read-only protocol baseline.
- Run canonical commands through `make`; do not rely on the host's native Node version.
- Run `make test` and `git diff --check` before claiming a change works.
- Never commit AuthKeys, raw captures, Apple credentials, provisioning profiles, private signing keys, `.env` files, dependency directories, or generated Xcode projects.
- Add a failing behavioral test before implementation changes.
- Preserve verified Xiaomi bytes. A wire change requires exact independent vectors, an ADR, and identified hardware acceptance cases.
- Do not claim hardware support from compilation, simulator, or deterministic tests alone.
