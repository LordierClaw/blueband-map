# macOS options under a zero-cost constraint

BlueBandMap does not require an owned, rented, or paid remote Mac for routine development. Portable Swift, protocol, state-machine, RPK, archive, and inspection work runs locally on Ubuntu. Standard GitHub-hosted macOS runners are the supported Apple compilation boundary for this public repository.

Apple's macOS software license permits virtualized macOS instances only on Apple-branded hardware. A KVM/Hackintosh guest on this Ubuntu PC is therefore outside the supported design, legally unsuitable for the project, fragile across updates, and not used for build acceleration. See [Apple Software License Agreements](https://www.apple.com/legal/sla/).

Paid hosted Macs are intentionally excluded. Public repositories can use standard GitHub-hosted runners without consuming paid Actions minutes; storage and policy limits still apply. See [GitHub Actions billing](https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-actions/about-billing-for-github-actions).

To keep macOS time small, Linux runs the broad suites first, iOS CI is path-filtered, Swift and npm inputs are locked, XcodeGen is checksum-pinned, and Apple CI only performs package/CommonCrypto tests, simulator tests, and one unsigned arm64 build.
