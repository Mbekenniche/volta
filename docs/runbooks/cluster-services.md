# Cluster services

How to install the services that make the cluster reachable over HTTPS: Traefik, cert-manager
with its two issuers, and the demo app. They are installed by hand from the workstation, with
Helm and `kubectl`, from the values and manifests under `cluster/`. On a fresh cluster, after a
destroy and apply, this runbook is played from the top.

## What it takes

- The tunnel to the API open, as in the [cluster access runbook](cluster-access.md).
- Helm and `kubectl` on the workstation.
- The infrastructure applied: the load balancer, its stable public address, and the DNS record
  `*.volta.koveolabs.com` pointing at that address. None of them changes across a cycle.

Commands run from the root of the repository, with the cluster's kubeconfig:

```sh
export KUBECONFIG=~/.kube/volta-lab.yaml
```

## 1. Traefik

```sh
helm upgrade --install traefik oci://ghcr.io/traefik/helm/traefik --version 41.6.1 \
  -n traefik --create-namespace -f cluster/traefik/values.yaml
kubectl -n traefik rollout status ds/traefik
```

One Traefik per server, behind the NodePorts 30080 and 30443 that the load balancer targets.
Traefik comes first because the demo needs what its chart brings: the `traefik` IngressClass and
the `Middleware` resource type.

Then check that the load balancer sees it, with `OS_CLOUD` set:

```sh
openstack loadbalancer status show volta-lab-ingress
```

Every member is expected `ONLINE`. Read it a few minutes after Traefik is up: right after a
health monitor is created, its members show `ONLINE` for about a minute, whether anything
listens or not.

## 2. cert-manager and the issuers

```sh
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager --version v1.21.2 \
  -n cert-manager --create-namespace -f cluster/cert-manager/values.yaml
kubectl -n cert-manager rollout status deploy/cert-manager-webhook
kubectl apply -f cluster/cert-manager/cluster-issuers.yaml
kubectl get clusterissuer
```

- **Wait for the webhook.** It validates every cert-manager resource; the issuers sent before it
  answers are refused.
- **Both issuers are expected `Ready`**: each has registered an ACME account with Let's Encrypt,
  whose key cert-manager keeps in a Secret of the `cert-manager` namespace. A fresh cluster
  registers new accounts.

## 3. The demo app

```sh
kubectl apply -f cluster/demo/whoami.yaml
kubectl -n demo get certificate whoami-tls
```

The certificate is expected `Ready` within a minute. Then, from the workstation:

```sh
curl -sv https://demo.volta.koveolabs.com/
```

- **The certificate verifies without `-k`**, issued by Let's Encrypt for
  `demo.volta.koveolabs.com`.
- **`X-Real-Ip` is the workstation's public address.** whoami echoes the headers it receives:
  this one shows that the client address crossed the load balancer.
- **`http://demo.volta.koveolabs.com/` answers a 301** to the same path over HTTPS.

## Certificates and their limit

The demo asks the production issuer. Let's Encrypt issues at most five certificates per week for
the same set of names, and every fresh cluster asks for a new one. To experiment, point the
Ingress at `letsencrypt-staging` (annotation `cert-manager.io/cluster-issuer`) and apply again;
cert-manager issues a new certificate whenever the issuer changes, and the staging one is not
trusted by browsers.

## Upgrades

The same commands, with the new `--version` and the values reviewed against the new chart:

```sh
helm show values oci://ghcr.io/traefik/helm/traefik --version <version>
```

A values file with an unknown key is refused by both charts' schemas, but a key written twice is
not: Helm keeps the last one silently. The `check-yaml` hook catches the second case at commit.
