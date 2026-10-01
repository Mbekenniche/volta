# 9. Place one etcd member per availability zone

## Status

Accepted — 2026-10-01

## Context

The cluster runs etcd embedded in k3s, on three servers: the smallest membership that survives
the loss of one. Where those three servers run decides what "the loss of one" can mean.

Region `dc3-a` exposes three compute availability zones, `dc3-a-04`, `dc3-a-09` and `dc3-a-10`.
Infomaniak's documentation describes them as having "different network connectivity and power
inputs"; this project has no way to verify what separates them physically and takes that
statement as given. Volumes and networks have a single zone, `nova`, with redundancy handled by
the storage backend.

## Decision

Place one server in each compute zone, and list the zones literally.

- A map at the root, `node_map`, gives each node a stable key and a zone:
  `"1" = "dc3-a-04"`, `"2" = "dc3-a-09"`, `"3" = "dc3-a-10"`. Ports and instances are both
  created from it, so a node and its port share a key.
- No server group. With as many nodes as zones, separate zones already mean separate hosts.

## Consequences

- **A lost zone costs one member, not the quorum.**
- **The latency is negligible.** Measured on 2026-10-01 around 09:30 UTC, with one series of
  100 pings per pair of nodes and no packet lost:

  | Pair | min / mean / max / std dev |
  |---|---|
  | `dc3-a-04` → `dc3-a-09` | 0.54 / 0.77 / 4.29 / 0.48 ms |
  | `dc3-a-04` → `dc3-a-10` | 0.49 / 0.87 / 5.81 / 0.74 ms |
  | `dc3-a-09` → `dc3-a-10` | 0.49 / 0.68 / 3.42 / 0.34 ms |

  Under a millisecond on average, against the 100 ms heartbeat etcd uses by default. One series
  at one time of day says nothing about busy hours.
- **A zone without capacity stops the apply** instead of quietly putting two members on the
  same side. That is intended.
- **Volumes are not tied to a compute zone.** A volume of zone `nova` was attached to an
  instance in `dc3-a-04` without error, which matters for the storage of later steps.
- **A new zone on the platform moves nothing.** The list is written in the code; reading it
  from the API would reshuffle the nodes when a zone appears.
- **The bastion has no zone.** It has no peer to keep apart; Nova placed it in `dc3-a-04`, then
  in `dc3-a-10` after a rebuild.

## Alternatives considered

**An anti-affinity server group without zones.** Rejected: it guarantees three hosts, which may
all sit in one zone.

**Both a server group and zones.** Not needed with three nodes and three zones. A fourth node,
such as a k3s agent, would need one, with `soft-anti-affinity`.

**Read the zones from the API.** Rejected: adding a zone to the platform would move existing
nodes.

**All nodes in one zone.** Rejected: it gives up the only failure domain the platform exposes,
for a latency gain under one millisecond.
