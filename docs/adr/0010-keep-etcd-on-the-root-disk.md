# 10. Keep etcd on the root disk, below its latency guideline

## Status

Accepted — 2026-10-01

## Context

etcd writes every change to its log and waits for the disk to confirm it with `fdatasync`
before answering. Its hardware guide asks for a 99th percentile of `fdatasync` latency under
10 ms, and recommends measuring it with `fio`.

Two places could hold etcd's data, at the same price and under the same ceiling:

- the root disk that comes with a `-diskNN-perf1` flavor. The flavor carries limits of 500
  IOPS and 200 MB/s (`quota:disk_*` in its extra specs). Where that disk lives is not
  documented;
- a Ceph volume of type `CEPH_1_perf1`, described by the platform as tolerant to disk, server
  and rack failure, with the same 500 IOPS and 200 MB/s.

At public list prices, `a2-ram4-disk0` plus a 20 GiB volume costs 0.01045 CHF per hour, and
`a2-ram4-disk20-perf1` costs 0.01043. Price does not choose between them; latency might.

## The measurement

On 2026-10-01, between 09:30 and 10:05 UTC, the command from etcd's guide ran three times on
each support, one pass at a time so that no two runs shared the storage:
`fio --rw=write --ioengine=sync --fdatasync=1 --size=22m --bs=2300`. Each pass is 10,029 writes,
each followed by `fdatasync`. Latencies of `fdatasync`, in milliseconds, as the range over the
three passes:

| Support | p50 | p99 | p99.9 | max |
|---|---|---|---|---|
| Root disk, node 1 | 4.55 – 4.69 | 18.22 – 23.99 | 38 – 66 | 217 – 639 |
| Root disk, node 2 | 4.55 – 4.82 | 10.29 – 13.17 | 24 – 41 | 103 – 201 |
| Root disk, node 3 | 4.23 – 4.36 | 14.75 – 22.15 | 34 – 85 | 85 – 266 |
| Ceph volume, on node 1 | 4.62 – 4.69 | 10.03 – 12.78 | 20 – 27 | 32 – 40 |

- **Neither support meets the guideline.** The volume comes closest.
- **The median is the same everywhere, about 4.5 ms.** A local NVMe disk answers well under a
  millisecond, so the root disk probably goes through network storage as well. That is an
  inference, not something the platform states.
- **The difference is in the tail.** The volume never went above 40 ms. The root disk reached
  639 ms on node 1.
- **The cause of that tail is not isolated.** The root disk also carries the operating system,
  and it is mounted with `discard`, which issues a TRIM with each deletion. The volume was
  empty and mounted without it.

The margin of error is wide: three passes per support, a single time window, a volume measured
on one node only, and root disks measured while the system ran.

## Decision

Keep etcd's data on the root disk, knowingly below the guideline, and add no volume for now.

The gap to the guideline is measured; its cause, and whether it matters to a cluster this size,
are not. The cluster does not run yet. The step that installs it is where leader elections and
slow writes would show, and where the decision is checked.

## Consequences

- **The cluster step has to plan for slow disks.** k3s passes settings to etcd
  (`--etcd-arg`). The heartbeat interval and election timeout default to 100 ms and 1 s; the
  worst write seen here took 639 ms. etcd's warnings about slow `fdatasync` and any leader
  election are the signals to watch.
- **The fallback is known and measured.** A dedicated Ceph volume per node, mounted on etcd's
  data directory, had a tail sixteen times shorter. It would cost three volumes, about 0.06 CHF
  a day each for 20 GiB, an attachment per node, and a mount in cloud-init by
  `/dev/disk/by-id`: Nova announced the test volume as `/dev/sdc`, and the guest saw it as
  `/dev/sdb`.
- **No volume means nothing to orphan.** The nodes stay disposable as a whole.

## When to revisit

At the first leader election or slow-write warning that the timing settings do not absorb, or
before the cluster carries anything it cannot lose. Two experiments were left undone and would
come first: running the same test on a root disk remounted without `discard`, and asking for
the `-perf2` tier, which the platform offers on request at 1,000 IOPS and 400 MB/s.

## Alternatives considered

**A dedicated volume for etcd, now.** Measured, and better in the tail. Rejected for now: it adds
three volumes and their wiring for a gain not yet shown to matter, while the root disk's own
tail has an untested suspect in `discard`.

**Booting from a volume** (`-disk0` flavors). Not measured as a root disk; it would put the
operating system's own writes on the same volume as etcd. It also spends a volume per node and
turns every image into a volume at each creation.

**The `-perf2` tier.** Available only on request, and not tested. Nothing shows that it lowers
the median, which is where the disks already agree.

## Amendment — 2026-10-05

The cluster step installed etcd 3.6.14, embedded in k3s, with its timing settings unchanged: a
100 ms heartbeat and a 1 s election timeout. etcd serves its own metrics on `127.0.0.1:2381` on
every server, with or without k3s's `etcd-expose-metrics`, which only adds the node's address
(k3s `pkg/etcd/etcd.go`). Among them are the duration of its write-ahead log's `fdatasync` and
the count of leader changes. The decision is
checked at the observability step, where Prometheus collects those metrics over time.
