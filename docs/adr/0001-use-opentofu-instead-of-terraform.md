# 1. Use OpenTofu instead of Terraform

## Status

Accepted — 2026-09-19

## Context

This platform is provisioned as code against the OpenStack API of the Infomaniak Public Cloud.
The declarative language, the state model and the OpenStack provider
(`terraform-provider-openstack/openstack`) are identical whichever binary executes them, so the
choice is about licensing, governance and tooling rather than about capability.

In August 2023 HashiCorp relicensed Terraform from MPL-2.0 to the Business Source License.
OpenTofu is the MPL-2.0 fork of the code base, maintained under the Linux Foundation. Both
binaries are installed on the workstation used for this project, and Infomaniak's own Public
Cloud documentation instructs users to install "HashiCorp Terraform or OpenTofu", so neither
option carries vendor friction on their platform.

## Decision

Use OpenTofu. Pin the minimum version in the `required_version` constraint and pin provider
versions in `required_providers`, so that a clone reproduces the same plan.

Write the configuration in portable HCL and avoid constructs specific to either binary. The
code must remain executable by Terraform with no edit, because that compatibility is what keeps
this decision cheap to reverse.

## Consequences

- The toolchain stays under MPL-2.0, with no usage restriction to read or reason about.
- Provider resolution goes through the OpenTofu registry. The OpenStack provider is published
  there, so no mirror or override is needed.
- CI needs OpenTofu explicitly; actions and images that default to Terraform have to be swapped
  for their OpenTofu equivalents. This is a one-line change per workflow.
- Linting and scanning tools operate on HCL and on the plan output, so `tflint` and Trivy are
  unaffected by the choice.
- Readers who look for the word "Terraform" will not find it in the commands. The skill is the
  same one, and reversing the decision is a single substitution of the binary name.

## Alternatives considered

**Terraform.** Rejected. It offers no functional advantage here, and the Business Source
License adds a restriction that has to be understood and tracked for no benefit on a project
whose entire point is to be readable and reusable.

**OpenStack Heat.** Rejected, though Infomaniak documents it as a first-class option. Heat is
native to OpenStack and would remove one abstraction layer, but its templates do not carry over
to any other platform, its ecosystem of modules and scanners is far smaller, and the resulting
skill would not transfer. Portability of the approach is worth more here than proximity to the
API.

**Pulumi or Crossplane.** Rejected. Both introduce a general-purpose language runtime or a
Kubernetes control plane into the provisioning path. On an infrastructure whose stated goal is
to be destroyed and rebuilt in one command, that is an extra failure domain bought for nothing:
the cluster cannot be the thing that provisions the cluster.
