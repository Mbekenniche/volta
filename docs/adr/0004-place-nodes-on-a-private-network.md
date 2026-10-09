# 4. Place the cluster nodes on a private network behind a router

## Status

Accepted — 2026-09-24

## Context

This platform offers two ways to connect an instance, and the difference between them is
visible in the API before anything is built.

The first is `ext-net1`. It belongs to another project, its description in the API reads
"Public shared network", and it is shared with this project without being external, so no
router can take its gateway there. It carries seventeen IPv4 `/24` subnets in address space
registered to Infomaniak at the RIPE NCC, and one IPv6 `/64`. On 2026-09-24, a probe port
created on it by this project was accepted, received one public IPv4 address and one public
IPv6 address, counted against the project's port quota, and was given the project's `default`
security group, having asked for none. It was deleted straight away.

The second is the usual OpenStack layout: a network owned by the project, with private
addressing, and a router whose gateway sits on the external network `ext-floating1`. Whatever
must be reachable from outside gets a floating IP, a one-to-one translation from a public
address to a private one. It is the model Azure applies to every virtual machine: the instance
only ever sees its private address, and the platform translates. Built in the network step,
this layout costs three of the project's twenty ports before any instance exists, two DHCP
ports and the router's interface. The router's own gateway port does not count.

The shared network is the cheaper of the two, and it comes with IPv6. The question is whether
that saving is worth what it gives away.

## Decision

Attach the cluster nodes to a project network, `volta-lab-network`, with the subnet
`10.10.0.0/24`, routed to `ext-floating1` by a router that translates outbound traffic. No node
receives a public address when it is created. A floating IP is associated only where the
platform needs an entry point, and each one is added by the step that needs it.

## Consequences

- **Exposure is a decision, not a default.** A node that holds only an address in
  `10.10.0.0/24` cannot be reached from the internet at all, because private ranges are not
  routed there. Its security group is a second barrier rather than the only one.
- **Cluster traffic stays on the project's own network.** etcd, the kubelet API and the Flannel
  overlay run between private addresses, on a network that is not shared with any other project
  (`shared: false`), rather than between public addresses on one that is.
- **The addressing plan belongs to the project.** The subnet range was chosen to stay clear of
  the ranges k3s gives to pods and services by default, `10.42.0.0/16` and `10.43.0.0/16`. On
  `ext-net1`, node addresses would be whatever the platform allocates from its public pool.
- **Outbound traffic leaves through one address.** The router translates source addresses
  (`enable_snat: true`) through a single address on `ext-floating1`, so every node without a
  floating IP reaches the internet from the same public address: one entry to add wherever a
  third party filters by source.
- **The router sits on the only path out.** Neutron runs it highly available: its interface on
  the subnet is owned by `network:ha_router_replicated_interface`.
- **Three ports are spent before the first instance.** Whether that matters depends on what the
  load balancer consumes, which the ingress step measures rather than assumes.
- **The platform is IPv4-only.** The project subnet has no IPv6, where `ext-net1` would have
  given each node a public IPv6 address at no cost. Serving anything over IPv6 later means
  adding it on purpose.
- **The decision is contained in the network layer.** Moving to `ext-net1` would replace the
  network, subnet, router and interface with one port per node on the shared network. The
  security group rules would carry over unchanged, since none of them names an address in the
  subnet.

## Alternatives considered

**Nodes attached directly to `ext-net1`.** Rejected. It is the cheapest layout the platform
offers: no router, no DHCP ports of the project's own, three ports saved, and IPv6 included.
It is also the layout in which every node is on the internet from its first boot, over IPv4
and IPv6, with a security group as the only thing between the Kubernetes API and the world,
and the cluster's internal traffic crossing a network the platform itself describes as shared.
The saving is real and small; the exposure is permanent.

**A private network, plus a second interface on `ext-net1` for the nodes that must be
reachable.** Rejected. It keeps internal traffic private, but spends one more port per
reachable node and gives those nodes two interfaces, each with its own gateway: routing
complexity that a floating IP avoids entirely.

**`ext-v6only1`, the shared IPv6-only network.** Rejected. An IPv6-only node cannot reach a
service that publishes no IPv6 address, and some of this platform's dependencies publish none.
On 2026-09-24, `github.com`, `objects.githubusercontent.com` and `ghcr.io` had no AAAA record,
and GitHub is where k3s publishes its releases. Working around that requires NAT64 on the
platform, which was not verified.

## Amendment — 2026-10-01

The compute step added the first entry point, and settled two questions left open above.

- **The platform has one public address, the bastion's.** The nodes have none. The floating IP
  is associated with the port of a dedicated bastion rather than with a node, for the reasons in
  [ADR 0011](0011-reach-the-nodes-through-a-bastion.md). A direct connection from the internet
  to a node's private address times out.
- **A floating IP does not count against the project's ports.** After the step, the project
  uses 7 of its 20 ports: one for each of the four instances, the two DHCP ports and the
  router's interface.
- **Associating a floating IP needs a routed subnet.** The port's subnet has to reach the
  external network through the router, and on an apply from scratch nothing ordered the
  association after the router's interface. The network layer's subnet output now waits for
  that interface, so the association does too, and a destroy removes the association first. A
  full destroy and apply went through on 2026-10-01, in 1 min 56 s and 1 min 05 s.
- **Addresses are drawn at random from the pool.** The nodes got `.17`, `.251` and `.152`, then
  `.66`, `.219` and `.54` after a rebuild. Nothing in the code names an address; whatever needs
  one reads it from the outputs.

## Amendment — 2026-10-09

The ingress step added the second entry point, and measured what the load balancer consumes.

- **The second public address is on no instance.** It is associated with the VIP port of an
  Octavia load balancer, which forwards TCP 80 and 443 to the servers' NodePorts; see
  [ADR 0015](0015-enter-through-an-octavia-load-balancer.md). The nodes still have no public
  address, and the bastion's is no longer the platform's only one.
- **That address survives the cycle.** It is created in the bootstrap stack, outside the
  platform's destroy and apply, so the DNS record that points at it is set once.
- **The load balancer costs one port, its VIP.** Its two amphorae each have a port on the subnet,
  but those belong to another project and do not count: 8 of the 20 ports are in use after the
  step.
