# 1. Run a self-managed k3s cluster

## Status

Accepted — 2026-09-19

## Context

Infomaniak sells a managed Kubernetes service, and its shared tier bills no control plane. It is
cheaper than running one on the project's own quota, and better for production. This repository
exists to show how a platform is built, and the cluster's bootstrap is part of that.

## Decision

Three k3s servers on instances created by OpenTofu, one per availability zone, with embedded
etcd.

- **cloud-init installs k3s** from the release's own script, run only if its SHA-256 matches.
  The join token travels in the servers' user data.
- **etcd stays on the root disk.** A test measured its `fdatasync` at 10 to 24 ms at the 99th
  percentile, and Prometheus 26 to 42 ms over four days, against etcd's guideline of 10 ms. A
  Ceph volume was faster in the tail, not in the median; the gap has not yet been shown to matter.
- **The kubeconfig is read over SSH** from a server, and kept on the workstation, mode 0600.

## Consequences

- Bootstrap, upgrades and etcd are this project's to run, with no SLA.
- Every k3s setting lives in the user data: changing one replaces the three servers.
- A lost zone costs one etcd member, not the quorum.
- The work runs on any OpenStack. Moving to the managed service would replace the compute and
  bootstrap code, and keep the rest.

## Alternatives considered

- **Managed Kubernetes, shared tier.** The right choice to run something real; rejected only for
  the purpose above.
- **kubeadm.** The same bootstrap in more steps, with etcd, certificates and a CNI to assemble.
