# Lifecycle

Build, destroy, and repair the state. Why: [ADR 5](../adr/0005-build-from-the-workstation-and-check-in-ci.md).

## What it takes

- `tofu`, `openstack`, `kubectl`, `helm`, `jq`, `dig`.
- `OS_CLOUD` (the `clouds.yaml` entry), `AWS_PROFILE` (the S3 key), `TF_VAR_encryption_passphrase`.
  [`.envrc.example`](../../.envrc.example) shows one way to set them.
- The workstation's public address in `admin_cidr`, in `infra/terraform.tfvars`.
- `~/.ssh/volta_lab`, and in `~/.config/volta/`: `cloud.conf`, `grafana-admin-password`,
  `velero-credentials`, `velero-repo-password` (the passwords without a final newline).

## Build

```sh
make up
```

- Type `yes` after reading the plan. No changes, no question.
- Done when the demo answers over HTTPS.
- Stopped or failed: run it again. One phase alone: `make preflight`, `infra`, `ssh-config`,
  `kubeconfig`, `secrets`, `services`.

## Destroy

```sh
make down
```

Type `volta-lab` after reading the plan. Then check what is left:

```sh
openstack server list
openstack loadbalancer list
openstack volume list
openstack floating ip list
```

Expected: only `179.237.92.39`, with no fixed address.

## When it fails

| Symptom | Fix |
|---|---|
| `admin_cidr … is …` | Put the new address in `admin_cidr`, then `make infra` |
| `… is new, waiting for its host keys`, on an old instance | Its key is not in `.project/ssh/keys/`, and its console no longer holds it: copy `keys/` from the workstation that built it, or rebuild |
| A health monitor, `TCP is not a valid option for type` | `make up` again |
| Destroy times out on the router interface | Something the state forgot still uses the router. Delete it (`openstack loadbalancer delete --cascade`, `openstack server delete`), then `make down` again |
| `Saved plan is stale` | The state changed since the plan: plan again |

## Restore a version of the state

The container keeps every version. List them, then copy one over the current object:

```sh
TOKEN=$(openstack token issue -f value -c id)
BASE=https://s3.pub1.infomaniak.cloud/object/v1/AUTH_<project_id>/volta-lab-tfstate
curl -s -H "X-Auth-Token: $TOKEN" "$BASE?format=json&versions" \
  | jq -r '.[] | "\(.version_id)  \(.last_modified)  \(.bytes)"'
curl -s -o /dev/null -w '%{http_code}\n' -X COPY -H "X-Auth-Token: $TOKEN" \
  -H "Destination: volta-lab-tfstate/infra.tfstate" "$BASE/infra.tfstate?version-id=<version_id>"
```

Expect `201`, then an empty `tofu -chdir=infra plan`.
