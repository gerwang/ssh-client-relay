# Security Model

## Trust Boundaries

`ssh-client-relay` delegates the final SSH client to a Linux relay:

```text
client -> outer SSH -> trusted relay -> inner SSH -> target
```

The relay is fully trusted. It owns the inner SSH process, target connection,
ControlMaster socket, SSH configuration, and any target credentials available
to that process. It can observe or modify terminal data, file transfers,
forwarded traffic, and commands.

This project does not provide end-to-end confidentiality from the relay. The
outer and inner SSH connections are separate encryption boundaries.

## Authentication

The client authenticates independently to the relay. The relay then
authenticates to the target or reuses a relay-owned ControlMaster. A reusable
target session does not remove the need to secure client-to-relay access.

Recommended controls:

- Use public-key authentication for the relay.
- Disable password login on the relay when practical.
- Restrict relay account access to intended users and devices.
- Protect the relay user's SSH configuration, keys, and ControlMaster sockets.
- Keep the relay patched and monitor its login history.
- Do not share one relay Unix account among mutually untrusted users.

## Helper Protocol

The client sends a version marker, argument count, and NUL-delimited SSH
arguments to a fixed helper over the authenticated outer SSH connection. The
helper reconstructs an argument array and executes `/usr/bin/ssh` without
evaluating the arguments as shell source.

The helper is not a privilege boundary. Anyone who can log into the relay
account can invoke SSH directly with that account's permissions.

The protocol limits requests to 4096 arguments and rejects malformed frames.
The helper accepts an optional UTF-8 byte-order mark emitted by some Windows
.NET Framework stream implementations.

## Configuration

The Linux configuration file is sourced as Bash code. The installer creates it
with mode `0600`; write access to that file is equivalent to code execution as
the client user. Do not use configuration files from untrusted sources.

The Windows configuration is parsed as `KEY=value` records and does not execute
code. Protect it from modification by other users.

## SSHFS

Relayed SSHFS gives the relay the same visibility and authority as the target
SSH client. Filesystem permissions, caching, reconnect behavior, and partial
writes retain normal SSHFS limitations. Do not treat reconnect as transactional
write recovery.

Avoid using SSHFS for concurrently written databases, virtual-machine disks,
container storage, or other lock-sensitive state.

## Forwarding

Dynamic forwarding requested with `-D` is created by the inner SSH client on
the relay and bridged back to the client with an outer `-L` forward. The relay
can observe the destination metadata and plaintext available to the SOCKS
client before any application-layer encryption.

Review the relay and target `AllowTcpForwarding`, `PermitOpen`, and firewall
policies before relying on forwarded ports.

## Secrets

The project does not require target passwords in its repository or generated
configuration. Never commit passwords, private keys, MFA seeds, ControlMaster
sockets, captured protocol streams, or production host details.

GitHub Actions tests use local fake transports and require no SSH credentials.
