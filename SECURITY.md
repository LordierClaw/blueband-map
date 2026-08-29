# Security Policy

Do not report vulnerabilities that include an AuthKey, private signing key, Apple credential, provisioning profile, raw packet capture, or unredacted device identifier in a public issue.

Use GitHub's private vulnerability reporting feature when it is available for this repository. Otherwise contact the repository owner privately and provide only the minimum sanitized reproduction material.

If a secret was committed, treat it as compromised, rotate or replace it where possible, remove it from future artifacts, and document the incident without reproducing the secret.
