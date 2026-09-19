# Platform inventory

What the Infomaniak Public Cloud exposes to this project, read from the API on 2026-09-19 in
region `dc3-a` with the `volta-opentofu` application credential. Each section names the command
that produced it. Nothing here was taken from the provider's documentation without being
confirmed against the API first.

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

`openstack network list --external`

Two external networks: `ext-floating1`, which carries the floating IP pool, and
`ext-provider1`.

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

The binding constraint is **20 ports**, not the CPU or memory ceiling. Every instance, every
router interface and every Octavia amphora consumes one, so the port budget runs out well
before the twenty vCPUs do.

## Starting state

`openstack keypair list` and `openstack security group list`

No keypairs, and the default security group only. Everything this platform runs on is created
by the code in this repository.
