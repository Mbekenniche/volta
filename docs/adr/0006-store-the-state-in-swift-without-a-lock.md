# 6. Store the state in Swift through the S3 API, without a lock

## Status

Accepted — 2026-09-28

## Context

The state is the only record of what the platform created, and the only thing that lets
OpenTofu destroy it. Until this step it was a single file on a single laptop. It is about to
hold more than resource IDs: the cluster step adds an admin kubeconfig, and CI will need to
reach it from somewhere else.

OpenTofu has no Swift backend. Its remote backends are `azurerm`, `consul`, `cos`, `gcs`,
`http`, `kubernetes`, `oss`, `pg` and `s3`. The platform's object storage speaks S3 through
Swift's `s3api` middleware, so `s3` is the only one that reaches it without adding a service.

That backend locks the state in one of two ways. DynamoDB does not exist here. The other,
`use_lockfile`, writes a lock object with `If-None-Match: *` and counts on the store to refuse
the write when the object already exists. The platform runs Swift 2.30.1, whose S3 layer
refuses every conditional write with `501 NotImplemented`, "Conditional object PUTs are not
supported." With `use_lockfile = true`, `tofu plan` failed on that error, as would any command
that takes the lock. Upstream Swift accepts `If-None-Match: *` from 2.36.0.

The backend also needs an S3 key. The application credential of
[ADR 0003](0003-authenticate-with-an-application-credential.md) was refused when it tried to
create one (403): Keystone keeps a restricted credential from creating a key broader than
itself.

## Decision

Keep the state in a Swift container through the `s3` backend, and run without a lock.

- The container, `volta-lab-tfstate`, is created by a separate root, `infra/bootstrap/`, which
  has a local state of its own. It is not part of the platform's destroy and apply cycle, has
  versioning enabled, and OpenTofu refuses any plan that would destroy it.
- The state object is `infra.tfstate`, named after the root module that owns it.
- The backend points at `https://s3.pub1.infomaniak.cloud` with `us-east-1` as signing region,
  the only one Swift accepts. It skips the calls the AWS SDK makes to STS, IAM and the instance
  metadata service, none of which exist here. Credentials come from `AWS_PROFILE`, never from
  the configuration.
- The S3 key was created once, by hand, with the account password.

What stands in for the lock:

- one operator, and a single terminal that writes the state;
- every change goes through a saved plan, `tofu plan -out` then `tofu apply` of that file.
  OpenTofu refuses a saved plan if the state changed after it was made ("Saved plan is
  stale"), which was tested;
- the container's version history, to recover a damaged state;
- from the CI step, a GitHub Actions concurrency group, and no more applies from a
  workstation.

## Consequences

- **Two applies that overlap can still lose one of them.** Without a lock, the last write
  wins. Saved plans catch a state that changed between plan and apply, not two applies started
  at the same moment.
- **Versioning is a way back, not an undo.** A version is restored by copying it over the
  current object with Swift's `COPY`. This was tested: the new version was identical to the old
  one, byte for byte, and the next plan was empty. After a real conflict, restoring one version
  drops the other writer's changes, and whatever it created has to be imported by hand. A
  restore also rewinds the serial, so the history is read by date.
- **The S3 key is a long-lived secret with the account's rights.** Created with the password,
  it carries the account's roles on the project and never expires, unlike the application
  credential. `/v3/ec2tokens` is exposed, so the key can be traded for a Keystone token. It is
  kept like `clouds.yaml`, and replacing it takes the password again.
- **The bootstrap state is local.** It describes one container, which can be imported again if
  that file is lost.
- **The migration restarted the state's serial and lineage.** On the first write to an empty
  backend, OpenTofu 1.12.5 re-reads the destination, finds nothing, and starts a new lineage at
  serial 1. Every resource was kept.

## When to revisit

Running without a lock stops being acceptable with a second operator, with CI and a person both
applying, or with anything beyond a lab. If `GET /info` reports Swift 2.36.0 or later, the lock
comes back with one line, `use_lockfile = true`, once the test of this step has been repeated
on a versioned container.

## Alternatives considered

**Keep `use_lockfile = true`.** Not an option: every command that takes the lock fails.

**A backend that locks.** `pg` needs a PostgreSQL database, and the catalogue has none; running
one in the project would put the state inside the infrastructure it describes. `kubernetes` has
the same problem. `azurerm` locks with blob leases, but the state of an Infomaniak project would
live on another cloud, under another account. `http` needs a lock server to write and host.
Each buys a guarantee against a risk that, with one operator, only a mistake can trigger.

**A hosted OpenTofu service**, such as Spacelift, Scalr or env0. Rejected: another account and
another dependency, for one operator.

**Create the container by hand.** Rejected: without a Swift client, enabling versioning means
raw API calls, and nothing would record what was done.

**Keep the state local.** Rejected: one laptop would stay the only record able to destroy the
platform.
