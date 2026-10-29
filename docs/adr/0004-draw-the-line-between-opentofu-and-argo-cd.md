# 4. OpenTofu outside the cluster, Argo CD inside

## Status

Accepted — 2026-10-11

## Context

Everything in the cluster was installed from the workstation, by a runbook replayed after every
rebuild, and nothing held it afterwards. A change made by hand stayed. Each resource needs one
owner, or two tools fight over it.

## Decision

| Owner | Runs | Owns |
|---|---|---|
| OpenTofu | From the workstation | Everything in OpenStack, and k3s's settings through the user data |
| Helm | From the workstation | Argo CD alone |
| Argo CD | In the cluster | Every other object in it, from [`cluster/apps/`](../../cluster/apps/) |

- **An app of apps.** One root `Application`, applied once, reads `cluster/apps/`, where each file
  is an `Application`: a chart at a pinned version, with its values from this repository.
- **Automated sync, pruning and self-healing everywhere**, the root included. Sync waves set the
  order. Argo CD polls GitHub; it is not exposed.
- **OpenTofu never reaches into the cluster**: no `helm` or `kubernetes` provider.
- **Four values are written on both sides** and must change together: the stable address, the
  node ports, the subnet and the domain.

Two exceptions:

- **Prometheus's Cinder volume** is created by the CSI driver, outside the state. `make down`
  deletes it after the destroy, by the mark the driver sets.
- **Four Secrets come from the workstation**, created by `make up` before Argo CD: two
  credentials and two passwords, never in Git.

## Consequences

- Git is the only way to change what runs: a manual change to a declared field is undone, and
  going back is a `git revert`.
- Argo CD's own values apply only when Helm runs again.
- A pushed change takes up to three minutes to land.

## Alternatives considered

- **Keep installing from the workstation**: nothing would reconcile the cluster with Git.
- **Flux**: the same work; Argo CD's interface served every check.
- **Argo CD managing itself**: a wrong value could break the tool meant to repair it.
- **OpenTofu installing Argo CD**: every apply would need the tunnel open, and the cluster's
  credentials would end up in the state.
- **k3s installing Argo CD at boot**: its version would join the user data, and any change would
  replace the three servers.
