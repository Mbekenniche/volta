# 3. Authenticate with an application credential

## Status

Accepted — 2026-09-19

## Context

Every command in this project authenticates to Keystone: the OpenStack CLI while exploring, the
OpenTofu provider while provisioning, and CI later on. Keystone offers two practical ways to do
that from a machine.

The first is the account password, which Infomaniak hands out in a ready-made `clouds.yaml`.
It authenticates the human being, carries every right that human has, cannot be narrowed, and
cannot be revoked without locking the person out of the dashboard at the same time. Rotating it
breaks every consumer at once, and nothing distinguishes a run of OpenTofu from someone logging
in.

The second is an application credential: a separate identifier and secret, scoped to one
project, holding a chosen subset of the owner's roles, revocable on its own and optionally
expiring. It is the same idea as a service principal on Azure, with one difference that matters
in practice — the scope is baked into the credential rather than passed alongside it.

## Decision

Authenticate with an application credential named `volta-opentofu`, restricted, expiring
2027-03-31.

Store it in `~/.config/openstack/clouds.yaml` under the entry `volta-tofu` — outside the
repository, on purpose. The repository holds only `.envrc.example`, which exports `OS_CLOUD` to
name that entry. No secret is ever written inside the working tree, so no secret can be
committed by accident.

The credential carries the roles its owner holds on the project: `member`, `reader`,
`observer`, `creator`, `SwiftOperator`, `load-balancer_member` and `load-balancer_observer`.
Those cover what the platform needs — Swift for remote state and backups, Octavia for ingress,
Barbican for TLS material.

## Consequences

- The configuration entry must not name a project or a domain. An application credential
  already carries its own project scope, and supplying a second one is rejected. This is the
  usual first failure when converting an existing `clouds.yaml`.
- The secret is displayed once, at creation, and stored hashed. Losing it means deleting the
  credential and creating another; there is no recovery path.
- Rotation is cheap and isolated: create the replacement, update `clouds.yaml`, delete the old
  one. Nothing else authenticates with it, so nothing else breaks.
- The account password no longer appears in any automated path. It stays where it belongs, on
  the dashboard login.
- **The expiry is a containment measure, not a budget control.** A credential that expires
  stops nobody's instances — it only stops whoever holds it from managing them, including from
  destroying them. It must be renewed before 2027-03-31, and the cost of running infrastructure
  is controlled by destroying it, not by letting its credentials lapse.
- CI will need the same pair as repository secrets. The credential model makes that safe:
  the value given to CI is not the account password and can be revoked alone.

## Alternatives considered

**The account password.** Rejected. It ties automation to a human identity, cannot be scoped or
revoked independently, and would have to be written into a file that sits next to the code.

**An unrestricted credential.** Rejected. `--unrestricted` lifts the ban on creating further
application credentials and trusts. Provisioning needs neither, and a credential that can mint
other credentials undoes most of the reason for using one.

**A narrowed role set, via `--role`.** Deferred rather than rejected. The credential could hold
fewer roles than its owner, and eventually should. It does not yet, because the full set this
platform needs is not known until Octavia and Barbican are actually in use; narrowing now would
produce authorisation failures several steps later, far from their cause. Worth revisiting once
the platform is complete, as a deliberate tightening with a working baseline to compare against.

**Access rules, via `--access-rules`.** Rejected. They restrict a credential to an explicit list
of API paths and methods. An infrastructure provider calls a wide and shifting surface of
endpoints, so the list would be long, brittle, and would fail in ways that look like provider
bugs. The cost of maintaining it outweighs what it adds over a restricted, project-scoped
credential.
