# 16. Deliver the cluster's services with Argo CD, as an app of apps

## Status

Accepted — 2026-10-11

## Context

After the ingress step, Traefik, cert-manager, its issuers and the demo application were
installed from the workstation, with Helm and `kubectl`, by a runbook replayed after every
rebuild. Nothing held them afterwards: a change made by hand stayed, and the repository described
the cluster without enforcing it.

GitOps moves that work into the cluster. A controller reads the desired state from Git and
converges the cluster towards it, continuously. This step brings one, and the services of the
ingress step become its first charge.

What the decision rests on, checked on 2026-10-09:

- **Argo CD v3.5.4** was current, published by the `argo-cd` chart 10.10.2 as an OCI artifact,
  `oci://ghcr.io/argoproj/argo-helm/argo-cd`.
- **No credentials are needed.** This repository is public, and Argo CD reads a public Git
  repository over HTTPS with nothing configured. It also reads a public Helm chart from an OCI
  registry without a declared repository, when `repoURL` carries no scheme (`ghcr.io/traefik/helm`)
  and the chart is named: stated in its documentation, and visible in its code
  (`IsHelmOciRepo`).
- **An `Application` has no health of its own** since Argo CD 1.8. A parent that orders its
  children in sync waves does not wait for them to be healthy unless that health check is
  restored, as a Lua script in the `argocd-cm` ConfigMap; the documentation gives it.

## Decision

Install Argo CD with Helm, then let it deliver everything else in the cluster from this
repository, through an app of apps.

- **Argo CD 3.5.4, from the `argo-cd` chart 10.10.2**, installed by Helm from the workstation
  with the values in [`cluster/argocd/values.yaml`](../../cluster/argocd/values.yaml). Dex and
  the notifications controller are disabled: no single sign-on, no alerts. The health check of
  `Application` resources is restored.
- **Argo CD does not manage itself.** Helm installs it and upgrades it, with the same command.
- **An app of apps.** A root `Application`, [`cluster/argocd/root.yaml`](../../cluster/argocd/root.yaml),
  is applied by hand once per cluster. It reads [`cluster/apps/`](../../cluster/apps/), where each
  file is an `Application`: Traefik, cert-manager, the issuers and the demo.
- **Charts from their registries, values from this repository.** Each chart's `Application` has
  two sources: the chart itself, at a pinned version, from its OCI registry; and this repository,
  as `ref: values`, which lends its files to the first. The values files of the ingress step serve
  unchanged, and a local `helm template` reads the same ones.
- **Automated sync, with pruning, self-healing and retries**, on every child. What leaves Git
  leaves the cluster, a change made by hand to what a manifest declares is undone, and a sync that
  fails is retried.
- **Sync waves set the order.** Traefik and cert-manager come first, in wave 0. The issuers follow
  in wave 1, once the webhook that validates them answers. The demo comes last, in wave 2: its
  `Ingress` needs the `Middleware` type that Traefik's chart brings, and an issuer.
- **Argo CD is not exposed.** Its interface is reached with `kubectl port-forward`, through the
  tunnel to the API ([ADR 0011](0011-reach-the-nodes-through-a-bastion.md)). Without a webhook from
  GitHub, Argo CD polls the repository: every 120 s, plus up to 60 s of jitter, by default.

The commands are in the [cluster services runbook](../runbooks/cluster-services.md). Where Argo
CD's territory ends is [ADR 0017](0017-draw-the-line-between-opentofu-and-argo-cd.md).

## Consequences

Measured on 2026-10-11, on a fresh cluster after a full destroy and apply; one sample, read from
the cluster's timestamps to the second:

| Step | Time |
|---|---|
| Argo CD ready, from the Helm installation | 60 s |
| Wave 0 healthy (cert-manager, Traefik), from the start of the root's sync | 26 s |
| Issuers healthy | 28 s |
| Demo healthy | 33 s |
| Demo's production certificate `Ready` | 2 min 04 s |

The waves held: the issuers were created at the second the last Traefik pod turned ready, after
cert-manager was healthy. Ten minutes after the sync, Argo CD's five pods used 309 MiB together,
221 MiB of them for the application controller (one reading of `kubectl top`).

- **Git is the way to change a component.** A change made by hand to a field the manifest
  declares is undone. The interface's Rollback is unavailable while automated sync is on; going
  back is a `git revert`, pushed.
- **Only what the manifest declares is enforced.** A field it leaves out is not drift: the demo
  scaled by hand stayed scaled until its manifest declared a replica count. Argo CD's own best
  practices leave `replicas` out of Git on purpose when an autoscaler owns it.
- **Helm no longer sees the components.** `helm list` shows Argo CD alone: Argo CD renders the
  charts with `helm template`, applies the result itself, and tracks each object with an
  annotation, `argocd.argoproj.io/tracking-id`.
- **Argo CD's own values are not reconciled.** A change to `cluster/argocd/values.yaml` does
  nothing until Helm runs again. Git and the cluster can disagree there without anything saying
  so; that is the price of not letting Argo CD manage itself.
- **A pushed change takes up to three minutes to arrive**, the polling interval.
- **Removing an `Application` removes what it created**, through its finalizer. cert-manager's
  CRDs survive: Argo CD honours their `helm.sh/resource-policy: keep` as `Delete=false`, so the
  certificates would too. Traefik's CRDs carry nothing of the kind, and every `Middleware` would
  go with them.
- **The cluster no longer needs the workstation to stay as declared.** Argo CD pulls from GitHub
  over HTTPS; nothing travels from the workstation to the cluster for a change to land. The
  workstation is needed for the bootstrap and for the interface.

## Alternatives considered

**Keep installing from the workstation**, with the runbook or Helmfile. Rejected: nothing would
reconcile the cluster with the repository, and a rebuild would still mean replaying commands.

**Flux.** It does the same work, with controllers and no interface of its own. The plan named
Argo CD from the start; its interface, which shows every object of an `Application` and its
health, served every check of this step.

**An ApplicationSet**, generating the `Application` resources from a template. Not chosen: the
four differ in shape, two charts and two directories, and do not share one template.

**Values inside each `Application`** (`helm.valuesObject`). One source instead of two, but the
values would leave their files, and a local `helm template` would no longer read them.

**Argo CD managing itself**, through an `Application` on its own chart. Rejected: a wrong value
could break the tool meant to repair it, and the version would be written in two places, the
bootstrap command and the `Application`.

**Exposing Argo CD**, through Traefik, filtered on the administrator's address. Rejected: Argo CD
can create anything in the cluster, and its interface would put that power behind a login form,
a second door next to the bastion. It would have allowed a webhook from GitHub.

**OpenTofu installing Argo CD.** Rejected; see [ADR 0017](0017-draw-the-line-between-opentofu-and-argo-cd.md).
