# 2. Run a self-managed k3s cluster rather than the managed Kubernetes service

## Status

Accepted — 2026-09-19

## Context

Infomaniak sells a managed Kubernetes service on this Public Cloud, and it is a good one. As
listed in September 2026, the shared tier costs nothing: the control plane is not billed, it
carries up to ten nodes, and only the worker instances and their storage are charged at
standard Public Cloud rates. Dedicated control planes start at EUR 0.04 per hour and add an
SLA, replicated etcd and a higher node ceiling. Clusters are created from the console, from an
API, or from a Terraform / OpenTofu connector. Cilium is the default CNI, the ingress
controller is left to the user, and worker nodes sit on a private network.

The service is not reachable through the standard OpenStack API — Magnum is absent from the
catalogue — so it is a product alongside OpenStack rather than a component of it. What Glance
does expose is the node side of it: eight versioned `Kaas Ubuntu … Kube` images.

So the question this ADR answers is not whether a managed option exists, nor whether it is
cheap enough. It exists, and on the shared tier it is cheaper than running a control plane on
one's own quota. The question is what this repository is for.

## Decision

Bootstrap a self-managed k3s cluster on instances provisioned by OpenTofu.

This repository is a demonstration of building a platform, and the cluster bootstrap is part
of what it demonstrates: instances created from code, configured by cloud-init, joined into a
cluster, with the kubeconfig surfaced as an OpenTofu output. A managed control plane would
remove precisely the layer the project exists to show.

That is the whole of the argument, and it is worth stating plainly that it is an argument about
purpose rather than about engineering. For production work on this platform, the managed
service is the better choice, and nothing below should be read as a case against it.

## Consequences

- The control plane costs project quota that the free shared tier would not have cost: an
  instance, a port, and a share of the twenty-port ceiling that binds this project before its
  CPU or memory ever will. This is a price paid deliberately.
- Bootstrap, upgrades, etcd and certificate rotation become this project's responsibility.
  There is no SLA and no vendor on call. Failures are the project's own, which is why the
  README reserves a section for them.
- The configuration stays portable. k3s on OpenStack instances runs on any OpenStack, so the
  work transfers off this provider unchanged.
- Measuring energy per workload requires a privileged DaemonSet with access to the node's
  cgroups. Owning the node removes any question of whether that is permitted. It does not
  improve the measurement itself: RAPL counters are unavailable inside a virtual machine
  either way, and the figures stay estimates.
- The decision is cheap to reverse. The cluster consumes the network layer rather than owning
  it, so adopting the managed service later would replace the compute and bootstrap code while
  leaving network, remote state, DNS, ingress and GitOps untouched.

## Alternatives considered

**Managed Kubernetes, shared tier.** The strongest alternative, and rejected only for the
reason given above. A free, unbilled control plane outside the project quota, driven from
OpenTofu like everything else, with Cilium already in place. Anyone building this platform to
run something real rather than to show how it is built should choose this.

**Managed Kubernetes, dedicated tier.** Rejected. From EUR 0.04 per hour it buys a 99.9% SLA,
two API server replicas and a dedicated etcd — insurance for an availability target this
project does not have.

**kubeadm.** Rejected. It would demonstrate the same bootstrap in more steps, with etcd,
control plane certificates and a CNI to assemble by hand. On a cluster sized for twenty vCPUs
the extra moving parts buy detail, not understanding. k3s is a CNCF-conformant distribution
that installs from a single binary, which keeps the cloud-init readable — and readability is
the point of writing it down.
