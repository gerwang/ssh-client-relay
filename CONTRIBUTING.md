# Contributing

Bug reports and focused pull requests are welcome.

## Before Reporting A Bug

Test the outer client-to-relay connection, the relay-to-target connection, and
the wrapper separately as described in the README troubleshooting section.
Include the client OS, OpenSSH version, relay OS, wrapper version, exact command
shape, and the smallest relevant error output.

Remove production usernames, hostnames, addresses, paths, keys, tokens,
ControlMaster socket names, and captured session contents. Suspected security
issues belong in a private vulnerability report rather than a public issue; see
[SECURITY.md](SECURITY.md).

## Development

Keep protocol and routing changes compatible across the Linux client, Windows
client, and relay helper. If the protocol must change, update both clients and
the helper together.

Run the Linux suite with:

```bash
tests/test-linux.sh
```

Run the Windows suite from Windows PowerShell with:

```powershell
tests\test-windows.ps1
```

Add fake-transport regression coverage for behavior changes. Tests must not
depend on production infrastructure, credentials, MFA, or external services.
