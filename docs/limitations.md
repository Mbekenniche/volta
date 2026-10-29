# Known limitations

- **Energy figures are estimates.** RAPL counters are not exposed inside a virtual machine, so
  per-pod power is derived from a model rather than read from hardware. The margin of error is
  documented alongside the dashboard rather than hidden behind it.
- **The DNS record is set by hand.** It points at the ingress's stable address, which survives
  every rebuild, so it was set once, and `make up` has nothing to change there. Designate is not
  used; see [ADR 0020](adr/0020-build-from-the-workstation-and-check-in-ci.md).
- **The entry point is not spread across zones.** On 2026-10-09, both of the load balancer's
  amphorae ran in the same zone, one of the cluster's three. Losing it would cost the entry point
  as well as one etcd member.
- **Administration has a single door.** The bastion is the only way to the nodes. If it fails, the
  cluster keeps running but cannot be administered until an apply recreates it.
- **etcd's disk is slower than etcd asks for.** Measured `fdatasync` latency at the 99th
  percentile is 10 to 24 ms on the nodes' root disks in a test, and 26 to 42 ms over four days
  of Prometheus, against a guideline of 10 ms; see
  [ADR 0010](adr/0010-keep-etcd-on-the-root-disk.md).
- **User data is readable from inside every instance**, from a config drive the platform always
  attaches and from the metadata service, and the servers' user data carries the cluster's join
  token. Root on a server can read the token anyway; each server drops its pods' traffic to the
  metadata service. See [ADR 0012](adr/0012-pass-the-join-token-in-user-data.md).
- **Every k3s setting is fixed when a server is created.** It lives in the user data, so changing
  the version or any option replaces the three servers, and the cluster with them. That holds
  while nothing lives only in the cluster; see
  [ADR 0013](adr/0013-install-k3s-from-cloud-init.md).
- **The metered cost is incomplete.** For nine hours, CloudKitty rated only the reserved part of
  one running node, never its running part. Cost figures taken from it are a lower bound, and
  say so; see the [inventory](platform-inventory.md#cost).
- **Argo CD sits outside its own reconciliation.** Helm installs it, and its values in Git are
  applied when Helm runs again, not when they are pushed; the two can disagree without notice. See
  [ADR 0016](adr/0016-deliver-the-cluster-services-with-argo-cd.md).
- **Changes arrive by polling.** Argo CD is not exposed, so GitHub cannot notify it: a pushed
  change takes up to three minutes to land.
- **A rebuild needs five services on the Internet.** GitHub, `ghcr.io`, `quay.io`, `docker.io` and
  `ecr-public.aws.com` serve the manifests, charts, images and k3s's installation script. A
  running cluster does not need them to keep serving; see
  [ADR 0017](adr/0017-draw-the-line-between-opentofu-and-argo-cd.md).
- **The state has no lock.** One operator, saved plans and a versioned container stand in for
  it. That holds for a lab run by one person, and not beyond; see
  [ADR 0006](adr/0006-store-the-state-in-swift-without-a-lock.md) and the
  [remote state runbook](runbooks/remote-state.md).
- **Only the workstation builds the platform.** The CI checks every change but cannot see drift,
  which needs a `plan`, and so the state. A second operator would need the lock the state lacks;
  see [ADR 0020](adr/0020-build-from-the-workstation-and-check-in-ci.md).
- **`make down` trusts the state.** Once, it left servers and the load balancer behind, for a
  cause not found; what is left is listed after each destroy. See
  [what broke](what-broke.md#a-destroy-that-forgot-half-the-platform).
- **Every fresh cluster takes a production certificate.** Let's Encrypt issues five a week for the
  same names: more than five rebuilds in a week need the staging issuer.
- **Backups hold one namespace.** `monitoring`, with Prometheus's volume; everything else comes
  back from Git. The restore proven is that of a namespace on a running cluster; see
  [ADR 0019](adr/0019-back-up-to-swift-with-velero.md).
- **Two OpenStack credentials live in the cluster.** The Cinder CSI driver's is narrowed by access
  rules to volume calls and reads on Nova. Velero's S3 key is worth the account's rights on the whole project,
  through Keystone's `ec2tokens`, the state's container included.
