# 15. Let Internet traffic in through an Octavia load balancer, on a stable address

## Status

Accepted — 2026-10-09

## Context

[ADR 0014](0014-serve-https-with-traefik-and-cert-manager.md) puts Traefik in the cluster to serve
HTTPS. Traffic from the internet still has to reach it, and the platform's rules leave few doors:
no node has a public address ([ADR 0004](0004-place-nodes-on-a-private-network.md)), and the only
public machine is the bastion, which is not a member of the cluster
([ADR 0011](0011-reach-the-nodes-through-a-bastion.md)).

The platform offers Octavia. On 2026-10-05, its API listed one provider, `amphora` (`octavia`
being a deprecated alias of it), no flavor and no zone, and no limit on this project's load
balancers. The public price list gives 0.0137 CHF an
hour for a load balancer, against 0.00457 for a floating IP.

Two more constraints. The address published in DNS should not change at every destroy and apply,
since the record is set by hand: `koveolabs.com` is served by Infomaniak's nameservers, and
`volta.koveolabs.com` is delegated nowhere. And the applications should see the address of the
client, not the load balancer's.

## Decision

An Octavia load balancer, managed by OpenTofu in an `ingress` module, takes TCP 80 and 443 on a
public address that lives outside the cycle, and hands the connections to Traefik on every
server.

- **The load balancer** sits on the cluster's subnet, with two TCP listeners, 80 and 443. It
  does not read HTTP and does not touch TLS: Traefik terminates it, with cert-manager's
  certificates.
- **Its pools target fixed NodePorts**, 30080 and 30443, on the three servers, with a TCP health
  monitor each. The cluster's security group opens those two ports to the subnet only, where the
  load balancer's own instances, its amphorae, take their addresses.
- **The pools speak the PROXY protocol.** An amphora opens its own connection to the node, so
  the source address Traefik sees is the amphora's. With `PROXY`, each connection starts with a
  header carrying the client's address, which Traefik reads from the subnet only
  (`proxyProtocol.trustedIPs: 10.10.0.0/24`).
- **Traefik runs as a DaemonSet, behind a `NodePort` Service with
  `externalTrafficPolicy: Local`.** One instance per server, and kube-proxy keeps each connection
  on the node it arrived at. With the default policy, it would hand some of them to another
  node's Traefik and rewrite their source address on the way: the header would then come from an
  address Traefik does not trust.
- **The public address is a floating IP created in the bootstrap stack**, `infra/bootstrap/`,
  next to the state's container, with `prevent_destroy`. A destroy of the platform never reaches
  it. The main stack finds it by its tag, `volta-ingress`, and associates it with the load
  balancer's VIP port.
- **One DNS record, set once by hand** in Infomaniak's manager: `*.volta.koveolabs.com`, type
  `A`, to that address.

## Consequences

Checked on 2026-10-06, then on 2026-10-09 after a full destroy and apply:

| Check | Result |
|---|---|
| Load balancer `ACTIVE` | within 1 min 18 s, then 1 min 19 s of its creation |
| Members, once Traefik runs | six `ONLINE`, on both pools |
| `X-Real-Ip` seen by the demo application | the workstation's public address, from two different addresses |
| `http://demo.volta.koveolabs.com/` | 301 to the same path over HTTPS |
| Public address after the cycle | unchanged, `179.237.92.39`, now on the new VIP port |

The two durations are upper bounds: they run from the load balancer's creation to its first
listener, which OpenTofu creates once it has seen the load balancer `ACTIVE`.

- **The first apply of a new load balancer fails on one health monitor.** On both builds, the
  monitor of the 443 pool was refused with `TCP is not a valid option for type`, while the
  identical monitor of the 80 pool went through. A second plan and apply created it. Until the
  cause is found, a fresh build takes two applies.
- **A new monitor reports its members `ONLINE` for about a minute** after it is created, whether
  anything listens or not. Members are read a few minutes after Traefik starts.
- **The load balancer runs on two amphorae**, each with a port on the subnet that carries the VIP
  as an allowed address. On 2026-10-09, both were in `dc3-a-09`, one of the cluster's three
  zones: losing that zone would cost the entry point as well as one etcd member.
- **It costs one of the project's ports**, the VIP's. The amphorae's ports belong to another
  project and do not count: 8 of 20 ports are in use after this step.
- **The stable address is billed even while the platform is destroyed**, 0.00457 CHF an hour.
  The load balancer adds 0.0137 CHF an hour while it exists.
- **The administration path does not change.** The load balancer listens on 80 and 443 only, and
  forwards them to Traefik; SSH and the Kubernetes API stay behind the bastion.
- **The DNS record is outside the code.** It points at an address that survives the cycle, so it
  was set once. Managing it with Designate in the same apply is left to the one-command step.

## Alternatives considered

**cloud-provider-openstack in the cluster**, creating a load balancer for each `LoadBalancer`
Service. Rejected: it needs an OpenStack credential inside the cluster, and the load balancer it
creates is outside OpenTofu's state, where its port on the subnet would stop the destroy of the
network.

**A floating IP on a server, with k3s's ServiceLB.** Rejected: a node with a public address,
which ADR 0004 and ADR 0011 rule out. ServiceLB is disabled
([ADR 0013](0013-install-k3s-from-cloud-init.md)).

**The floating IP in the main stack**, and the DNS record updated after every cycle. Rejected: a
new address at every rebuild, and a manual step each time.

**Designate, with `volta.koveolabs.com` delegated to it.** Fully automatic, but the delegation was
never tested on this platform. Left to the one-command step, which needs it.

**TLS terminated on the load balancer** (`TERMINATED_HTTPS`, certificates in Barbican). Rejected:
the certificates would leave cert-manager's hands, and the load balancer would have to be updated
at every renewal.

**HTTP listeners** rather than TCP. Rejected: the load balancer would parse every request, for no
use, since Traefik routes them.
