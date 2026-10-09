# 14. Serve HTTPS with our own Traefik and certificates from cert-manager

## Status

Accepted — 2026-10-09

## Context

The ingress step makes the cluster's applications reachable over HTTPS on
`*.volta.koveolabs.com`. Inside the cluster, it takes an ingress controller, which terminates TLS
and routes each request to its application, and a source of certificates that renews them
without anyone's help.

The plan named ingress-nginx. On 2026-10-05, its repository, `kubernetes/ingress-nginx`, was
archived: the Kubernetes project has retired it, and its last releases, chart 4.15.1 and
controller 1.15.1, date from 2026-03-19. No fix will follow, security fixes included.

k3s ships its own Traefik, disabled on these servers since the cluster step
([ADR 0013](0013-install-k3s-from-cloud-init.md)). Its settings would live in files on the
servers, which here means in their user data: changing one would replace the three servers.

## Decision

Install Traefik and cert-manager with Helm, from pinned charts, with values kept in this
repository under [`cluster/`](../../cluster/), and keep the copy k3s bundles disabled.

- **Traefik**, chart 41.6.1, Traefik v3.7.13, serves the Kubernetes `Ingress` API, and its
  `traefik` IngressClass is the cluster's default. How traffic reaches it is
  [ADR 0015](0015-enter-through-an-octavia-load-balancer.md).
- **cert-manager**, chart v1.21.2, with its CRDs installed by the chart and kept if the release
  is removed, so that removing it does not delete the certificates.
- **Two cluster issuers, staging and production**, both on Let's Encrypt with the HTTP-01
  challenge, answered through the `traefik` class. Work goes through staging; an application
  switches to production once its setup holds.
- **One certificate per name**, requested by an annotation on the application's `Ingress`
  (`cert-manager.io/cluster-issuer`).
- **No contact email.** Let's Encrypt stopped sending expiry notices on 2025-06-04 and deleted the
  addresses it held, so the field would only publish one in this repository.
- **HTTP is redirected to HTTPS by each application's `Ingress`**, through a Traefik middleware,
  rather than on the whole `web` entry point. The HTTP-01 challenge is served by a separate
  `Ingress` that cert-manager creates, and never meets the redirect.

The commands, and the order they run in, are in the
[cluster services runbook](../runbooks/cluster-services.md).

## Consequences

Measured on the demo application, `traefik/whoami` on `demo.volta.koveolabs.com`; each figure is
one sample, read from the cluster's timestamps to the second:

| Certificate | From | To `Ready` |
|---|---|---|
| Staging, first issuance | `Ingress` created | 25 s |
| Production, after switching the issuer | annotation changed | 24 s |
| Production, on a fresh cluster after a full destroy and apply | `Ingress` created | 35 s |

On the fresh cluster, the 35 s include registering a new ACME account. The production
certificate verifies without `-k`, issued by Let's Encrypt `YR1`.

- **Every fresh cluster asks for a new production certificate.** Let's Encrypt issues at most
  five per week for the same set of names. A cycle spends one; experiments go to staging.
- **No wildcard certificate.** It needs the DNS-01 challenge, and therefore a token for
  Infomaniak's DNS API inside the cluster. One certificate per name needs nothing but port 80.
- **cert-manager's webhook validates every cert-manager resource**, and refuses them all until it
  answers (`failurePolicy: Fail`). The issuers are applied once it is ready.
- **The installation is manual for now.** Helm runs from the workstation, through the tunnel to
  the API; after a cycle, the runbook is played again from the top.
- **The charts' schemas refuse an unknown key, not a duplicated one.** A values file that wrote
  `service:` twice rendered with the first block silently dropped. The `check-yaml` hook refuses
  duplicate keys at commit.

## Alternatives considered

**ingress-nginx.** Rejected: retired, with no security fixes to come.

**The Traefik bundled with k3s.** Rejected: its version follows k3s, and its settings would be
part of the servers' user data, where any change replaces the cluster.

**Traefik with the Gateway API.** The API Kubernetes recommends for what `Ingress` does. Not
chosen at this stage: it adds the Gateway API resources and their wiring in cert-manager, for the
same result on one application. Traefik serves both, so the move stays open.

**Envoy Gateway.** Built for the Gateway API, with more components to run. Rejected for the same
reason.

**A wildcard certificate through DNS-01.** Rejected above: a DNS API token in the cluster, to
save one certificate per application.
