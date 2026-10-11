# Cluster services

How the services inside the cluster come to run: Argo CD, installed with Helm, then an app of
apps that brings Traefik, cert-manager with its two issuers, and the demo application from this
repository. On a fresh cluster, after a destroy and apply, this runbook is played from the top;
after that, every change goes through Git. Why it works this way is recorded in
[ADR 0016](../adr/0016-deliver-the-cluster-services-with-argo-cd.md) and
[ADR 0017](../adr/0017-draw-the-line-between-opentofu-and-argo-cd.md).

## What it takes

- The tunnel to the API open, as in the [cluster access runbook](cluster-access.md).
- Helm and `kubectl` on the workstation.
- The infrastructure applied: the load balancer, its stable public address, and the DNS record
  `*.volta.koveolabs.com` pointing at that address. None of them changes across a cycle.
- The repository pushed: Argo CD reads `main` on GitHub, not the workstation's copy.

Commands run from the root of the repository, with the cluster's kubeconfig:

```sh
export KUBECONFIG=~/.kube/volta-lab.yaml
```

## 1. Argo CD

```sh
helm upgrade --install argocd oci://ghcr.io/argoproj/argo-helm/argo-cd --version 10.10.2 \
  -n argocd --create-namespace -f cluster/argocd/values.yaml
kubectl -n argocd get pods
```

- **Every pod is expected `Running`.** On 2026-10-11, they were all ready a minute after the
  installation.
- **The release is named `argocd`**, which names its objects: `argocd-server`,
  `argocd-repo-server`, `argocd-application-controller`.
- **It is the only Helm release on the cluster.** The same command upgrades Argo CD.

## 2. The root Application

```sh
kubectl apply -f cluster/argocd/root.yaml
```

- **It is the only `Application` applied by hand.** It reads [`cluster/apps/`](../../cluster/apps/)
  on `main`, where each file is an `Application`, and creates them.
- **The root does not sync by itself.** Sync it from Argo CD's interface (section 3): open
  `app-of-apps` and press Sync. Its children then sync on their own. A file added to or removed
  from `cluster/apps/` also waits for a sync of the root.
- **The children come in sync waves**: Traefik and cert-manager first, then the issuers, once
  cert-manager's webhook answers, then the demo, whose `Ingress` needs Traefik's `Middleware`
  type and an issuer.

```sh
kubectl -n argocd get applications
```

The five `Application` resources are expected `Synced` and `Healthy`. On 2026-10-11, the demo's
production certificate was `Ready` two minutes after the root's sync started.

## 3. Argo CD's interface

```sh
kubectl -n argocd port-forward svc/argocd-server 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

- **The port-forward runs in a terminal of its own**, left open. The interface is then on
  `https://localhost:8080`, behind a self-signed certificate the browser warns about.
- **The account is `admin`**, with the password the second command prints. It never goes into the
  repository, a conversation or a ticket. Each fresh cluster generates a new one.
- **Argo CD is not exposed on the Internet.** The port-forward goes through the tunnel: when the
  tunnel drops, so does the interface. Argo CD itself keeps working; it runs in the cluster and
  reads GitHub on its own.

## 4. Checks

With `OS_CLOUD` set:

```sh
openstack loadbalancer status show volta-lab-ingress
```

Every member is expected `ONLINE`. Read it a few minutes after Traefik is up: right after a
health monitor is created, its members show `ONLINE` for about a minute, whether anything listens
or not.

```sh
curl -sv https://demo.volta.koveolabs.com/
```

- **The certificate verifies without `-k`**, issued by Let's Encrypt for
  `demo.volta.koveolabs.com`.
- **`X-Real-Ip` is the workstation's public address.** whoami echoes the headers it receives:
  this one shows that the client address crossed the load balancer.
- **`http://demo.volta.koveolabs.com/` answers a 301** to the same path over HTTPS.

## Changing a component

- **Edit the files under `cluster/`, commit, push to `main`.** Argo CD polls the repository every
  two to three minutes and applies what changed. Nothing runs from the workstation.
- **No `helm` and no `kubectl apply` on a component Argo CD manages.** A change made by hand to a
  field the manifest declares is undone. A field the manifest leaves out is not watched at all.
- **Going back is a `git revert`, pushed.** The interface's Rollback is unavailable while
  automated sync is on.
- **Removing a file from `cluster/apps/` removes the component**, and every object it created.
  cert-manager's CRDs stay, and the certificates with them; Traefik's go, and every `Middleware`
  with them.

## Upgrades

- **A chart**: its version is the chart source's `targetRevision` in `cluster/apps/`. Review the
  values against the new chart before pushing:

  ```sh
  helm show values oci://ghcr.io/traefik/helm/traefik --version <version>
  ```

  A values file with an unknown key is refused by both charts' schemas, but a key written twice
  is not: Helm keeps the last one silently. The `check-yaml` hook catches the second case at
  commit.
- **Argo CD**: the command of section 1, with the new `--version`. Its values file is applied only
  then; Argo CD does not reconcile it.

## Certificates and their limit

The demo asks the production issuer. Let's Encrypt issues at most five certificates per week for
the same set of names, and every fresh cluster asks for a new one. To experiment, point the demo's
`Ingress` at `letsencrypt-staging` (annotation `cert-manager.io/cluster-issuer`) and push;
cert-manager issues a new certificate whenever the issuer changes, and the staging one is not
trusted by browsers.
