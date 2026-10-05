# 12. Pass the join token in user data, and keep pods away from the metadata service

## Status

Accepted — 2026-10-05

## Context

Every k3s server needs the same token to join the cluster, and that token admits a machine as a
server: in effect, administrative access to etcd. The cluster is meant to form from a single
`apply`, with no step in between, so each server has to find the token on its own at first boot.

[ADR 0011](0011-reach-the-nodes-through-a-bastion.md) found that user data stays readable from
inside an instance, two ways: on the config drive the platform attaches to every instance, which
only root can mount, and from the metadata service, which answers `/openstack/latest/user_data`
over HTTP, through the router, to any process. Pods on a node reach the same address: their
traffic to anything outside the cluster is forwarded by the node.

## Decision

OpenTofu generates the token, and every server receives it in its user data. Each server keeps
its pods away from the metadata service with a firewall table of its own.

- **The token** is a `random_password` of 48 alphanumeric characters, so that it needs no
  quoting in YAML. cloud-init writes it into `/etc/rancher/k3s/config.yaml`, mode 0600, owned by
  root. It also sits in the state, with its bcrypt hash; the state is encrypted
  ([ADR 0007](0007-encrypt-the-state-and-plans.md)).
- **The table**, `inet pod_metadata_block`, holds one base chain on the `forward` hook, at
  priority `filter - 10`, and one rule: traffic from the pod network to `169.254.169.254` is
  dropped. The pod network is one variable, written both into k3s's `cluster-cidr` and into that
  rule, so the two cannot drift apart.
- **A systemd unit loads it**, from a file of its own, before `k3s.service`, at every boot. The
  file declares the table, deletes it and declares it again, so loading it twice leaves a single
  rule. `nftables.service` is not used: its configuration starts with `flush ruleset`, which
  would also clear the rules k3s writes through the same `nf_tables` backend.

Why a table of its own rather than a rule in the node's `FORWARD` chain: k3s manages that chain.
Its network policy controller, an embedded kube-router, creates a firewall chain for every pod on
the node, even when no NetworkPolicy exists, marks the traffic that passes it, and inserts into
`FORWARD`, after its own rules, an `ACCEPT` for that mark. At every sync it also moves its own jump
back to the top of the chain (k3s-io/kube-router `v2.6.3-k3s1`, `pkg/controllers/netpol`,
`ensureTopLevelChains` and `ensureExplicitAccept`). A rule written there by the node would land
above or below that `ACCEPT` depending on which started first. In a table of its own, the rule
does not depend on that order: an `accept` ends the evaluation of the base chain that issues it
only, while a `drop` is final, and k3s does not touch a table it did not create.

## Consequences

Checked on the three servers on 2026-10-02, and on one of them after a full rebuild on
2026-10-05: the token file and `config.yaml` are mode 0600 and owned by root, the unit is active
and enabled, and the table is loaded with its rule.

- **Root on a server can read the token anyway.** k3s keeps it in
  `/var/lib/rancher/k3s/server/token`, mode 0600, and the config drive opens to root only. The
  table closes the one path that did not need root.
- **Processes on the node, and pods on the host network, keep access to the metadata service.**
  Their traffic leaves from the node's own address, not from the pod network.
- **Whoever can read the state can admit a server.** That is what the state's encryption is for.
- **Changing the pod network replaces the servers**, since it is part of their user data.
- **The token's generator comes from OpenTofu's registry.** `hashicorp/random` 3.9.1 is served
  from OpenTofu's own build of the provider (`github.com/opentofu/terraform-provider-random`),
  signed with OpenTofu's key `0C0AF313E5FD9F80`. The hashes in the lock file match that build,
  not HashiCorp's release checksums.

## Alternatives considered

**The first server creates the token, copied by hand to the others.** Nothing secret in user
data, and no cluster from a single `apply`. Rejected.

**Rotate the token once the cluster has formed**, with `k3s token rotate`, so that the copy in
user data no longer admits anyone. Stronger. Rejected for now: one more operation at every
rebuild, and the servers' configuration files to bring back in line with the new token.

**A rule in the node's `FORWARD` chain.** Rejected for the reason given above: its place in the
chain would depend on k3s's start-up order.
