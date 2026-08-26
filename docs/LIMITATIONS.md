# Known Limitations

## Destination Detection

The current clients identify a relayed request by scanning arguments for an
exact match with the configured target alias or hostname. They do not implement
a complete OpenSSH command-line parser.

Consequences:

- A remote command argument equal to the target name can trigger relay mode.
- Every matching argument is rewritten, not only the destination operand.
- Unusual option ordering and future OpenSSH options may be interpreted
  incorrectly.

Use the wrapper with conventional OpenSSH invocations where the target appears
once as the destination.

## Forwarding

Dynamic forwarding (`-D PORT` and `-DPORT`) is bridged back to the client and is
tested for VS Code Remote SSH.

The following are not translated between inner and outer SSH semantics:

- Local forwarding with `-L`
- Remote forwarding with `-R`
- Stdio forwarding with `-W`
- Unix-domain socket forwarding
- Forwarding options supplied indirectly through complex `-o` values

They may bind on the relay rather than the client or otherwise behave
differently from direct SSH.

## Platform Coverage

The tested clients are Bash-based Linux and Windows PowerShell/.NET Framework.
The relay must be Linux with Bash and OpenSSH. macOS, BSD, non-Bash relays, and
Windows relays are unsupported.

Linux SSHFS support additionally requires Perl to handle nonblocking binary
stdin correctly.

## Installation And Upgrades

The Windows installer cannot replace `ssh-client-relay.exe` while VS Code or
another process has it open. Close relay users before upgrading.

Installers overwrite generated configuration and installed binaries. They do
not provide package-manager integration, rollback, or automatic migration.

Custom helper locations are limited to simple paths relative to the relay
user's home directory. Paths containing whitespace, shell metacharacters,
traversal components, or absolute paths are intentionally unsupported.

The client and helper use a fixed protocol marker but do not negotiate versions.
Upgrade both sides together.

## Session Lifecycle

Abrupt client termination, relay failure, or network partitions can leave inner
SSH sessions until keepalive or server timeout processing closes them. A live
ControlMaster socket does not guarantee that the target accepts new channels.
Test a real session when checking health.

The target SSH server may limit multiplexed sessions through `MaxSessions`.
VS Code windows, terminals, and SSHFS mounts each consume channels.

## Performance

Traffic is processed by two SSH transports. The measured interactive overhead
was small, while bulk download throughput was lower. See
[`BENCHMARKS.md`](../BENCHMARKS.md) for the tested topology and limitations.

## Test Scope

CI tests argument routing, framing, BOM compatibility, dynamic-forward bridges,
direct fallback, SSHFS injection, version output, and Windows compilation using
fake local transports.

CI does not test a live SSH server, MFA, ControlMaster behavior, real port
forwarding, SSHFS/FUSE mounts, network interruption, or relay reboot recovery.
The maintainers additionally exercise Linux and Windows clients against a live
Linux relay, but those private deployment checks are not reproducible in CI.
