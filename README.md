# SSH Client Relay

`ssh-client-relay` lets a client delegate selected SSH connections to another
SSH-reachable machine. The relay machine runs the final SSH client and can reuse
credentials or a ControlMaster socket that exists only on that machine.

```text
client application -> local ssh-client-relay -> SSH to relay
                   -> SSH client on relay -> final SSH server
```

All other destinations continue to use the client's normal OpenSSH executable.
This makes the wrapper suitable as a global SSH runtime for applications such
as VS Code Remote SSH while changing the route for only one configured target.

## How it works

The client wrapper sends a protocol marker, argument count, and NUL-delimited
SSH arguments to a fixed helper on the relay. The helper reconstructs the exact
argument array without evaluating it as shell source, then executes the relay's
`/usr/bin/ssh`. After the argument frame, the same channel transports the inner
SSH process's stdin and stdout.

Dynamic forwarding needs one additional bridge. An inner `-D PORT` listener is
created on the relay, while applications such as VS Code expect it on the
client. The wrapper therefore adds an outer `-L PORT:127.0.0.1:PORT` forward so
the client-local port reaches the relay-local SOCKS listener.

This requires two independent connections:

1. The client must be able to SSH to the relay.
2. The relay must be able to SSH to the final server.

The second connection may reuse a relay-owned ControlMaster, but that is not a
requirement.

Measured performance and methodology are documented in [BENCHMARKS.md](BENCHMARKS.md).

## Requirements

- Bash and OpenSSH on the relay
- A working, preferably non-interactive SSH login from client to relay
- A working SSH configuration or route from relay to the final server
- On a Linux client: Bash, OpenSSH `ssh` and `scp`, and `install`
- On a Windows client: Windows PowerShell 5.1 or later and Windows OpenSSH

The relay must run Linux because the helper uses Bash and the intended
authentication reuse mechanism is an OpenSSH ControlMaster Unix socket. The
client may run Linux or Windows; WSL is not required for the Windows client.

## Install on Linux

Supply the relay's SSH name, the client-facing target alias, and the target name
understood by the relay:

```bash
./install.sh RELAY_HOST TARGET_ALIAS TARGET_HOST
```

For example:

```bash
./install.sh ssh-relay compute compute.example.org
```

Environment variables are also supported:

```bash
RELAY_HOST=ssh-relay \
TARGET_ALIAS=compute \
TARGET_HOST=compute.example.org \
./install.sh
```

The installer creates:

- `~/.local/bin/ssh-client-relay` on the client
- `~/.config/ssh-client-relay/config` on the client
- `~/.local/bin/ssh-client-relay-helper` on the relay

`RELAY_HOST` must resolve through DNS or the client's SSH configuration.

## Install on Windows

Run Windows PowerShell from the repository directory. If script execution is
restricted, use a process-scoped bypass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-windows.ps1 `
    ssh-relay compute compute.example.org
```

The Windows installer:

- Compiles `windows\SshClientRelay.cs` into a native Windows-launchable .NET
  console executable using PowerShell's built-in C# compiler.
- Writes `%USERPROFILE%\.config\ssh-client-relay\config.windows`.
- Copies the shared Bash helper to the Linux relay.

It installs the client executable at:

```text
%USERPROFILE%\bin\ssh-client-relay.exe
```

No WSL, Visual Studio, separate .NET SDK, Python, or third-party package is
required. The Windows client uses `ssh.exe` and `scp.exe` from Windows OpenSSH.

## Verify

Using the example configuration:

```bash
~/.local/bin/ssh-client-relay -O check compute
~/.local/bin/ssh-client-relay compute hostname
printf 'stream-test\n' | ~/.local/bin/ssh-client-relay compute \
    'read line; printf "%s\n" "$line"'
```

A non-target host is dispatched directly to `/usr/bin/ssh`:

```bash
~/.local/bin/ssh-client-relay -G ssh-relay
```

## VS Code on Linux

Complete the following setup before changing `remote.SSH.path`.

### 1. Confirm where VS Code runs

This configuration is for a VS Code client process running on Linux. The path
in `remote.SSH.path` is resolved by the client process. A Windows VS Code client
cannot execute `/home/your-user/.local/bin/ssh-client-relay`; it needs the
Windows client executable instead.

### 2. Configure the client-to-relay connection

The relay name passed to `install.sh` must work with the client's normal SSH.
For example, the Linux client's `~/.ssh/config` can contain:

```sshconfig
Host ssh-relay
    HostName relay.example.com
    User relay-user
    Port 22
    IdentityFile ~/.ssh/id_ed25519
```

Verify the outer connection independently:

```bash
/usr/bin/ssh ssh-relay true
/usr/bin/ssh -o BatchMode=yes ssh-relay true
```

The second command should succeed without a password or interactive MFA prompt.
If it does not, configure a key or a separate ControlMaster for the relay. Any
authentication prompt on this outer connection will otherwise occur whenever
VS Code starts a relayed connection.

### 3. Configure the relay-to-target connection

On the relay machine, configure the final server in `~/.ssh/config`. For
example, `ssh-relay:~/.ssh/config` needs an entry equivalent to:

```sshconfig
Host compute.example.org compute
    HostName compute.example.org
    User remote-user
    ControlMaster auto
    ControlPath ~/.ssh/controlmasters/%r@%h:%p
    ControlPersist 48h
```

Create the socket directory once:

```bash
ssh ssh-relay 'mkdir -p ~/.ssh/controlmasters && chmod 700 ~/.ssh/controlmasters'
```

Then log in from the relay and complete any password or MFA authentication. An
interactive session, service, or command such as the following can establish
the master:

```bash
ssh -t ssh-relay 'ssh compute'
```

After disconnecting that interactive session, confirm that the persistent
master remains available:

```bash
ssh ssh-relay 'ssh -O check compute'
```

The expected result contains `Master running`. The relay can connect without a
ControlMaster, but then every new VS Code connection may require the target's
normal authentication.

### 4. Install and verify the relay wrapper

Run the installer on the Linux client:

```bash
./install.sh ssh-relay compute compute.example.org
```

Before involving VS Code, all of these commands must work:

```bash
~/.local/bin/ssh-client-relay -O check compute
~/.local/bin/ssh-client-relay compute hostname
~/.local/bin/ssh-client-relay -G compute | grep -E '^(hostname|user|port) '
```

The first command should report the relay's master as running. The second should
print the final server's hostname. The third should show the final server's
effective SSH configuration as evaluated on the relay.

Also verify that an unrelated host still uses local SSH:

```bash
~/.local/bin/ssh-client-relay -G ssh-relay
```

### 5. Make the target discoverable in VS Code

VS Code reads the client's SSH config to populate `Remote-SSH: Connect to Host`.
Add at least a host declaration to the Linux client's `~/.ssh/config`:

```sshconfig
Host compute
    HostName compute.example.org
```

The connection details used for the final hop still come from the relay's SSH
configuration. This local entry primarily makes the target visible to VS Code
and ensures that either the alias or canonical hostname triggers dispatch.

### 6. Set the VS Code SSH runtime

In the Linux VS Code user `settings.json`, set the absolute path:

```json
"remote.SSH.path": "/home/your-user/.local/bin/ssh-client-relay"
```

Although `remote.SSH.path` is global, the wrapper relays only the configured
target alias or canonical hostname. Other hosts continue through
`/usr/bin/ssh` on the client.

Reload VS Code, run `Remote-SSH: Connect to Host`, and select the configured
target alias. If connection fails, inspect `View: Output` and select
`Remote - SSH`; first rerun the commands in steps 2 through 4 outside VS Code to
identify whether the failed hop is client-to-relay or relay-to-target.

## VS Code on Windows

Complete these steps before changing `remote.SSH.path`.

### 1. Configure Windows-to-relay SSH

Add the Linux relay to `%USERPROFILE%\.ssh\config`:

```sshconfig
Host ssh-relay
    HostName relay.example.com
    User relay-user
    Port 22
    IdentityFile ~/.ssh/id_ed25519
```

From PowerShell, verify both interactive and non-interactive access:

```powershell
ssh.exe ssh-relay true
ssh.exe -o BatchMode=yes ssh-relay true
```

The second command should complete without a password or MFA prompt. This is
the outer connection. It is independent of the relay's ControlMaster for the
final server.

### 2. Prepare relay-to-target SSH

Configure and establish the target ControlMaster on the Linux relay exactly as
described in steps 3 and 4 of the Linux VS Code section. From PowerShell, the
key verification is:

```powershell
ssh.exe ssh-relay "ssh -O check compute"
```

It should report `Master running` before VS Code is started.

### 3. Run the Windows installer

In Windows PowerShell, from this repository:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-windows.ps1 `
    ssh-relay compute compute.example.org
```

The installer itself connects to the relay twice to deploy the helper. Complete
any outer-hop authentication prompts during installation.

### 4. Verify the executable outside VS Code

Run all checks from PowerShell:

```powershell
& "$env:USERPROFILE\bin\ssh-client-relay.exe" -O check compute
& "$env:USERPROFILE\bin\ssh-client-relay.exe" compute hostname
& "$env:USERPROFILE\bin\ssh-client-relay.exe" -G compute
& "$env:USERPROFILE\bin\ssh-client-relay.exe" -G ssh-relay
```

The first three commands use the Linux relay. The last command demonstrates
that an unrelated destination still goes directly through Windows OpenSSH.

### 5. Make the target visible to VS Code

Add the target alias to `%USERPROFILE%\.ssh\config` if it is not already
present:

```sshconfig
Host compute
    HostName compute.example.org
```

This entry makes `compute` appear in `Remote-SSH: Connect to Host`. The final
connection settings and credentials still come from the Linux relay.

### 6. Set the Windows VS Code SSH runtime

In the Windows VS Code user `settings.json`, set:

```json
"remote.SSH.path": "C:\\Users\\your-user\\bin\\ssh-client-relay.exe"
```

Reload VS Code and select `compute` from `Remote-SSH: Connect to Host`. The path
must point to the `.exe`, not the PowerShell installer or C# source file.
