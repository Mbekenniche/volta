# Lifecycle

How to build the platform with one command and destroy it with another. Why it works this way is
recorded in [ADR 0020](../adr/0020-build-from-the-workstation-and-check-in-ci.md).

## What it takes

- `tofu`, `openstack`, `kubectl`, `helm`, `jq` and `dig` on the workstation.
- The environment of the [remote state runbook](remote-state.md): `OS_CLOUD`, `AWS_PROFILE` and
  `TF_VAR_encryption_passphrase`.
- The workstation's public address in `admin_cidr`, in `infra/terraform.tfvars`, applied.
- The SSH key named in `infra/terraform.tfvars`, `~/.ssh/volta_lab`.
- Four files in `~/.config/volta/`, never in the repository: `cloud.conf`,
  `grafana-admin-password`, `velero-credentials` and `velero-repo-password`. The two passwords
  have no final newline: `--from-file` would keep it.

`make preflight` checks all of it but the key, and stops on the first thing missing.

## Build

```sh
make up
```

- **The plan comes first.** If it changes anything, `make up` waits for `yes`, typed, then applies
  that exact plan. A plan with no changes asks nothing.
- **It ends when the demo answers over HTTPS** with a valid certificate, after three nodes `Ready`
  and the root `Application` `Synced` and `Healthy`.
- **Every line it prints starts with a UTC time**, which gives the duration of each phase.
- **Each phase runs alone**: `make preflight`, `make infra`, `make ssh-config`,
  `make kubeconfig`, `make secrets`, `make services`. `make -n up` shows the order.
- **An interrupted or failed run is resumed by running `make up` again.** Each phase does nothing
  when its work is already done.

Then, in any terminal used on the platform:

```sh
export KUBECONFIG=~/.kube/volta-lab.yaml OS_CLOUD=volta-tofu
kubectl -n argocd get applications
```

The eight `Application` resources are expected `Synced` and `Healthy`. The scripts set
`KUBECONFIG` themselves; the operator's shell does not, and its default context may be another
cluster.

## The files of a build

`.project/ssh/`, which Git ignores, holds the outputs of the main stack (`outputs.json`), the
known hosts, the SSH configuration and, in `keys/`, one host key per instance, named by the
instance's ID. The kubeconfig is `~/.kube/volta-lab.yaml`, mode 0600.

`keys/` matters most: a host key can be read from the console log only while its instance is new
([node access runbook](node-access.md)). From another workstation, the keys of a running build
are no longer in the console: copy `keys/` over, or rebuild.

## Destroy

```sh
make down
```

- **The destroy plan comes first**, then the name of the environment, `volta-lab`, typed.
- **Only the main stack goes.** The bootstrap stack keeps the state, the stable address and the
  backups.
- **The volumes of the Cinder CSI driver go after it**, each once it is detached. Prometheus's
  history goes with them, and stays in the backups.
- **The kubeconfig, the outputs and the host keys of the destroyed build are deleted.**

Then:

```sh
openstack server list
openstack loadbalancer list
openstack volume list
openstack floating ip list
```

Nothing is expected but the stable address, `179.237.92.39`, with no fixed address. What stays
billed is the stable address and the bootstrap stack's containers.

## When it does not go through

- **"this workstation is …, admin_cidr … is …".** The address has changed. Update `admin_cidr`,
  then `make infra`: Neutron cannot edit a rule, so the plan replaces the two that name it.
- **"… is new, waiting for its host keys on the console", for an instance that is not new.** Its
  key is not in `keys/`, and its console no longer holds it. Copy `keys/` from the workstation that
  built it, or rebuild the instance.
- **A destroy that times out on the router interface.** Something the state no longer knows still
  uses the router, such as the stable address associated with a load balancer. List what is left as
  above, delete it (`openstack loadbalancer delete --cascade`, `openstack server delete`), then run
  `make down` again; see [what broke](../what-broke.md#a-destroy-that-forgot-half-the-platform).
- **The first apply fails on a health monitor**, "TCP is not a valid option for type". Run
  `make up` again: the plan shows only what is missing. See the amendment to
  [ADR 0015](../adr/0015-enter-through-an-octavia-load-balancer.md).
