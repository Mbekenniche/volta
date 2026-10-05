# Node access

How to reach the bastion and the cluster nodes over SSH. The nodes have no public address; every
session goes through the bastion. Why is recorded in
[ADR 0011](../adr/0011-reach-the-nodes-through-a-bastion.md).

## What it takes

- The private key matching `ssh_public_key_path` in `infra/terraform.tfvars`.
- A public address equal to `admin_cidr`. Otherwise the connection to the bastion times out.
- The environment of the [remote state runbook](remote-state.md), to read the outputs, and
  `OS_CLOUD`, to read the console logs.

## Where the files live

Commands run from the root of the repository. The SSH configuration, the known hosts and a copy
of the outputs live in `.project/ssh/`, which Git ignores: they describe one build of the
platform, not the code.

## Build the known hosts from the console logs

At first boot, cloud-init prints each instance's SSH host keys, and their fingerprints, to the
instance's console. The console log is read through the OpenStack API, authenticated, so the keys
can be trusted before the first connection, rather than accepted on it.

```sh
mkdir -p .project/ssh
tofu -chdir=infra output -json > .project/ssh/outputs.json

addr() {
  jq -r --arg n "$1" '
    if $n == "volta-lab-bastion" then .public_ip_bastion.value
    else .private_ip_node.value[$n] end' .project/ssh/outputs.json
}

: > .project/ssh/known_hosts
for name in volta-lab-bastion volta-lab-server-1 volta-lab-server-2 volta-lab-server-3; do
  log=$(openstack console log show "$name")
  key=$(printf '%s\n' "$log" | sed -n '/BEGIN SSH HOST KEY KEYS/,/END SSH HOST KEY KEYS/p' \
    | grep -o 'ssh-ed25519 [A-Za-z0-9+/=]*')
  echo "$name"
  printf '%s\n' "$key" | ssh-keygen -lf -
  printf '%s\n' "$log" | sed -n '/BEGIN SSH HOST KEY FINGERPRINTS/,/END SSH HOST KEY FINGERPRINTS/p' \
    | grep -o 'SHA256:[A-Za-z0-9+/]* .*(ED25519)'
  echo "$(addr "$name") $key" >> .project/ssh/known_hosts
done
```

For each instance, the fingerprint computed from the key and the one cloud-init printed must be
the same. If they differ, or a key is missing, do not connect: rebuild the file once the cause
is understood.

## SSH configuration

`.project/ssh/config`, with the addresses from the outputs:

```
Host *
  User ubuntu
  IdentityFile ~/.ssh/<private key>
  IdentitiesOnly yes
  UserKnownHostsFile <repository>/.project/ssh/known_hosts
  StrictHostKeyChecking yes
  HostKeyAlgorithms ssh-ed25519
  ForwardAgent no

Host volta-bastion
  HostName <public_ip_bastion>

Host volta-lab-server-1
  HostName <private_ip_node["volta-lab-server-1"]>
  ProxyJump volta-bastion
```

and the same block for `volta-lab-server-2` and `volta-lab-server-3`. `UserKnownHostsFile` takes
the absolute path of the repository, so that the file is found whatever the current directory.
Then:

```sh
ssh -F .project/ssh/config volta-bastion
ssh -F .project/ssh/config volta-lab-server-1
```

With `-F`, `~/.ssh/config` is not read, and the jump to the bastion uses the same file.

- **`StrictHostKeyChecking yes`**: an unknown key ends the connection instead of asking. There
  is never a reason to answer yes; the right keys are already in the file.
- **`ProxyJump`**: the session to a node is encrypted end to end between the workstation and
  the node, and the bastion relays bytes it cannot read. The private key stays on the
  workstation.
- **`ForwardAgent no`**: with agent forwarding, anyone who is root on the bastion could use the
  key while a session is open. `ProxyJump` does not need it.

## Check that the path is the expected one

```sh
ssh -F .project/ssh/config volta-lab-server-1 'echo $SSH_CONNECTION'
```

The first field is the bastion's private address, not the workstation's public one: the node only
ever sees the bastion. A direct connection that skips the bastion times out:

```sh
ssh -F .project/ssh/config -o ProxyJump=none -o ConnectTimeout=10 volta-lab-server-1
```

## After a destroy and apply

The floating IP is released on destroy, so the bastion gets a new public address, the nodes get
new private ones, and every instance has new host keys. Rebuild the known hosts and the
configuration, in that order. Nothing from the previous run is worth keeping.

## When it does not connect

- **The connection to the bastion times out.** The public address has probably changed. Update
  `admin_cidr`, then plan and apply: Neutron cannot edit a rule, so the plan replaces the two
  rules that name the address.
- **"REMOTE HOST IDENTIFICATION HAS CHANGED".** The instance was rebuilt, or something else
  answers on that address. Rebuild the known hosts from the console logs. Do not delete the line
  and accept whatever key comes next.
- **The bastion answers, a node does not.** `ProxyJump` needs SSH forwarding on the bastion, which
  the image allows by default. Hardening the bastion must not set `AllowTcpForwarding no`.
