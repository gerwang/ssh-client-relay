# Security Policy

## Supported Versions

Security fixes are provided for the latest tagged release.

| Version | Supported |
|---|---|
| 0.1.x | Yes |
| Unreleased older revisions | No |

## Reporting A Vulnerability

Do not open a public issue for a suspected vulnerability or include production
credentials, hostnames, logs, or captured SSH traffic in an issue.

Use the repository's GitHub **Security** tab to submit a private vulnerability
report. Include:

- A concise description and impact
- Affected client platform and version
- Reproduction steps using non-production systems
- Relevant configuration with secrets and identities removed
- Any proposed mitigation

Reports will be acknowledged as soon as practical. Confirmed issues will be
fixed on the private security advisory branch before coordinated disclosure.

## Scope

Security reports may cover argument injection, protocol parsing, unsafe process
handling, forwarding exposure, configuration permissions, installer behavior,
or unintended credential disclosure.

The relay is intentionally a fully trusted machine and can observe target
session contents. Reports based solely on a malicious or compromised relay
observing those contents are outside the project's security guarantees. See
[`docs/SECURITY_MODEL.md`](docs/SECURITY_MODEL.md).
