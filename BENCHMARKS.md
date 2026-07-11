# Performance Benchmarks

## Summary

For interactive development, the measured relay overhead was small:

- Approximately 0.3 to 0.4 ms additional steady-state round-trip latency
- Approximately 0.1 to 0.4 seconds additional session setup time when all
  required authentication state was already available
- Approximately 20% to 30% lower bulk download throughput
- Upload impact varied by client implementation and platform

The relay is suitable for terminals, VS Code Remote SSH, source editing, and
ordinary SSHFS use. A direct connection remains preferable for sustained large
file transfers when repeated authentication is not a concern.

## Topology

The tested paths were:

```text
Direct: client -> target
Relay:  client -> Linux relay -> target
```

The direct Linux path reused a client-owned ControlMaster. The relayed paths
used a ControlMaster owned by the Linux relay. The direct Windows path used a
new authenticated connection because Windows did not hold a compatible
ControlMaster socket.

All machine names, usernames, domains, and target identifiers have been removed
from this report.

## Methodology

Each steady-state transport run used one SSH session and performed:

- 50 request/response echo exchanges for latency
- A 64 MiB download from the target
- A 64 MiB upload to the target

The Linux measurements used three runs for each path. The Windows relay used
three runs. The Windows direct path used one run because each new direct
connection required interactive multi-factor authentication.

Session setup was measured from client process creation until the benchmark
endpoint reported that it was ready. Consequently, the direct Windows setup
measurement includes password and multi-factor interaction and must not be
compared directly with pre-authenticated setup measurements.

The benchmark used generated zero-filled data. Results therefore represent SSH
transport and stream-processing behavior rather than storage performance.

## Results

Values below are averages except for the single Windows direct run.

| Client and path | Setup | Mean RTT | Download | Upload |
|---|---:|---:|---:|---:|
| Linux direct ControlMaster | 13.9 ms | 1.95 ms | 40.6 MiB/s | 36.7 MiB/s |
| Linux through relay | 104.1 ms | 2.24 ms | 28.6 MiB/s | 34.6 MiB/s |
| Windows direct, including MFA | 5.58 s | 2.48 ms | 38.7 MiB/s | 8.2 MiB/s |
| Windows through relay | 393.8 ms | 2.90 ms | 29.9 MiB/s | 6.7 MiB/s |

### Linux relay overhead

Compared with the direct Linux ControlMaster path:

- Setup increased by approximately 90 ms
- Mean round-trip latency increased by approximately 0.29 ms, or 15%
- Download throughput decreased by approximately 30%
- Upload throughput decreased by approximately 6%

### Windows relay overhead

Compared with the single direct Windows transport sample:

- Mean round-trip latency increased by approximately 0.42 ms, or 17%
- Download throughput decreased by approximately 23%
- Upload throughput decreased by approximately 18%

Direct Windows setup time is excluded from the overhead comparison because it
contains human multi-factor authentication delay. The relay setup completed in
approximately 0.39 seconds using existing relay authentication state.

Both Windows upload results were substantially lower than the Linux results,
which indicates a Windows client or benchmark-pipeline bottleneck independent
of the relay. They should not be interpreted as the target's upload capacity.

## Analysis

The relay adds another SSH process, encrypted transport, and network hop. This
primarily affects connection startup and sustained throughput. Once connected,
interactive traffic consists of small messages, so the measured sub-millisecond
latency increase is unlikely to be noticeable.

Bulk output is processed by both the inner and outer SSH transports. The extra
encryption, copies, flow control, and relay network path explain the measured
download reduction. Actual results will vary with client CPU, relay CPU,
network topology, cipher selection, and target load.

VS Code also creates dynamic forwarding channels. The project bridges the
relay-side SOCKS listener back to the client. That bridge adds another channel
but did not create material interactive latency in these measurements.

## Issue Found During Testing

The original native Windows client used managed asynchronous stream-copy
operations. Short commands worked, but small control messages in a persistent
session could remain buffered, and sustained bidirectional tests could stall.

The implementation was changed to dedicated stream pumps with explicit 4 KiB
read, write, and flush cycles. The benchmark completed after this change, and
the same behavior is important for long-lived VS Code and terminal sessions.

## Limitations

- Measurements were taken on one client network and one relay topology.
- Target and network load were not controlled.
- The direct Windows path has only one transport sample.
- The test did not measure many simultaneous VS Code windows or SSHFS mounts.
- Generated data does not represent compression-sensitive workloads.
- Results are comparative observations, not capacity guarantees.
