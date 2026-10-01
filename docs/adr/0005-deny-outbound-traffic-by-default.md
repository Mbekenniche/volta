# 5. Deny outbound traffic by default

## Status

Accepted — 2026-09-24

## Context

A security group filters both directions, and Neutron fills in the outbound side before anyone
asks. On this platform, a new group comes with two rules: every protocol to every IPv4
destination, and the same for IPv6. That was measured on 2026-09-24 on a probe group created
for the purpose and deleted straight away; the API that would describe this template,
`/v2.0/default-security-group-rules`, answers 404 here. The platform's filter on outbound TCP
port 25 lives only in the project's `default` group. Groups created afterwards do not inherit
it.

Groups on this platform are stateful, and both of this project's report `stateful: true`. The
reply to a connection accepted inbound goes back out without any outbound rule, so outbound
rules govern only the connections a node opens itself: packages and images pulled, names
resolved, clocks set and, once the cluster runs, whatever its workloads call. A pod reaches the
outside through its node's network port, so the node's group applies to the pod as well.

The choice was between keeping that default, and letting the group allow everything, or
deleting it and declaring each flow.

## Decision

Create the cluster's security group with `delete_default_rules = true`, and declare every
outbound flow in the same code as the inbound ones. The group allows, over IPv4 only:

| Flow | Port | Destination | Needed for |
|---|---|---|---|
| DNS | 53/UDP, 53/TCP | anywhere | Name resolution; TCP carries answers too large for UDP |
| HTTP | 80/TCP | anywhere | Package repositories |
| HTTPS | 443/TCP | anywhere | Container registries, release downloads, APIs |
| NTP | 123/UDP | anywhere | Time synchronisation |
| Everything | all | members of the group | Traffic between cluster nodes |

Nothing is allowed over IPv6: the project subnet has none, so there is nothing to open. Each
later step adds the outbound rules its own components need, in the same change as those
components, and nothing is opened ahead of its consumer.

Read back from the raw API after the network step: fourteen rules, six of them outbound, none
for IPv6.

## Consequences

- **An outbound flow exists because someone wrote it down.** The table above is the complete
  outbound policy of the cluster, readable in one file and reviewed like any other change.
  Opening a port is a diff.
- **This narrows exposure; it does not seal it.** HTTPS to the whole internet stays open, and
  it is the port that exfiltration and command-and-control traffic favour. What the policy
  removes is everything else: outbound SSH and SMTP, arbitrary high ports, direct connections
  to databases elsewhere. Reading "egress closed" as "egress controlled" would be a mistake,
  and this record says so.
- **A missing rule looks like a timeout, not a refusal.** A security group drops what it does
  not allow, without answering, so the client waits and gives up. The first question about a
  download that hangs is the outbound list, not the remote service.
- **The policy is per node, not per workload.** Every pod on a node shares the node's
  allowance. Restricting one workload more tightly than another is the job of Kubernetes
  network policies, not of the security group.
- **New needs cost a change first.** Pulling a Git repository over SSH would need port 22;
  over HTTPS it needs nothing new. Sending mail, or reaching a service on a non-standard port,
  starts with a rule.
- **IPv6 is closed outright.** That costs nothing only while the platform is IPv4-only, as
  [ADR 0004](0004-place-nodes-on-a-private-network.md) makes it. Adding IPv6 means declaring
  its outbound flows too.

## Alternatives considered

**Keep Neutron's default outbound rules.** Rejected. Everything would work at the first
attempt, including the flows nobody chose: on this platform a new group allows all outbound
traffic over IPv4 and IPv6, SMTP included, although the platform filters it in its own
`default` group. The outbound policy would exist only as an absence, and nobody reviews an
absence.

**Rely on the project's `default` group.** Rejected. Its outbound policy is the provider's,
everything but TCP port 25, and it applies to every port the project creates without naming a
group. Tightening it for the cluster would change it for everything else.

**Restrict HTTPS to known destinations.** Rejected. Security group rules match address
prefixes, not host names, and the services this platform pulls from — registries, release
hosting, certificate authorities — sit behind content delivery networks whose ranges are wide
and change without notice. The list would be long, stale, and would fail as timeouts.
Filtering by name is the job of an egress proxy, which is more infrastructure than this
project needs today.

## Amendment — 2026-10-01

The compute step added a second group and checked the first from inside the instances.

**A group for the bastion.** The bastion of [ADR 0011](0011-reach-the-nodes-through-a-bastion.md)
does not join the cluster's group, whose rule allowing everything between members would open
etcd, the kubelet and the Kubernetes API to it. Its own group follows the same rule as this
record, every flow written down:

| Flow | Port | Peer | Needed for |
|---|---|---|---|
| SSH, ICMP in | 22/TCP, ICMP | the administrator's address | The only way into the platform |
| SSH out | 22/TCP | members of the cluster's group | Reaching the nodes |
| DNS | 53/UDP, 53/TCP | the subnet | The resolvers on the DHCP ports, nothing beyond |
| HTTP | 80/TCP | anywhere | Ubuntu's package repositories |
| NTP | 123/UDP | anywhere | Time synchronisation |

There is no HTTPS. Ubuntu's packages come over HTTP, from a mirror named after the zone
(`dc3-a-04.clouds.archive.ubuntu.com`) and from `security.ubuntu.com`, and the daily update runs
completed without it. The only process that asked for HTTPS was `snapd`, which nothing here
uses.

**The cluster's group lost its rules for the administrator.** SSH, ICMP and the Kubernetes API
were open to the administrator's address. With no public address on any node, they led nowhere
and were removed; SSH is now admitted from the bastion's group only.

**What the outbound rules actually serve.** cloud-init does not depend on them: the platform
attaches a config drive to every instance, and cloud-init reads its data from there. The
metadata service answers too, over the HTTP rule, through the router: any process on a node can
read the node's user data from it. Nothing secret goes into user data for that reason.

**Rules name their peer group.** A rule with neither a prefix nor a group means any address to
Neutron, so a misspelt group name would have opened the rule silently. Preconditions now stop
the plan on an unknown group name, and on any rule that sets both or neither.
