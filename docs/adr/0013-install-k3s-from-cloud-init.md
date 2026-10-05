# 13. Install k3s from cloud-init, from a pinned and verified script

## Status

Accepted — 2026-10-05

## Context

[ADR 0002](0002-run-a-self-managed-k3s-cluster.md) chose k3s, and
[ADR 0009](0009-place-one-etcd-member-per-availability-zone.md) three servers, one per zone, each
an etcd member that also runs workloads. The servers are created by OpenTofu from the pinned image
([ADR 0008](0008-pin-the-node-image-by-id.md)). Each has to install k3s at first boot and join the
others, with nothing done by hand.

The usual installation is `curl -sfL https://get.k3s.io | sh -`. On 2026-10-01, the script served
there was not the one tagged with the release: 38,693 bytes, against 37,118 for the `install.sh`
of `v1.36.4+k3s1`. It follows the main branch. The `stable` channel pointed to `v1.36.4+k3s1`, and
`latest` to `v1.37.0+k3s1`.

OpenTofu creates the three servers at the same time. k3s's documentation on embedded etcd asks for
an odd number of servers and a shared token; it does not say whether servers may join at the same
time.

## Decision

Every server installs k3s from cloud-init, from the script tagged with a pinned release, and only
if that script is the expected one.

- **Version and checksum.** `k3s_version` is `v1.36.4+k3s1`, from the `stable` channel.
  cloud-init downloads `install.sh` from that release's tag, with a URL built from the version,
  and runs it only if its SHA-256 matches `k3s_install_script_sha256`. The script then checks the
  binary against the release's own checksum file. The two variables sit side by side: a new
  version needs a new checksum.
- **The options live in a file**, `/etc/rancher/k3s/config.yaml`, written by cloud-init: the join
  token ([ADR 0012](0012-pass-the-join-token-in-user-data.md)), `cluster-cidr`,
  `secrets-encryption` from the first start, and Traefik disabled, since the ingress controller
  arrives with the ingress step. CoreDNS, metrics-server, the local-path provisioner and
  ServiceLB stay as k3s ships them; the ingress and observability steps decide their fate.
- **One server initialises the cluster.** `init_node` names it explicitly, rather than taking the
  first entry of the map; a validation checks that it is one of the nodes. Only that server
  carries `cluster-init`. The others join it at the address of its port, which exists before any
  instance does and stays the same when the instance is replaced.
- **No ordering between the servers.** The three start together, and k3s is relied on to wait
  for the first one.
- **The servers' cloud-init is a template** (`.tftpl`). The bastion keeps its own file.

## Consequences

Measured on 2026-10-02, on one `apply` that replaced the three servers:

| | Result |
|---|---|
| Script checksum | `/root/k3s-install.sh: OK` in the cloud-init log of each server |
| Version | `v1.36.4+k3s1` on the three servers, etcd 3.6.14 |
| Nodes `Ready` | 32, 48 and 62 s after the last server became active |
| Restarts of `k3s.service` | none, on any server |

Server 2 started k3s two seconds after server 1. It joined etcd as a learner, then was promoted
to voting member: k3s waits for the first server inside its own process, and systemd never had to
restart it. After a full destroy and apply on 2026-10-05, the cluster formed again with no
intervention.

- **Every option is fixed at creation.** User data belongs to the instance: changing the version,
  an option or the token replaces the three servers, and the cluster with them. That is
  acceptable while nothing lives only in the cluster.
- **The script comes from GitHub at boot.** If GitHub does not answer, the checksum fails and k3s
  is not installed.
- **cloud-init does not stop at the first failing command.** cloud-init 26.1 joins the `runcmd`
  items into a single `/bin/sh` script without `set -e`. The checksum and the installation are
  therefore chained on one line with `&&`: on separate lines, a failed check would not have
  prevented the script from running.

## Alternatives considered

**`get.k3s.io` with `INSTALL_K3S_VERSION`.** It is the command every guide gives. Rejected: it
pins the binary, not the script that installs it as root, which changes without notice.

**Installing the binary without the script.** Rejected: more code to redo what the script
already does, checksum included.

**Options on the command line**, through `INSTALL_K3S_EXEC`. Rejected: unreadable past three
options, where a YAML file reads like the rest of the configuration.

**Two resources, the first server and then the others**, to order their start. Not needed: the
joining servers waited on their own.

**`v1.37`, from the `latest` channel.** Rejected: `stable` is the channel k3s recommends, and the
operator's `kubectl` 1.36 stays within the supported version skew.
