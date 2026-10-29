# 3. Reach the nodes through a bastion

## Status

Accepted — 2026-10-01

## Context

The nodes sit on a private network behind a router, with no public address. They still have to
be reached over SSH, and the Kubernetes API from the workstation. Each server keeps the join
token in its user data, readable from inside it.

## Decision

A dedicated instance, the bastion, holds the only public address used for administration.

- **Its security group** admits SSH from the administrator's address only. It may open SSH and
  the Kubernetes API to the cluster's group, and nothing over HTTPS.
- **The cluster's group** admits SSH from the bastion's group only, and the API from the bastion
  and the other nodes.
- **SSH goes through `ProxyJump`**: encrypted end to end, the key never leaves the workstation,
  agent forwarding is off, and host keys come from the instances' console logs.
- **The API is reached through a tunnel** bound to the workstation's loopback,
  `127.0.0.1:6443`. TLS runs between `kubectl` and the API server.
- **The load balancer is the only other public address**, on ports 80 and 443 alone.

## Consequences

- The exposed machine is not a member of the cluster: no etcd, no API, no join token.
- The three servers stay identical.
- A compromised node cannot reach the bastion, and the bastion cannot reach etcd or the kubelet.
- One door: if the bastion fails, the cluster keeps running but cannot be administered until an
  apply recreates it.
- Its address changes at every rebuild; `make up` rewrites the SSH configuration.

## Alternatives considered

- **A floating IP on one node**: that node would also be an etcd member and hold the join token.
- **A floating IP on every node**: three public addresses to save one hop.
- **The API through the load balancer**: a second door for administration.
