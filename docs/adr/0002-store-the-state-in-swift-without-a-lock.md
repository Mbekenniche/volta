# 2. Store the state in Swift, encrypted, without a lock

## Status

Accepted — 2026-09-28

## Context

The state is the only record of what the platform created, and the only way to destroy it.
OpenTofu has no Swift backend; its `s3` backend reaches Swift through the S3 API. That backend
locks by writing an object with `If-None-Match: *`, and Swift 2.30.1 refuses every conditional
write: `501 NotImplemented`. With the lock on, `tofu plan` fails.

## Decision

The `s3` backend, on a versioned Swift container, encrypted by OpenTofu, with no lock.

- **The container belongs to a separate stack**, `infra/bootstrap/`, with a local state. No
  destroy of the platform touches it, and OpenTofu refuses any plan that would.
- **The state and saved plans are encrypted** with a passphrase kept on the workstation: they
  hold the cluster's join token.
- **In place of the lock:** one operator, every change through a saved plan (OpenTofu refuses a
  plan made before the state changed), and the container's versions to roll back.

## Consequences

- Two applies started at the same moment can still lose one of them.
- A version is restored by copying it over the current object in Swift; tested, byte for byte.
- The S3 key carries the account's rights on the project and never expires.
- The CI never plans or applies ([ADR 5](0005-build-from-the-workstation-and-check-in-ci.md)):
  the workstation is the only writer.
- The lock comes back with `use_lockfile = true` once the platform runs Swift 2.36.0 or later.

## Alternatives considered

- **A backend that locks** (`pg`, `kubernetes`, `azurerm`, `http`): a database or a server to run,
  inside the infrastructure it describes or on another cloud.
- **A hosted service** (Spacelift, Scalr): another account, for one operator.
- **A local state**: one laptop as the only record able to destroy the platform.
