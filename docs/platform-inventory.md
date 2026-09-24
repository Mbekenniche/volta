# Platform inventory

What the Infomaniak Public Cloud exposes to this project, read from the API in region `dc3-a`
with the `volta-opentofu` application credential: first on 2026-09-19, then on 2026-09-24 once
the network layer had been built on top of it. Each section names the command that produced it.
Nothing here was taken from the provider's documentation without being confirmed against the
API first.

Account identifiers — project ID, credential ID, network UUIDs — are deliberately left out.
They are not secrets, but they identify a tenancy and tell a reader nothing.

## Services

`openstack catalog list`

| Service | Type | What this project uses it for |
|---|---|---|
| Keystone | `identity` | Application credential authentication |
| Nova | `compute` | Cluster instances |
| Neutron | `network` | Private network, router, security groups, floating IPs |
| Glance | `image` | Base images |
| Cinder | `volumev2`, `volumev3` | Persistent volumes |
| Swift | `object-store` | Remote state, and Velero backups later |
| Octavia | `load-balancer` | Ingress entry point |
| Barbican | `key-manager` | TLS material for the load balancer |
| Designate | `dns` | Candidate for managing records in the same `apply` |
| Ceilometer, Gnocchi, CloudKitty, Aodh | `metering`, `metric`, `rating`, `alarming` | Billed cost, to compare against the energy model |
| Heat, Heat-CFN | `orchestration`, `cloudformation` | Not used — see [ADR 0001](adr/0001-use-opentofu-instead-of-terraform.md) |
| Placement, Panko | `placement`, `event` | Internal to the platform |

Magnum (`container-infra`) is absent, so there is no OpenStack-native managed Kubernetes API
here. A managed offering exists outside the standard API nonetheless: Glance publishes eight
versioned Kubernetes node images.

Designate answers. `openstack zone list` returns an empty list rather than an error, and the
service has public endpoints in both regions. Whether a subdomain can be delegated to its
nameservers is a separate question, settled in the ingress step.

## Regions and availability zones

`openstack availability zone list --compute --volume --network`

Two regions are reachable with the same credential, `dc3-a` and `dc4-a`; this project stays in
`dc3-a`. Within it:

- **Compute**: three zones — `dc3-a-04`, `dc3-a-09`, `dc3-a-10`. Enough to spread cluster nodes
  across failure domains.
- **Volume and network**: one zone, `nova`.

## Compute flavors

`openstack flavor list`

44 public flavors, named `a<vCPU>-ram<GB>-disk<GB>-perf1`.

- vCPU: 1, 2, 4, 8, 12, 16
- RAM: 2 GB to 64 GB
- Root disk: 20, 50 or 80 GB, or `0`

A flavor ending in `-disk0` has no local root disk: the instance boots from a Cinder volume
instead. Which of the two models this platform uses is decided when the instances are created.

## Images

`openstack image list --status active`

45 active images. The relevant ones here:

- Debian 10, 11, 12, 13
- Ubuntu LTS 18.04, 20.04, 22.04, 24.04, 26.04, plus 25.04
- Rocky Linux 9 and 10, RHEL 8, 9 and 10, Oracle Linux 9, CentOS Stream 8 and 9
- Alpine Linux 3, Fedora Cloud 42, Fedora CoreOS 44, openSUSE Leap 16

Also present: eight `Kaas Ubuntu 2404/2604 Kube V1.30` through `V1.36` node images, two
Infomaniak rescue images, Windows Server 2019/2022/2025, FreeBSD, OPNsense, Arch, Gentoo,
RancherOS and CirrOS.

## Networking

`openstack network list` and `openstack network show <name>`

Four networks are visible before the project creates any of its own:

| Network | External | Shared | MTU | Subnets |
|---|---|---|---|---|
| `ext-floating1` | yes | no | 8950 | 5 |
| `ext-provider1` | yes | no | 8950 | 2 |
| `ext-net1` | no | yes | 1500 | 18 |
| `ext-v6only1` | no | yes | 1500 | 1 |

`ext-floating1` carries the floating IP pool, and the router of this platform takes its gateway
there. The two shared networks are not external, so a router cannot use either of them as its
gateway.

### The shared networks

`GET /v2.0/networks` and `GET /v2.0/subnets` on the raw API, and a probe port created then
deleted on 2026-09-24

- **`ext-net1` is public address space.** It belongs to another project and its description
  reads "Public shared network". Seventeen of its subnets are IPv4 `/24` blocks registered to
  Infomaniak at the RIPE NCC; the eighteenth is an IPv6 `/64`. All of them run DHCP, with
  resolvers set by the platform.
- **The project can attach to it directly.** The probe port was accepted, received one public
  IPv4 and one public IPv6 address, counted against the project's port quota, and was given the
  `default` security group, having named none.
- **`ext-v6only1` is its IPv6-only counterpart**: a single `/64`, described as "Public shared
  IPv6-only network".
- **The subnets of `ext-floating1` are not visible to the project.**

Why the cluster uses neither shared network is recorded in
[ADR 0004](adr/0004-place-nodes-on-a-private-network.md).

### Measured on the network layer

`openstack network show`, `openstack port list --long`, `openstack quota show --usage` and
`GET /v2.0/routers` on the raw API, after the first `apply` of [`infra/`](../infra/):

- **A project network gets an MTU of 1500**, not the 8950 of the external networks. An overlay
  built on top of it, such as Flannel's VXLAN in the cluster step, has to fit inside 1500 bytes.
- **Each subnet with DHCP enabled costs two ports**: Neutron places two `network:dhcp` ports on
  it.
- **The router is highly available.** Its interface on the subnet is owned by
  `network:ha_router_replicated_interface`, the owner Neutron gives to the interfaces of an HA
  router.
- **The router translates outbound traffic** (`enable_snat: true`) through a single address on
  `ext-floating1`.
- **The router's gateway port is not visible to the project** and does not count against its
  port quota.
- **Security group rules scoped to a group are misreported by the CLI**, which prints
  `0.0.0.0/0` as their source. The API returns no prefix for them. See
  [what broke](../README.md#what-broke-and-how-it-was-fixed).

## Block storage

`openstack volume type list`

One volume type, `CEPH_1_perf1`. There is no tier to choose between.

## Quotas

`openstack limits show --absolute` and `openstack quota show`

| Resource | Limit |
|---|---|
| Instances | 10 |
| vCPU | 20 |
| RAM | 64 GB |
| Volumes, total size | 20, 1000 GB |
| Snapshots, backups | 40, 40 (1000 GB) |
| Keypairs | 10 |
| Networks, subnets, routers | 10 each |
| Ports | 20 |
| Floating IPs | 10 |
| Security groups, rules | 10, 100 |
| Server groups, members per group | 10, 10 |

Nova reports `-1` for floating IPs and security groups. Neutron owns those two quotas and is
the authoritative source; the table above uses Neutron's values.

After the network layer, 3 of the 20 ports are in use: the two DHCP ports and the router
interface. Every instance adds at least one more. Which ceiling binds first, ports or the ten
instances, depends on what the load balancer consumes; that is measured in the ingress step
rather than assumed here.

## Starting state

`openstack keypair list`, `openstack security group list` and
`openstack security group rule list default`

No keypairs, and the default security group only. Everything this platform runs on is created
by the code in this repository.

The default group is not Neutron's stock one. Its TCP egress is split into ports 1–24 and
26–65535, so **outbound TCP port 25 is filtered**; UDP and ICMP egress are open, and ingress is
allowed only from members of the group. The group this repository creates deletes Neutron's
default rules and declares every flow itself (`delete_default_rules = true`).
