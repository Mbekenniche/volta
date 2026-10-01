# 11. Reach the nodes through a dedicated bastion

## Status

Accepted — 2026-10-01

## Context

[ADR 0004](0004-place-nodes-on-a-private-network.md) gives the nodes private addresses only, and
a floating IP "only where the platform needs an entry point". This step needs one: the nodes
have to be reached over SSH to be checked, and the cluster step will need to reach them again.

Where that entry point sits matters more once the instances are seen from the inside. On this
platform, the user data an instance was created with stays readable from within it, two ways:
on a config drive that the platform attaches to every instance, requested or not, and from the
metadata service, which answers `/openstack/latest/user_data` over HTTP through the router. The
cluster step will hand the nodes a token to join the cluster.

## Decision

Reach the nodes through a dedicated instance, `volta-lab-bastion`, which holds the only public
address of the platform and has a security group of its own.

- **The bastion** runs the pinned image on `a1-ram2-disk20-perf1`, the smallest flavor with a
  local disk, with the nodes' keypair and in no particular zone. Its cloud-init lives in its own
  file, so that the cluster bootstrap added to the nodes' file does not replace it.
- **The floating IP** is a resource of its own, associated with the bastion's port.
- **The bastion's group** admits SSH and ICMP from the administrator's address. It may open SSH
  to the cluster's group, resolve names on the subnet, and reach HTTP and NTP. It may not open
  HTTPS.
- **The cluster's group** admits SSH from the bastion's group only. Its three rules scoped to
  the administrator's address, for SSH, ICMP and the Kubernetes API, are removed: with no public
  address on any node, nothing from the internet could reach them.
- **Access goes through `ProxyJump`.** The SSH session to a node is encrypted end to end
  between the workstation and the node, and the bastion only relays it. The private key never
  leaves the workstation, agent forwarding is off, and host keys are checked against the
  instances' console logs. See the [node access runbook](../runbooks/node-access.md).

Why a separate machine rather than a floating IP on one of the nodes:

1. **No node has a public address**, and the cluster's group admits nothing from the internet.
2. **The exposed machine is not a member of the cluster.** On a node, the entry point would also
   be an etcd member, serve the Kubernetes API and the kubelet, and keep the join token in its
   user data. Taking the bastion gives an SSH relay, not a place in the cluster.
3. **The three nodes stay identical.** None of them is the one with the door.

## Consequences

Checked from inside the instances on 2026-10-01. After a full destroy and apply the same day,
SSH to every instance and the bastion's isolation from port 10250 were checked again.

| From | To | Result |
|---|---|---|
| Workstation | a node, without the bastion | times out |
| Bastion | a node, TCP 22 | open |
| Bastion | a node, TCP 10250 and 6443 | time out |
| Node | another node, TCP 10250 and 2379 | refused: allowed by the group, nothing listens yet |
| Node | the bastion, TCP 22 | times out |
| Bastion | the internet, TCP 443 | times out |

- **A compromised node cannot climb back to the bastion**, and the bastion cannot reach etcd,
  the kubelet or the API.
- **The bastion needs no HTTPS to stay patched.** Ubuntu's packages come over HTTP, from a
  mirror named after the zone and from `security.ubuntu.com`, and the daily update runs
  completed. `snapd` tries `api.snapcraft.io` over HTTPS and times out; nothing here uses it.
- **One more machine to keep up to date**, at 0.0064 CHF an hour.
- **Administration has a single door.** If the bastion goes down, the cluster keeps running but
  cannot be administered until the bastion is recreated, which an apply does.
- **The address changes with each rebuild.** The floating IP is released on destroy, so the
  public address and every host key are new after a cycle: 179.237.94.239 became 179.237.94.97.
  The SSH configuration and the known hosts are rebuilt from the outputs and the console logs.
- **The Kubernetes API is no longer open to the administrator's address.** The cluster step
  chooses how to reach it: a tunnel through the bastion, or the load balancer of the ingress
  step.
- **SSH forwarding must stay enabled on the bastion.** `ProxyJump` opens a `direct-tcpip`
  channel, which `AllowTcpForwarding no` would refuse.

## Alternatives considered

**A floating IP on the first node.** The cheapest option: no extra instance, port or group.
Rejected for the second reason above. It would also have taken an SSH rule between nodes, and
made one node unlike the others.

**A floating IP on every node.** Rejected: three public addresses, and the cluster's group open
to the administrator on each of them, to save one hop.

**No entry point until the load balancer exists.** Rejected: the nodes could not be checked
before the cluster step, and a load balancer is not an SSH entry point.
