# Architecture decisions

The five decisions that shape the platform, each with the options it rejected.

| Decision | Why | Record |
|---|---|---|
| Self-managed k3s rather than managed Kubernetes | The cluster's bootstrap is what this repository shows | [ADR 1](0001-run-a-self-managed-k3s-cluster.md) |
| State in Swift, encrypted, without a lock | Swift refuses the conditional write a lock needs; one operator and saved plans stand in | [ADR 2](0002-store-the-state-in-swift-without-a-lock.md) |
| A bastion as the only way in | No node has a public address, and the exposed machine is not a member of the cluster | [ADR 3](0003-reach-the-nodes-through-a-bastion.md) |
| OpenTofu outside the cluster, Argo CD inside | Every resource has one owner; Git is the way to change what runs | [ADR 4](0004-draw-the-line-between-opentofu-and-argo-cd.md) |
| Build from the workstation, check in CI | Any S3 key is worth the whole project, so the CI checks and holds no secret | [ADR 5](0005-build-from-the-workstation-and-check-in-ci.md) |
