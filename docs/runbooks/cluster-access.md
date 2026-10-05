# Cluster access

How to reach the Kubernetes API from the workstation. The API has no public address: it is
reached through an SSH tunnel to the bastion. Why is recorded in the amendments to
[ADR 0011](../adr/0011-reach-the-nodes-through-a-bastion.md) and
[ADR 0002](../adr/0002-run-a-self-managed-k3s-cluster.md).

## What it takes

- SSH access to the nodes through the bastion, set up as in the
  [node access runbook](node-access.md): the known hosts and `.project/ssh/config`.
- `kubectl`, within one minor version of the cluster's.
- Nothing listening on the workstation's port 6443.

## Fetch the kubeconfig

Commands run from the root of the repository, like those of the node access runbook. k3s writes
an admin kubeconfig on every server, readable by root only. Copy it from one of them:

```sh
rm -f ~/.kube/volta-lab.yaml
(umask 077; ssh -F .project/ssh/config volta-lab-server-1 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/volta-lab.yaml)
```

- **The file holds the cluster's admin client key.** It never goes into the repository, a
  conversation or a ticket.
- **`rm` first.** A redirection into an existing file keeps that file's mode; `umask 077` only
  applies to a file it creates, which then gets mode 0600.
- **It is kept apart from `~/.kube/config`**, and chosen per command with `KUBECONFIG`, so that
  no other cluster's context is touched.
- **It points at `https://127.0.0.1:6443`**: the local end of the tunnel below. The server's
  certificate covers that address.

## Open the tunnel

With the address of `volta-lab-server-1` from the outputs (`private_ip_node`):

```sh
ssh -F .project/ssh/config -f -N -L 127.0.0.1:6443:<server address>:6443 volta-bastion
```

- **`-L 127.0.0.1:6443:…`** listens on the workstation's loopback only. Never add `-g`, and never
  bind `0.0.0.0`: anyone who could reach that port would reach the API.
- **`-f -N`** sends the tunnel to the background once authenticated, with no remote command.
- **The bastion relays bytes.** TLS runs between `kubectl` and the API server, and the bastion
  holds no credential of the cluster.

## Use it

```sh
KUBECONFIG=~/.kube/volta-lab.yaml kubectl get nodes -o wide
```

Three nodes are expected, `Ready`, with the roles `control-plane,etcd`, and as internal addresses
the private addresses of their ports.

## Close the tunnel

```sh
pkill -f 'L 127.0.0.1:6443'
```

## After a destroy and apply

Every address, host key and certificate is new. Rebuild the node access first, as in the
[node access runbook](node-access.md), then fetch the kubeconfig again and open the tunnel to the
server's new address. The old kubeconfig names a certificate authority that no longer exists.
