# 19. Back up to Swift with Velero

## Status

Accepted — 2026-10-25

## Context

Almost everything in the cluster comes back from Git: Argo CD recreates it. What does not is
Prometheus's history, on its Cinder volume ([ADR 0018](0018-observe-the-cluster-with-prometheus-on-a-cinder-volume.md)).
A backup that has never been restored proves nothing, so this step ends with a real restore.

What the decision rests on, checked on 2026-10-25:

- **Velero 1.18**, from the `velero` chart 12.2.1, with `velero-plugin-for-aws` v1.14.4, the
  plugin for any S3-compatible storage. By default the chart deploys neither the plugin nor the
  node agent.
- **Two ways to back up a volume.** The file-system backup: an agent on each node reads the
  volume's files and sends them with kopia. Or CSI snapshots moved to object storage, which need
  the `VolumeSnapshot` CRDs and a snapshot controller; k3s ships neither.
- **Velero writes the Kubernetes objects as compressed JSON, unencrypted.** Only volume data
  goes through kopia, encrypted with a repository password. That password defaults to one value
  shared by every installation, and a fresh cluster needs the same one to read the repository.
- **A restore skips every object that already exists**, and Argo CD recreates within seconds
  what is deleted: restored behind its back, the volume would come back empty.
- **An S3 key is worth a Keystone token**, through `/v3/ec2tokens`: it carries the account's
  rights on the whole project, not on one container.

## Decision

Back up what Git cannot recreate, with Velero, to a Swift container that survives every rebuild.

- **Velero, delivered by Argo CD** in sync wave 0, with the AWS plugin and the node agent.
- **One namespace, `monitoring`, with Prometheus's volume**, by file-system backup with kopia.
  **Secrets and cert-manager's `CertificateRequest` objects are excluded.** Secrets would sit in
  Swift readable by anyone who reads the container; the Secrets of a fresh cluster come from the
  workstation, and the chart's own from Argo CD.
- **Every day at 03:00 UTC, kept seven days.**
- **The container, `volta-lab-velero`, belongs to the bootstrap stack**, with the state and the
  stable address: `make down` never touches it.
- **A dedicated S3 key**, created with the account's password and revocable on its own, and **a
  repository password of our own**, set before the first backup. Both live in files on the
  workstation and reach the cluster as Secrets, created by `make up` before Argo CD
  ([ADR 0020](0020-build-from-the-workstation-and-check-in-ci.md)): a Velero that started
  without them would write the default password.
- **No checksum on uploads** (`checksumAlgorithm: ""`). The plugin sends a CRC32 by default,
  which turns each upload into `aws-chunked`, and Swift 2.30.1 refuses that with a 501.

## Consequences

Measured on 2026-10-28, on the loss of the `monitoring` namespace on the running cluster, with
its volume:

| Measure | Value |
|---|---|
| Backup | 2 min 40 s, 134 objects, Prometheus's 3.88 GB volume in 78 s |
| Restore, from the command to Prometheus running | about 3 min, the volume in about 86 s |
| Data lost | everything since the backup used: 31 min that day, up to 24 h with the schedule |
| Memory, Velero / each node agent | 64 MiB / 16 to 18 MiB |

The restored Prometheus answered for data older than the loss: its oldest point dated from
2026-10-22. The procedure is the [restore runbook](../runbooks/restore.md).

- **A restore needs Argo CD's automated sync suspended**, on the root and on the restored
  `Application`, then resumed as soon as the restore has created the volume. Resuming it is also
  what brings back the chart's Secrets, which the backup excludes.
- **cert-manager's requests are not restored.** Restored, they pointed at a private key held in a
  Secret that was not there, stayed pending, and blocked cert-manager; without them, it issues
  new ones.
- **The backups survive a rebuild.** After the cycle of 2026-10-29, the fresh cluster's Velero
  listed the backups taken before it, from the same container.
- **The S3 key in the cluster is worth the account's rights on the project**, the state's
  container included. A project of its own for the backups would limit it; see below.
- **The restore proven is that of a namespace, on a running cluster.**

## Alternatives considered

**The same, with the Secrets.** A rebuild would not need new certificates, but keys and
credentials would sit unencrypted in Swift.

**The whole cluster.** Simple to write, but most of it comes from Git, and restoring it would
fight Argo CD.

**CSI snapshots moved to Swift.** A volume consistent to the instant, where the file-system
backup is consistent as after a power cut, which Prometheus's storage withstands. Rejected for
now: the snapshot CRDs and controller would come first.

**Cinder snapshots alone.** They live in the same project as what they protect: not an off-site
backup.

**Velero installed by Helm, like Argo CD.** Only useful if Velero had to act before Argo CD, to
restore a fresh cluster before it recreates the volume empty.

**A separate OpenStack project for the backups**, with its own account: a stolen key would open
the backups alone, and they would survive the loss of the main project. Cleaner, at the cost of
a project to create and a second provider in the bootstrap stack.
