# Platform inventory

What the Infomaniak Public Cloud exposes to this project, read from the API in region `dc3-a`
with the `volta-opentofu` application credential: first on 2026-09-19, then on 2026-09-24 once
the network layer had been built on top of it, and on 2026-10-01 from inside the first
instances. Each section names the command that produced it.
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

Infomaniak's documentation describes the three compute zones as having "different network
connectivity and power inputs". That is the provider's statement; nothing here can verify it.
Nova accepts microversions up to 2.93 in `dc3-a` and 2.96 in `dc4-a`; Cinder up to 3.70.

## Compute flavors

`openstack flavor list`

44 public flavors, named `a<vCPU>-ram<GB>-disk<GB>-perf1`.

- vCPU: 1, 2, 4, 8, 12, 16
- RAM: 2 GB to 64 GB
- Root disk: 20, 50 or 80 GB, or `0`

`openstack flavor list --long`

- **`-perf1` flavors carry I/O limits** in their extra specs: 500 IOPS and 200 MB/s for writes
  (`quota:disk_write_iops_sec`, `quota:disk_write_bytes_sec`), and 500 IOPS for reads. These are
  the same figures as the volume type below. Where their root disk is stored is not documented.
- **`-disk0` flavors carry no I/O limit of their own.** Infomaniak's documentation says their
  disk is "the same size as the image". Whether this project can boot one from an image, or
  only from a volume, was not tested. An earlier version of this page stated the latter as a
  fact; it had not been checked.
- **Infomaniak documents a `-perf2` tier**, 1,000 IOPS and 400 MB/s, available on request. It is
  not visible to this project.

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

### Images are rebuilt under the same name

`GET /v2/images?os_hidden=true` on the raw API, and `openstack image show <id>`

- **A rebuild replaces the visible image and hides the previous one.** The Ubuntu 24.04 image
  visible on 2026-09-14 was replaced on 2026-09-28 at 09:02 UTC by a build with a new ID. Hidden
  builds stay `active` and readable by their ID: on 2026-10-01 there were 46 of Ubuntu 24.04,
  the oldest from 2024-05-22, and 768 hidden images in all.
- **The rhythm is irregular.** Six rebuilds of Ubuntu 24.04 between 2026-07-20 and 2026-09-28,
  nearly always on a Monday around 09:00 UTC; none between December 2025 and February 2026.
- **The Ubuntu 24.04 image** is `qcow2`, stored in Swift, with its disk on a virtio-SCSI bus
  (`/dev/sda` in the guest, not `/dev/vda`), the QEMU guest agent enabled, and `ubuntu` as its
  default user.

Why the nodes pin an ID rather than a name is recorded in
[ADR 0008](adr/0008-pin-the-node-image-by-id.md).

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

One public volume type, `CEPH_1_perf1`, described as a "Reliable store tolerant to
disk/server/rack failure", with 500 IOPS and 200 MB/s. The project's quotas also name
`CEPH_1`, `CEPH_1_perf2`, `CEPH_1_perf3` and `CEPH_1_perf4`, which it cannot see or use.

Measured with a 20 GiB test volume on 2026-10-01, created and deleted the same morning:

- **A volume of zone `nova` attaches to an instance of zone `dc3-a-04`.**
- **The device name Nova reports is not the guest's.** Nova announced `/dev/sdc`; the guest saw
  the disk as `/dev/sdb`. The reliable name is `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_<volume
  id>`.
- **Synchronous writes take about 4.5 ms at the median**, as on the instances' root disks. The
  measurement, and why etcd stays on the root disk, are in
  [ADR 0010](adr/0010-keep-etcd-on-the-root-disk.md).

## Object storage

`GET /info` on the Swift endpoint, which answers without authentication, and S3 requests
signed with a key that does not exist, so that nothing can be written. Measured on
2026-09-24, then confirmed while moving the state there.

- **Swift 2.30.1**, with the `s3api` middleware for the S3 API and `object_versioning` for
  versioned containers.
- **The S3 endpoint for `dc3-a` is `https://s3.pub1.infomaniak.cloud`**, the same host as
  Swift.
- **The signing region must be `us-east-1`.** A request signed for `dc3-a` is rejected with
  `AuthorizationHeaderMalformed`, "the region 'dc3-a' is wrong; expecting 'us-east-1'".
- **Conditional writes are refused.** A `PUT` carrying `If-None-Match: *` gets `501
  NotImplemented`, "Conditional object PUTs are not supported.", before the signature is even
  checked. The same request without that header fails on its signature (403). Upstream Swift
  accepts `If-None-Match: *` from 2.36.0. This is why the state cannot be locked, see
  [ADR 0006](adr/0006-store-the-state-in-swift-without-a-lock.md).
- **Versioning works through both APIs.** A container with versioning enabled reports
  `X-Versions-Enabled: True` on Swift and `Enabled` on S3. Its versions are listed with
  `?versions`, and a `COPY` of an old version onto the current name restores it as a new
  version (201), without removing the others.
- **A private container refuses anonymous reads**, with 401.

## Identity

`openstack ec2 credentials create` with the application credential, and `POST /v3/ec2tokens`
with a key that does not exist

- **A restricted application credential cannot create S3 keys.** The request is refused with
  403, "Using method 'application_credential' is not allowed for managing additional
  application credentials." The message matches a check Keystone added to S3 key creation in
  a fix backported to its stable branches in April 2026 (bug 2142138). Before it, a restricted
  credential could create a key carrying every right of its owner.
- **An S3 key can be exchanged for a Keystone token.** `/v3/ec2tokens` is exposed: an unknown
  key gets 401, where an unknown route gets 404.

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
interface. After the compute layer, 7: one for each of the four instances. A floating IP uses
none of them. Which ceiling binds first, ports or the ten instances, depends on what the load
balancer consumes; that is measured in the ingress step rather than assumed here.

The compute layer uses 4 of 10 instances, 7 of 20 vCPUs, 14 of 64 GB of RAM, 1 of 10 floating
IPs and no volume.

## Inside an instance

`openstack console log show`, then SSH into the instances, on 2026-10-01

- **Every instance gets a config drive**, whether or not it is requested: Nova reports
  `config_drive: True`, and the guest sees an `iso9660` disk labelled `config-2`. cloud-init
  reads its data from it (`cloud-id: configdrive`).
- **The metadata service answers as well.** The guest gets a route to `169.254.169.254` through
  the router, and `/openstack/latest/user_data` returns the user data in clear. Anything placed
  in user data can be read from inside the instance, two ways.
- **The hosts are KVM on AMD EPYC-Rome processors.** The image runs kernel 6.8. A 4 GB flavor
  shows 3,915 MB to the guest; a 20 GB root disk shows 19 GB.
- **cloud-init finished 41 to 48 s after the instance was created** on a 2 vCPU node, and 82 to
  84 s on a 1 vCPU instance, in two rounds.
- **The console log carries the SSH host keys**, which is how the known hosts are built without
  trusting a first connection. See the [node access runbook](runbooks/node-access.md).
- **Ubuntu's packages come over plain HTTP**, from a mirror named after the zone
  (`http://dc3-a-04.clouds.archive.ubuntu.com/ubuntu/`) and from `security.ubuntu.com`. Only
  `snapd` asked for HTTPS.
- **Addresses are drawn at random from the subnet's pool**: `.17`, `.251`, `.152` for the nodes,
  then `.66`, `.219`, `.54` after a rebuild.

## Cost

Infomaniak's public price list, then `openstack rating dataframes get` and
`openstack rating summary get`

Prices below are excluding tax, in CHF per hour, as published on 2026-09-28. CloudKitty reports
in ICU, at 50 ICU to the franc.

| Resource | CHF per hour |
|---|---|
| `a1-ram2-disk20-perf1` (bastion) | 0.00640 |
| `a2-ram4-disk20-perf1` (node) | 0.01043 |
| `a2-ram4-disk0`, without its volume | 0.00805 |
| Volume `CEPH_1_perf1`, per GiB | 0.00012 |
| Floating IP, or the router's gateway | 0.00457 |
| Load balancer | 0.0137 |

- **The router's gateway is billed** like a floating IP, from the moment the router exists.
- **CloudKitty matches the list price to the fifth decimal.** It splits an instance into two
  hourly lines: for a node, `instance_up` at 0.40243 ICU and `instance_reserved` at 0.11890 ICU,
  0.010427 CHF in all.
- **CloudKitty missed part of the bill.** Over the nine hours rated by 2026-10-01 noon, one of
  the four instances, the node in `dc3-a-10`, had no `instance_up` line at all, only its reserved
  part, although it was running and in use. The hour from 04:00 UTC was missing for every
  resource. The rated cost is therefore lower than the price list says, and comparing energy
  with cost later has to allow for it.

## Starting state

`openstack keypair list`, `openstack security group list` and
`openstack security group rule list default`

No keypairs, and the default security group only. Everything this platform runs on is created
by the code in this repository.

The default group is not Neutron's stock one. Its TCP egress is split into ports 1–24 and
26–65535, so **outbound TCP port 25 is filtered**; UDP and ICMP egress are open, and ingress is
allowed only from members of the group.

**That filter is not inherited.** A probe group, created then deleted on 2026-09-24, came with
Neutron's two stock rules and nothing else: all outbound IPv4, all outbound IPv6. The API that
would describe this template, `/v2.0/default-security-group-rules`, answers 404 on this
platform. Security groups here are stateful (`stateful: true`): the reply to an accepted
connection needs no rule of its own.

The group this repository creates deletes Neutron's default rules and declares every flow
itself (`delete_default_rules = true`). Why is recorded in
[ADR 0005](adr/0005-deny-outbound-traffic-by-default.md).
