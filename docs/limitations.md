# Known limitations

- **Energy figures will be estimates.** No RAPL counters inside a virtual machine: per-pod power
  comes from a model, with its margin of error stated.
- **The state has no lock.** One operator and saved plans stand in; see
  [ADR 2](adr/0002-store-the-state-in-swift-without-a-lock.md).
- **Administration has one door.** If the bastion fails, the cluster runs on but cannot be
  administered until an apply recreates it; see [ADR 3](adr/0003-reach-the-nodes-through-a-bastion.md).
- **etcd's disk is slower than etcd asks for**: 26 to 42 ms at the 99th percentile over four days,
  against 10 ms; see [ADR 1](adr/0001-run-a-self-managed-k3s-cluster.md).
- **Every k3s setting lives in the user data.** Changing one replaces the three servers, and the
  join token is readable from inside each of them.
- **The entry point is not spread across zones.** Both amphorae of the load balancer ran in one
  zone on 2026-10-09.
- **`make down` trusts the state.** What is left is listed after each destroy; see
  [what broke](what-broke.md#a-destroy-that-forgot-half-the-platform).
- **Backups hold one namespace**, `monitoring`. Velero's S3 key is worth the account's rights on
  the whole project.
- **Every fresh cluster takes a production certificate**, five a week at most.
- **The metered cost is incomplete.** CloudKitty rated only part of one node for nine hours: its
  figures are a lower bound; see the [inventory](platform-inventory.md#cost).
- **A rebuild needs GitHub, `ghcr.io`, `quay.io`, `docker.io` and `ecr-public.aws.com`.** A
  running cluster does not.
