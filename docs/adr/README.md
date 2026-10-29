# Architecture decisions

Each significant decision is recorded here, with the options that were rejected and why.

| Decision | Rationale | Record |
|---|---|---|
| OpenTofu rather than Terraform | MPL-2.0 licensing, supported by Infomaniak's own documentation | [ADR 0001](0001-use-opentofu-instead-of-terraform.md) |
| Self-managed k3s rather than managed Kubernetes | The cluster bootstrap is part of what this repository demonstrates | [ADR 0002](0002-run-a-self-managed-k3s-cluster.md) |
| Application credentials rather than user passwords | Scoped, revocable, never tied to a human account | [ADR 0003](0003-authenticate-with-an-application-credential.md) |
| Private network behind a router rather than the shared public network | Nothing is reachable from the internet until a floating IP says so | [ADR 0004](0004-place-nodes-on-a-private-network.md) |
| Outbound traffic denied by default | Every flow a node can open is declared, and reviewed as code | [ADR 0005](0005-deny-outbound-traffic-by-default.md) |
| State in Swift through the S3 API, without a lock | The platform's S3 layer refuses the conditional write a lock needs; saved plans and versioning stand in | [ADR 0006](0006-store-the-state-in-swift-without-a-lock.md) |
| State and plans encrypted by OpenTofu | The state holds the cluster's join token, in storage the project's credentials can read | [ADR 0007](0007-encrypt-the-state-and-plans.md) |
| Node image pinned by ID | Glance republishes images under the same name; a lookup by name would replace the cluster at each rebuild | [ADR 0008](0008-pin-the-node-image-by-id.md) |
| One etcd member per availability zone | A lost zone costs one member, not the quorum, for under a millisecond of latency | [ADR 0009](0009-place-one-etcd-member-per-availability-zone.md) |
| etcd on the root disk, below its latency guideline | Measured: neither the root disk nor a Ceph volume meets it, and the gap has not yet been shown to matter | [ADR 0010](0010-keep-etcd-on-the-root-disk.md) |
| A bastion as the only way in | No node has a public address, and the exposed machine is not a member of the cluster | [ADR 0011](0011-reach-the-nodes-through-a-bastion.md) |
| Join token passed in user data | The cluster forms from one apply; each server drops its pods' traffic to the metadata service, the one path to user data that needs no root | [ADR 0012](0012-pass-the-join-token-in-user-data.md) |
| k3s installed by cloud-init from the release's own script | `get.k3s.io` serves a script that follows the main branch; the tagged one runs as root only if its SHA-256 matches | [ADR 0013](0013-install-k3s-from-cloud-init.md) |
| Our own Traefik and cert-manager | ingress-nginx is retired, and the copy k3s bundles would tie its settings to the servers' user data | [ADR 0014](0014-serve-https-with-traefik-and-cert-manager.md) |
| An Octavia load balancer on a stable address | No node gets a public address, the client's address reaches the applications, and the DNS record survives every rebuild | [ADR 0015](0015-enter-through-an-octavia-load-balancer.md) |
| Argo CD as an app of apps, installed with Helm | Git becomes the way to change what runs in the cluster; Argo CD cannot install itself, and does not manage itself | [ADR 0016](0016-deliver-the-cluster-services-with-argo-cd.md) |
| OpenTofu outside the cluster, Argo CD inside | Every resource has one owner, and the four values that cross the line are listed in one place | [ADR 0017](0017-draw-the-line-between-opentofu-and-argo-cd.md) |
| kube-prometheus-stack, Prometheus on a Cinder volume | etcd's disk is checked over time, and Prometheus does not write next to it; the driver's credential is narrowed by access rules | [ADR 0018](0018-observe-the-cluster-with-prometheus-on-a-cinder-volume.md) |
| Velero to a Swift container that survives every rebuild | Only what Git cannot recreate, without Secrets; a restore measured at about three minutes | [ADR 0019](0019-back-up-to-swift-with-velero.md) |
| `make up` and `make down` on the workstation, CI without secrets | Any S3 key is worth the whole project, so the CI checks and the workstation applies; every phase can run twice | [ADR 0020](0020-build-from-the-workstation-and-check-in-ci.md) |
