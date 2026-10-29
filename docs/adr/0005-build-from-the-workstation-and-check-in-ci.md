# 5. Build from the workstation, check every change in CI

## Status

Accepted — 2026-10-29

## Context

A rebuild took a dozen hand-run steps, and nothing checked a change before Argo CD applied it.
A `plan` in CI would need an S3 key, and any S3 key is worth the account's rights on the whole
project. An action's tag can be moved: in March 2026, the tags of `aquasecurity/trivy-action` were
rewritten to steal secrets.

## Decision

`make up` and `make down` run on the workstation; the CI checks and holds no secret.

- **The CI**, on every pull request and on `main`: the pre-commit hooks and gitleaks over the
  history; `tofu validate` on both stacks; every `Application` rendered as Argo CD renders it,
  then checked by kubeconform. Read-only token, every action pinned to a commit.
- **`main`** takes pull requests only, with the three checks green, a linear history, no bypass.
- **`make up`** runs six phases, each doing nothing when its work is done: preflight, a saved
  plan applied after a typed `yes`, SSH host keys, kubeconfig and tunnel, the Secrets, then Argo
  CD and the root. It ends when the demo answers over HTTPS.
- **`make down`** applies a destroy plan after the environment's name is typed, then deletes the
  CSI volumes. The bootstrap stack is never touched.

## Consequences

- A CI run takes 35 to 55 s.
- Only the workstation writes the state, which the missing lock requires
  ([ADR 2](0002-store-the-state-in-swift-without-a-lock.md)).
- A stopped `make up` is resumed by running it again.
- Each fresh cluster takes a production certificate, five a week at most.

## Alternatives considered

- **A `plan` in CI**: drift would show, at the cost of the project's rights in GitHub.
- **`apply` from CI**: every secret in GitHub, and no lock.
- **Pushing to `main` directly**: `main` could be red, and Argo CD applies it anyway.
- **`-auto-approve`**: a plan that replaces the servers would go through unread.
