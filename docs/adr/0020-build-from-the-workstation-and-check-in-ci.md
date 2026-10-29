# 20. Build and destroy from the workstation, check every change in CI

## Status

Accepted — 2026-10-29

## Context

The README's first rule is "one command builds it, one destroys it". Until this step, a rebuild
took a dozen hand-run steps: two applies, the known hosts, the kubeconfig, the tunnel, four
Secrets, Argo CD, the root `Application`. Nothing checked a change before Argo CD applied it from
`main`.

What the decision rests on, checked on 2026-10-28 and 2026-10-29:

- **`tofu init -backend=false` and `tofu validate` need no secret** on either stack: no
  passphrase, no S3 key, no cloud credential. A `plan` needs the state, so an S3 key, and any S3
  key is worth the account's rights on the project ([ADR 0019](0019-back-up-to-swift-with-velero.md)).
- **An action's tag can be moved.** On 2026-03-19, almost every tag of `aquasecurity/trivy-action`
  was rewritten to point at code that stole secrets (CVE-2026-33634). Only a commit SHA is
  immutable, and GitHub can refuse any action not pinned to one.
- **The pre-commit hook for gitleaks reads only the staged changes.** Run in CI, where nothing is
  staged, it passes with a key committed in the history.
- **Nova keeps only the end of an instance's console log**, about 1,200 lines here. The block
  where cloud-init prints the SSH host keys, at first boot, was gone from all four instances
  within days.
- **The workstation's `make` is GNU Make 3.81**: every line of a recipe runs in its own shell.
- **The workstation's default `kubectl` context belongs to another cluster.** A script that
  inherits it would create volta's Secrets there.

## Decision

The workstation builds and destroys, with `make up` and `make down`; the CI checks every change
and holds no secret.

**The CI** ([`.github/workflows/checks.yaml`](../../.github/workflows/checks.yaml)) runs on every
pull request and on `main`, in three jobs:

- `pre-commit`: the repository's hooks on every file, then gitleaks over the whole history.
- `validate`: `tofu validate` on both stacks, without their backend.
- `render`: every `Application` rendered as Argo CD renders it, its chart at its version with its
  values, then every object checked by kubeconform against the schemas of the cluster's
  Kubernetes version and of its CRDs ([`scripts/render-apps.sh`](../../scripts/render-apps.sh)).

Its token can only read the repository, and the checkout does not keep it. Every action is pinned
to a commit, its release in a comment; the repository refuses any other, and Dependabot proposes
new SHAs every month.

**`main` is protected**: a pull request for every change, the three checks green on a branch up
to date with `main`, a linear history (merges by rebase), and no bypass, for anyone.

**`make up`** runs six phases, each a script under [`scripts/`](../../scripts/), each of which
does nothing when its work is already done:

| Phase | Work |
|---|---|
| `preflight` | The tools, the variables OpenTofu reads, the Secrets' source files, and the workstation's address against `admin_cidr` |
| `infra` | A plan saved to a file; if it changes anything, a typed `yes`, then the apply of that plan |
| `ssh-config` | The known hosts and the SSH configuration. A host key is kept under its instance's ID, read once from the console while the instance is new, its fingerprint checked |
| `kubeconfig` | The admin kubeconfig, the tunnel to the API, three nodes `Ready` |
| `secrets` | The four Secrets from the workstation's files, applied server side, before Argo CD |
| `services` | Argo CD with Helm, the root `Application`, the root `Synced` and `Healthy`, the demo answering over HTTPS with a valid certificate |

Each script sets `KUBECONFIG` itself, never inheriting the operator's.

**`make down`** saves a destroy plan of the main stack, asks for the environment's name, applies
the plan, then deletes the volumes the Cinder CSI driver created, by their mark, once each is
detached. The bootstrap stack, with the state, the stable address and the backups, is never
touched.

**The DNS record stays outside the code.** It points at the stable address, which survives every
cycle, so `make up` has nothing to change there. Designate is not used.

## Consequences

- **A run of the CI takes 35 to 55 s**, its three jobs in parallel: `pre-commit` 34 to 52 s,
  `render` 7 to 14 s, `validate` 7 to 11 s, over ten runs.
- **Only the workstation can apply**, which keeps the single operator that
  [ADR 0006](0006-store-the-state-in-swift-without-a-lock.md) relies on. The CI cannot see drift:
  that needs a `plan`.
- **The root `Application` synced on its own** on both fresh clusters built on 2026-10-29: no click
  in Argo CD's interface.
- **A fresh build takes one apply** since the health monitors wait for the pools' members; see
  the amendment to [ADR 0015](0015-enter-through-an-octavia-load-balancer.md). One build so far.
- **Every `make up` on a fresh cluster takes a production certificate.** Let's Encrypt issues five
  a week for the same names.
- **A workstation knows only the host keys of instances it saw new.** From another one, the keys
  of a running build are no longer in the console logs.
- **`make down` trusts the state.** On 2026-10-29, it left servers and the load balancer behind;
  see [what broke](../what-broke.md#a-destroy-that-forgot-half-the-platform). After each
  `make down`, the project's servers and load balancers are listed.

## Alternatives considered

**A `plan` on every pull request.** It would show drift, and errors `validate` lets through, at
the cost of an S3 key and the state's passphrase in GitHub: the rights to read and destroy the
whole project. A federated identity (OIDC), as on Azure, was not checked on this platform.

**`apply` from the CI**, or `make up` triggered by hand on GitHub. Rejected: it would need the
lock the state lacks, every secret in GitHub, and SSH from GitHub's changing addresses to a
bastion that admits one.

**Pushing to `main` directly**, with the CI after. Rejected: `main` could be red, and Argo CD
applies it anyway.

**`apply -auto-approve`.** Rejected: a change that replaces the servers would go through without
anyone reading the plan.

**Deleting the volumes from inside the cluster before the destroy.** Rejected: it needs a healthy
cluster and the tunnel, and it fights the controllers that recreate what they own.

**Designate**, with `volta.koveolabs.com` delegated to it. Rejected: the address never changes,
and the DNS would depend on the platform.

**Action tags.** Rejected for the reason above. **`pre-commit/action`** is in maintenance only:
the CI installs pre-commit itself.
