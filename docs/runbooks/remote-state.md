# Remote state

How the OpenTofu state of `infra/` is kept, and what to do when it needs repairing. The reasons
behind this setup are in [ADR 0006](../adr/0006-store-the-state-in-swift-without-a-lock.md)
and [ADR 0007](../adr/0007-encrypt-the-state-and-plans.md).

## Environment

Every `tofu` command in `infra/` needs three variables:

| Variable | What it points to |
|---|---|
| `OS_CLOUD` | the `clouds.yaml` entry holding the application credential |
| `AWS_PROFILE` | the `~/.aws/credentials` profile holding the S3 key |
| `TF_VAR_encryption_passphrase` | the passphrase of the state encryption |

[`.envrc.example`](../../.envrc.example) shows one way to set them. None of the values belongs
in the repository.

## Everyday rules

- One terminal writes the state. There is no lock, and two applies at once can lose one of
  them.
- Every change goes through a saved plan, including destroys (`tofu plan -destroy -out=…`):

  ```sh
  tofu plan -out=change.tfplan
  tofu apply change.tfplan
  rm change.tfplan
  ```

  If the state changed in between, the apply stops with "Saved plan is stale". Plan again.
- A plan file holds as much as the state. It is encrypted, kept out of Git by the `.tfplan`
  extension, and deleted once applied.

## The state container

`infra/bootstrap/` creates the `volta-lab-tfstate` container and keeps its own state locally.
It is applied once and stays out of the platform's destroy and apply cycle. OpenTofu refuses
any plan that would destroy the container.

## List the versions of the state

The container keeps every version ever written. With a Keystone token:

```sh
TOKEN=$(openstack token issue -f value -c id)
BASE=https://s3.pub1.infomaniak.cloud/object/v1/AUTH_<project_id>/volta-lab-tfstate
curl -s -H "X-Auth-Token: $TOKEN" "$BASE?format=json&versions" \
  | jq -r '.[] | "\(.version_id)  \(.last_modified)  \(.bytes)"'
```

Each version is encrypted, but its serial stays readable:

```sh
curl -s -H "X-Auth-Token: $TOKEN" "$BASE/infra.tfstate?version-id=<version_id>" \
  | grep -o '"serial":[0-9]*'
```

## Restore a version

`tofu state push` cannot do it: OpenTofu 1.12.5 reads the file it is given as plaintext. The
version is restored in Swift instead, by copying it over the current object:

```sh
curl -s -o /dev/null -w '%{http_code}\n' -X COPY -H "X-Auth-Token: $TOKEN" \
  -H "Destination: volta-lab-tfstate/infra.tfstate" \
  "$BASE/infra.tfstate?version-id=<version_id>"
```

The answer is `201`. The copy becomes the newest version and the others stay. Then run
`tofu plan`: an empty plan means the restored state matches the platform.

The serial goes back to that of the restored version, so the history can hold two versions
with the same serial. Read it by date.

After two applies that overlapped, restoring brings back one side and drops the other's
changes. Whatever the dropped side created has to be imported, or deleted by hand.

## Replace the S3 key

The application credential is not allowed to create S3 keys, so this takes the account
password, typed at the prompt. `env -u OS_CLOUD` keeps the application credential out of this
one command:

```sh
env -u OS_CLOUD openstack --os-auth-type v3password \
  --os-auth-url https://api.pub1.infomaniak.cloud/identity/v3 --os-region-name dc3-a \
  --os-username <user> --os-user-domain-name Default --os-project-id <project_id> \
  ec2 credentials create
```

Put the new `access` and `secret` in the profile, check that `tofu plan` still works, then
delete the old key with the same options and `ec2 credentials delete <old access>`. Deleting a
key has not been done on this project yet.

## If the passphrase is lost

The state can no longer be read, and OpenTofu can no longer destroy what it describes. The
resources then have to be removed by hand, or imported into a new state. This is why the
passphrase is kept in a password manager.

Changing the passphrase is not covered here. OpenTofu supports it through a fallback method,
but it has not been done on this project.
