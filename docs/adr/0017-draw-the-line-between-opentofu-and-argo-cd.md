# 17. Draw the line between OpenTofu and Argo CD

## Status

Accepted — 2026-10-11

## Context

Two declarative tools now build the platform, and they work differently. OpenTofu runs on
demand, from the workstation, and records what it created in a state file. Argo CD runs in the
cluster, all the time, and its desired state is this repository
([ADR 0016](0016-deliver-the-cluster-services-with-argo-cd.md)).

Each needs a territory of its own. A resource claimed by both is changed twice, by whichever ran
last. A resource claimed by neither is forgotten at the next rebuild. And something has to put
Argo CD on an empty cluster, since it cannot install itself.

## Decision

Three owners, which act in this order on a fresh build:

| Owner | Runs | Owns |
|---|---|---|
| OpenTofu | From the workstation, at each `apply` | Everything in OpenStack: the network, security groups, bastion, servers, the load balancer with its pools and monitors, and, in the bootstrap stack, the stable public address. Also k3s's settings, through the servers' user data |
| Helm | From the workstation, through the tunnel to the API | Argo CD alone |
| Argo CD | In the cluster, continuously | Every other object in the cluster, from [`cluster/apps/`](../../cluster/apps/) |

- **OpenTofu does not reach into the cluster.** It has no `helm` or `kubernetes` provider, and
  never holds the cluster's credentials.
- **Nothing Argo CD creates lives outside the cluster.** There is no `LoadBalancer` Service to
  turn into an OpenStack load balancer: ServiceLB is disabled, and no cloud controller runs
  ([ADR 0013](0013-install-k3s-from-cloud-init.md), [ADR 0015](0015-enter-through-an-octavia-load-balancer.md)).
  There is no volume either. A destroy therefore leaves nothing behind that OpenTofu does not
  know about. Volumes requested from inside the cluster, which the observability step will need,
  would be the first exception; that step decides how to handle them.
- **Four values are written on both sides, by hand.** They must change together:

| Value | Outside the cluster | Inside the cluster |
|---|---|---|
| `179.237.92.39`, the stable public address | The floating IP of the bootstrap stack, and the DNS record | Published by Traefik on every `Ingress` ([`cluster/traefik/values.yaml`](../../cluster/traefik/values.yaml)) |
| Node ports `30080` and `30443` | The load balancer's members, and the security group rules that admit them | Traefik's Service |
| `10.10.0.0/24` | The subnet (`subnet_cidr`) | Traefik's `proxyProtocol.trustedIPs` |
| `*.volta.koveolabs.com` | The DNS record, set in Infomaniak's manager | The demo's `Ingress` |

## Consequences

- **A value changed on one side is not caught on the other.** Nothing checks the four pairs. A
  new public address would leave every `Ingress` publishing the old one, and Argo CD would still
  report them healthy. The table above is the list to read before changing any of them.
- **An `apply` never needs the tunnel; the bootstrap does.** After the `apply`, two commands from
  the workstation bring the cluster's services back: Helm for Argo CD, then the root
  `Application` ([cluster services runbook](../runbooks/cluster-services.md)).
- **No outbound rule was added.** Argo CD clones this repository from GitHub and fetches the
  Traefik and cert-manager charts from `ghcr.io` and `quay.io`; the nodes pull its images from
  `quay.io` and `ecr-public.aws.com`. All of it goes through the HTTPS rule of
  [ADR 0005](0005-deny-outbound-traffic-by-default.md). Nothing under `infra/` changed during this
  step.
- **A fresh cluster depends on more of the Internet.** The workstation used to fetch the charts;
  the cluster now fetches them itself, with its manifests from GitHub. Counting k3s's installation
  script ([ADR 0013](0013-install-k3s-from-cloud-init.md)) and the images, a rebuild needs GitHub,
  `ghcr.io`, `quay.io`, `docker.io` and `ecr-public.aws.com` to answer. A running cluster keeps
  serving without them: Argo CD is not on the path of the requests.

## Alternatives considered

**OpenTofu installs Argo CD**, with the `helm` or `kubernetes` provider in the main stack.
Rejected. The API is reachable only through the tunnel, so every `apply` would depend on a tunnel
being open. The provider would be configured from values that exist only once the servers do. And
the cluster's credentials would end up in the state.

**k3s installs Argo CD at boot**, from a `HelmChart` resource in its auto-deploying manifests,
written by cloud-init. The cluster would come up with Argo CD in a single `apply`. Rejected for
now: Argo CD's version would join the servers' user data, where any change replaces the three
servers ([ADR 0013](0013-install-k3s-from-cloud-init.md)). The one-command step may revisit it.

**A cloud controller in the cluster**, creating an OpenStack load balancer for each `LoadBalancer`
Service. Rejected in [ADR 0015](0015-enter-through-an-octavia-load-balancer.md): it would put an
OpenStack credential in the cluster, and OpenStack resources outside the state.

## Amendment — 2026-10-29

Two exceptions to the table above:

- **Cinder volumes**, created by the CSI driver for Prometheus
  ([ADR 0018](0018-observe-the-cluster-with-prometheus-on-a-cinder-volume.md)), live in OpenStack
  outside the state. A destroy leaves them behind; `make down` deletes them afterwards, found by
  the mark the driver sets on each.
- **Four Secrets are not Argo CD's**: the driver's credential, Grafana's admin password, Velero's
  S3 key and its repository password. Their source is a set of files on the workstation, and
  `make up` creates them before Argo CD starts
  ([ADR 0020](0020-build-from-the-workstation-and-check-in-ci.md)).

Velero's container, like the stable address, belongs to the bootstrap stack
([ADR 0019](0019-back-up-to-swift-with-velero.md)).
