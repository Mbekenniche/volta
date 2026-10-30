# Platform inventory

What the Infomaniak Public Cloud offers this project, read from its API in region `dc3-a`
between 2026-09-19 and 2026-10-29. Nothing here comes from the documentation alone.

## Services

| Service | Used for |
|---|---|
| Nova, Neutron, Glance | Instances, private network, router, security groups, images |
| Octavia | The entry point: one load balancer, TCP 80 and 443 |
| Cinder | Prometheus's volume |
| Swift, through S3 | The state and Velero's backups |
| CloudKitty | The billed cost, to compare with the energy model |
| Designate, Barbican, Heat | Not used |

No Magnum: Infomaniak's managed Kubernetes sits outside the OpenStack API.

## Compute

- **Three availability zones**, `dc3-a-04`, `-09` and `-10`; one zone, `nova`, for volumes and
  networks.
- **`-perf1` flavors cap disk I/O** at 500 IOPS and 200 MB/s. A `-perf2` tier exists on request.
- **Images are rebuilt under the same name**, irregularly, and the old build is hidden, not
  deleted. The nodes pin an image ID.
- **Ubuntu 24.04 sees its disk as `/dev/sda`** (virtio-SCSI), on KVM with AMD EPYC-Rome.
- **No energy counter reaches the guest**: no RAPL, an empty `/sys/class/powercap`.

## Network

- **A project network gets an MTU of 1500**; Flannel's VXLAN fits inside it.
- **The router is highly available and translates outbound traffic**; its gateway is billed like
  a floating IP.
- **The shared network `ext-net1` hands out public addresses** to any port attached to it. The
  cluster does not use it.
- **The project's default security group filters outbound TCP 25.** A new group does not inherit
  that filter.
- **The CLI shows `0.0.0.0/0` for rules scoped to a group**; the API returns no prefix.

## Load balancer

- **Provider `amphora`, two amphorae** per load balancer, both in `dc3-a-09` on 2026-10-09.
- **`ACTIVE` about 1 min 20 s after creation.**
- **A new health monitor shows its members `ONLINE` for about a minute**, whatever listens.
- **Any database error while a monitor is created reads "TCP is not a valid option for type".**

## Storage

- **One volume type, `CEPH_1_perf1`**: 500 IOPS, 200 MB/s. A `nova` volume attaches in any zone;
  the guest names it differently from Nova, so it is found by `/dev/disk/by-id/`.
- **Swift 2.30.1, S3 at `https://s3.pub1.infomaniak.cloud`**, signing region `us-east-1`.
- **Swift refuses conditional writes** (`If-None-Match: *`, 501), so the state cannot be locked.
- **Swift refuses `aws-chunked` uploads** (501): Velero's checksum is turned off.
- **Versioning works**; an old version is restored by copying it over the current one.

## Identity

- **An application credential cannot create S3 keys** (403); one is created with the account's
  password.
- **Any S3 key can be traded for a Keystone token** (`/v3/ec2tokens`), with the account's rights.

## Inside an instance

- **The user data is readable from inside**, on a config drive attached to every instance and
  from the metadata service.
- **The console log carries the SSH host keys at first boot**, but Nova keeps only its last
  1,200 lines or so.
- **cloud-init is done 41 to 48 s after creation** on a 2 vCPU node.

## Quotas

| Instances | vCPU | RAM | Volumes | Ports | Floating IPs | Security group rules |
|---|---|---|---|---|---|---|
| 10 | 20 | 64 GB | 20, 1000 GB | 20 | 10 | 100 |

The running platform uses 4 instances, 7 vCPUs, 14 GB, 8 ports and 2 floating IPs.

## Cost

CHF per hour, excluding tax, as published on 2026-09-28. CloudKitty counts in ICU, 50 to the franc.

| Resource | CHF per hour |
|---|---|
| `a1-ram2-disk20-perf1`, the bastion | 0.00640 |
| `a2-ram4-disk20-perf1`, a node | 0.01043 |
| Volume, per GiB | 0.00012 |
| Floating IP, or the router's gateway | 0.00457 |
| Load balancer | 0.0137 |

- **Running: about 1.56 CHF a day.** Destroyed: about 0.11, for the stable address.
- **CloudKitty matches the list price, but missed part of the bill**: over nine hours, one running
  node had only its reserved part rated. Its figures are a lower bound.
