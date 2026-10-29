# 18. Observe the cluster with Prometheus, on a Cinder volume

## Status

Accepted — 2026-10-13

## Context

The cluster ran without any record of itself: nothing kept the history of its nodes, its pods or
etcd. [ADR 0010](0010-keep-etcd-on-the-root-disk.md) left etcd on a disk slower than etcd asks
for, to be checked "at the observability step, where Prometheus collects those metrics over
time". This is that step.

What the decision rests on, checked on 2026-10-11:

- **kube-prometheus-stack 92.3.0** brings the Prometheus operator, Prometheus, Grafana,
  kube-state-metrics and node-exporter, as an OCI chart. Its largest CRD weighs 878 KB, far
  beyond the 256 KB a client-side `kubectl apply` can annotate.
- **Grafana's admin password changes at every render** when none is set, and Argo CD renders the
  chart at every new revision.
- **k3s runs the controller manager, the scheduler, the proxy and etcd inside one process.** The
  chart looks for them as separate pods. etcd serves its metrics on `127.0.0.1:2381`;
  `etcd-expose-metrics` adds the node's address, over HTTP, without authentication.
- **Cinder has one volume type and one zone, `nova`**, while compute has three. A `nova` volume
  attaches to an instance in any of them. The Cinder CSI driver can ignore the zones.
- **An application credential cannot create another one.** The driver's credential is created
  with the account's password, and Keystone accepts access rules that narrow it to given calls.

## Decision

Run kube-prometheus-stack, delivered by Argo CD like the rest, with Prometheus on a Cinder volume.

- **kube-prometheus-stack 92.3.0**, in the `monitoring` namespace, in sync wave 2, with
  server-side apply for its CRDs. Its admission webhooks take their certificates from
  cert-manager, so the chart runs no hook Job.
- **Prometheus keeps its data on a 10 GiB Cinder volume**, through the Cinder CSI driver
  (chart 2.36.5, wave 0), with topology disabled. Retention is ten days, capped at 8 GiB.
- **The driver has its own application credential**, with the `member` role, an expiry date, and
  access rules limited to volume calls on Cinder and to reads and volume attachments on Nova.
- **etcd's metrics are exposed on the node's address**, port 2381, with `etcd-expose-metrics` in
  the servers' user data and an ingress rule from the private subnet. A scrape job finds the nodes
  through the Kubernetes API, so no address is written down. The monitors for the controller
  manager, the scheduler and the proxy are disabled; etcd's alerting rules stay.
- **node-exporter is reachable between nodes** on port 9100, from the cluster's security group.
- **Grafana is not exposed and has no volume.** It is reached with `kubectl port-forward`, like
  Argo CD, and its admin password comes from a Secret.
- **No Alertmanager.** The rules run and their alerts show in Prometheus; nobody is on call to
  receive them.
- **Two Secrets are created outside Git**, from files on the workstation: the driver's
  `cloud.conf` and Grafana's admin password. `make up` creates them before Argo CD starts
  ([ADR 0020](0020-build-from-the-workstation-and-check-in-ci.md)).

## Consequences

Measured on 2026-10-25, one reading each:

| Measure | Value |
|---|---|
| Memory, Prometheus / Grafana | 721 MiB / 448 MiB |
| Memory used per node, out of 3.8 GiB | 48 to 61 %, against 1229 to 1298 MiB before this step |
| Active series | 173,441, of which kubelet and cAdvisor 90,787, the API server 65,429, etcd 5,189 |
| Data written | about 0.54 GB a day: ten days, about 5.4 GB, fit under the 8 GiB cap |
| From a push to the change applied | 31 to 136 s, four samples |

- **The volume lives outside OpenTofu's state.** The driver creates it, and marks it
  `cinder.csi.openstack.org/cluster=volta-lab`. It is the first exception to
  [ADR 0017](0017-draw-the-line-between-opentofu-and-argo-cd.md): `make down` finds the volumes
  by that mark after the destroy, and deletes them. Prometheus's history goes with them; it
  survives in the backups ([ADR 0019](0019-back-up-to-swift-with-velero.md)).
- **An OpenStack credential lives in the cluster.** Its access rules let it create, attach,
  detach and delete volumes, and read on Nova. It cannot touch servers, networks or the load
  balancer.
- **etcd's metrics answer over HTTP to anything on the private subnet**, the bastion included.
  They carry no secret.
- **Turning `etcd-expose-metrics` on meant replacing the three servers**, like any k3s setting
  ([ADR 0013](0013-install-k3s-from-cloud-init.md)).
- **What etcd's metrics showed** is recorded in the amendment to
  [ADR 0010](0010-keep-etcd-on-the-root-disk.md).

## Alternatives considered

**local-path, the provisioner k3s ships.** No credential and nothing outside the cluster, but
the data would sit on the root disk next to etcd, which is already below its guideline, and the
pod would be bound to its node.

**No persistence.** Prometheus would lose its history at every restart of its pod.

**The driver's credential without access rules**, or OpenTofu's own. Rejected: a compromised
cluster could then destroy the whole project.

**The Secrets in the servers' user data**, which the driver can read from the host. Rejected:
the secret would enter the state, and changing it would replace the three servers. **SOPS or
Sealed Secrets** would put them in Git, at the cost of another component and a decryption key
placed by hand anyway.

**Reading etcd's metrics once, over SSH.** No replacement of the servers, but no history: the
promise of ADR 0010 would not have been kept.

**Grafana exposed**, behind a login on its own name: a second public surface for one user who
already has the tunnel. Anonymous read-only access, as a showcase for the energy dashboards, is
left to the dashboards step.

**An Alertmanager**, with no receiver, or with mail, which needs an outbound rule that
[ADR 0005](0005-deny-outbound-traffic-by-default.md) does not open.
