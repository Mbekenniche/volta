# volta

[![checks](https://github.com/Mbekenniche/volta/actions/workflows/checks.yaml/badge.svg?branch=main)](https://github.com/Mbekenniche/volta/actions/workflows/checks.yaml)

A Kubernetes platform on the Infomaniak Public Cloud (OpenStack), built, destroyed and rebuilt from
code, then instrumented to show what each workload costs in watts, grams of CO2 and money.

## Why

In the cloud, a pod drawing 40 W looks exactly like one drawing 4 W. volta builds a complete
platform from nothing, then adds the signal most platforms lack: energy and carbon per workload,
shown next to what it costs.

Two rules hold the project together:

- **One command builds it, one destroys it.** A step that cannot survive a full rebuild is not done.
- **Every figure states its margin of error.** Inside a virtual machine, power is estimated, never
  read from hardware, and the repository says so.

## Architecture

```mermaid
flowchart TB
    internet([Internet])
    operator([Operator])
    git[("Git repository")]
    tofu["OpenTofu"]

    subgraph cloud["Infomaniak Public Cloud · region dc3-a"]
        fip["Stable floating IP"]
        lb["Octavia load balancer"]
        bastion["Bastion"]
        swift[("Swift / S3 object storage")]

        subgraph k3s["k3s cluster · private network"]
            ingress["Traefik + cert-manager"]
            app["demo workload"]
            argo["Argo CD"]
            obs["Prometheus + Grafana"]
            kepler["Kepler"]
            velero["Velero"]
        end
    end

    internet -->|"*.volta.koveolabs.com"| fip
    fip --> lb
    lb -->|"PROXY protocol"| ingress
    operator -->|SSH| bastion
    bastion -->|"SSH, API tunnel"| k3s
    ingress --> app
    git -.->|desired state| argo
    argo -.->|reconciles| ingress
    argo -.->|reconciles| app
    argo -.->|reconciles| obs
    kepler -->|watts per pod| obs
    velero -->|snapshots| swift
    tofu -->|provisions| cloud
    tofu -->|encrypted state| swift
```

The target, not yet the current state: see the status below.

## Stack

| Layer | Tools |
|---|---|
| Cloud | OpenStack on Infomaniak: Nova, Neutron, Octavia, Cinder, Swift |
| Infrastructure as code | OpenTofu and cloud-init; state in Swift through S3, encrypted |
| Kubernetes | k3s, three servers across three availability zones, embedded etcd |
| Ingress | Octavia load balancer on a stable address, Traefik, cert-manager, Let's Encrypt |
| Delivery | Argo CD as an app of apps, Helm charts |
| Observability | Prometheus, Grafana, etcd's metrics, Prometheus on a Cinder CSI volume |
| Backups | Velero to Swift, volumes copied with kopia, restore proven |
| Lifecycle and CI | `make up` and `make down`; GitHub Actions with no secret, every action pinned to a commit |
| Energy and carbon | Per-pod power estimates, Prometheus rules, Grafana *(planned)* |

## Status

**Phase 1 — the platform**

- [x] Private network, encrypted remote state, three nodes behind a bastion
- [x] k3s from a single `apply`
- [x] HTTPS through an Octavia load balancer: Traefik, cert-manager, Let's Encrypt
- [x] GitOps: Argo CD delivers everything in the cluster from this repository
- [x] Observability: Prometheus and Grafana, etcd's metrics over time
- [x] Backups, proven by a real restore
- [x] One command to build, one to destroy, and CI on every change

**Phase 2 — energy and carbon**

- [ ] Power per pod, a carbon model, dashboards as code, and one optimisation measured before and after

## Build it

From the workstation, with what the [lifecycle runbook](docs/runbooks/lifecycle.md) lists:

```sh
make up     # a plan, a typed yes, the apply, then everything up to the demo over HTTPS
make down   # the main stack and its volumes; the state, the stable address and the backups stay
```

Each phase of `make up` does nothing when its work is already done, so a run that stops is resumed
by running it again. The CI checks every pull request without holding a secret; only the
workstation applies. Why: [ADR 0020](docs/adr/0020-build-from-the-workstation-and-check-in-ci.md).

## A few things that broke

- The OpenStack CLI showed etcd and the Kubernetes API open to the internet; the raw API said
  otherwise. [Read](docs/what-broke.md#a-cli-that-showed-the-clusters-internal-ports-open-to-the-internet)
- Swift refuses the conditional write a state lock needs, so the state has no lock, and the
  repository says what stands in for it. [Read](docs/what-broke.md#a-state-lock-the-platform-cannot-take)
- A firewall rule on the nodes would have lost to k3s's own, depending on which started first.
  [Read](docs/what-broke.md#a-firewall-rule-that-k3s-would-have-outranked)
- Argo CD's self-healing left a manual `scale` in place: the manifest never declared a replica
  count. [Read](docs/what-broke.md#a-self-healing-cluster-that-left-a-manual-change-in-place)
- A rule on `main` saved without its required checks let a red pull request through, and Argo CD
  deployed it. [Read](docs/what-broke.md#a-rule-on-main-that-let-a-red-pull-request-through)
- Octavia refused a health monitor for its type; the type was fine, and the error came from its
  database. [Read](docs/what-broke.md#a-health-monitor-refused-for-a-type-that-was-fine)

[All the stories](docs/what-broke.md)

## Read more

- [Decisions](docs/adr/): 20 ADRs, each with the options it rejected
- [What broke, and how it was fixed](docs/what-broke.md)
- [Known limitations](docs/limitations.md)
- Runbooks: [lifecycle](docs/runbooks/lifecycle.md), [nodes](docs/runbooks/node-access.md),
  [cluster](docs/runbooks/cluster-access.md), [services](docs/runbooks/cluster-services.md),
  [restore](docs/runbooks/restore.md), [remote state](docs/runbooks/remote-state.md)
- [Platform inventory](docs/platform-inventory.md): what the cloud offers, and what it costs

## License

MIT. See [LICENSE](LICENSE).
