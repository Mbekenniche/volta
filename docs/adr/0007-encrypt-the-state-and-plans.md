# 7. Encrypt the state and plans with OpenTofu

## Status

Accepted — 2026-09-28

## Context

From the cluster step on, the state will contain an admin kubeconfig and the k3s join token.
It now lives in object storage that anyone holding the project's application credential or
the S3 key can read ([ADR 0006](0006-store-the-state-in-swift-without-a-lock.md)). A saved
plan carries the same data as the state.

OpenTofu has encrypted state and plan files itself since version 1.7, with a key provider and a
method declared in the configuration. Terraform has no equivalent.

The state held no secret yet: resource IDs, the administrator's address, a public key. That
made this step the cheapest moment to add encryption, and doing it before the remote backend
meant the object store would never receive a plaintext copy.

## Decision

Encrypt the state and every saved plan, and refuse anything unencrypted.

- Key provider `pbkdf2`, fed by a passphrase through a sensitive variable,
  `TF_VAR_encryption_passphrase`. The passphrase never enters the repository. Its parameters
  are OpenTofu's defaults, as recorded in the state: 600,000 iterations of SHA-512, a 32-byte
  key.
- Method `aes_gcm` for both `state` and `plan`, both `enforced`.
- The `encryption` block stays in the code, where it gets reviewed. Only the passphrase comes
  from outside.
- The local state was encrypted first, through a one-time fallback to an unencrypted method,
  and moved to Swift afterwards. The first version in the container is already ciphertext.

## Consequences

- **A lost passphrase is a lost state**, and with it the means to destroy the platform through
  OpenTofu. The passphrase is kept in a password manager, and loaded into the environment from
  the macOS keychain.
- **Every command needs it**, CI included from the CI step.
- **What stays readable** is the serial, the lineage and the key provider's metadata: the salt
  and parameters, which are not secret. The rest is ciphertext, and a wrong passphrase is
  refused.
- **Names are part of the data.** The state records the key provider's name in its metadata,
  so renaming it takes the same fallback as the first migration. That was done once, when
  `migration` became `passphrase`.
- **`tofu validate` does not look at the `encryption` block.** A reference to an undeclared
  provider or method passes it; only a plan catches it.
- **`tofu state push` expects plaintext.** OpenTofu 1.12.5 reads the file it is given without
  decrypting it, so an encrypted version is restored in Swift instead, see
  [ADR 0006](0006-store-the-state-in-swift-without-a-lock.md).
- **Terraform can neither use this configuration nor read this state.** That ends the
  portability promise of [ADR 0001](0001-use-opentofu-instead-of-terraform.md), which is
  amended accordingly.
- **Changing the passphrase has not been done yet.** OpenTofu supports it through the same
  fallback mechanism. It will be tested before it is needed.

## Alternatives considered

**Wait for the cluster step.** Rejected: the kubeconfig would have been the first secret to
reach the store, and a mistake in the migration would have cost a real secret instead of
nothing.

**Barbican.** OpenTofu has no key provider for it, and a key kept in the same project as the
state would not protect it from the credential that can read both.

**The whole configuration in `TF_ENCRYPTION`.** Rejected: the design would live outside the
repository, where nobody reviews it.

**A cloud KMS**: AWS KMS, GCP KMS, Azure Key Vault or OpenBao. Rejected: another cloud, or
another service to run, for one passphrase.

**The `external` key provider**, which runs a command to fetch the key. Viable, and the next
step if the passphrase has to leave the environment. For now the keychain feeds a variable,
which is easier to reason about.
