# 8. Pin the node image by ID

## Status

Accepted — 2026-10-01

## Context

Glance on this platform republishes its public images under the same name. The Ubuntu 24.04
image visible on 2026-09-14 had one ID; on 2026-09-28 at 09:02 UTC a new build replaced it
under the name `Ubuntu 24.04 LTS Noble Numbat`, with another ID. The previous builds are not
deleted. They are hidden (`os_hidden`), stay `active`, and can still be read by their ID: on
2026-10-01, 46 hidden builds of that image existed, the oldest from 2024-05-22. The rhythm is
irregular. There were six rebuilds between 2026-07-20 and 2026-09-28, nearly always on a Monday
around 09:00 UTC, and none at all between December 2025 and February 2026.

An instance's image cannot change in place: a new `image_id` replaces the instance. Looking the
image up by name would therefore propose, at the first plan after each rebuild, to replace every
node at once. With the embedded etcd of [ADR 0002](0002-run-a-self-managed-k3s-cluster.md), that
is all three members of the quorum.

Pinning an ID raises a second question: how to check that the ID is the image it claims to be.
The provider cannot look an image up by ID. `openstack_images_image_v2` lists `id` among its
arguments in the provider schema, as 53 of its 54 data sources do, but this is the implicit field
the plugin SDK adds everywhere: `tofu validate` rejects it as an "Invalid or unknown key".

## Decision

Pin the image by ID, and check it against the name at plan time.

- The ID is the default of a variable at the root, `image_id`, with the image name and build
  date in a comment beside it. Moving to a newer build is a reviewed change to that line.
- Two `openstack_images_image_ids_v2` data sources list the builds carrying the exact name
  `Ubuntu 24.04 LTS Noble Numbat`: the visible one, and the hidden ones (`hidden = true`).
- A precondition on each instance, nodes and bastion alike, requires the pinned ID to be in one
  of the two lists. A mistyped ID, or one belonging to another image, stops the plan before
  anything is created.

On 2026-10-01 the visible list held only the pinned build, the hidden list held 46, including
the build replaced on 2026-09-28, and the ID of a Debian image was in neither.

## Consequences

- **A rebuild in Glance changes nothing here.** The next plan stays empty.
- **Changing the image replaces every instance**, nodes included, in a single plan. Once etcd
  runs on them, that change has to be rolled one node at a time.
- **The image ages.** Security updates come from `unattended-upgrades`, which is enabled in the
  image and was seen completing its daily runs, not from upgrading packages at boot, which would
  make two identical nodes differ by their creation date.
- **The pin relies on a practice, not a promise.** Infomaniak has kept hidden builds for more
  than two years, but nothing states it will. If the pinned build disappears, the instances
  that exist keep running; creating a new one fails at the precondition, loudly.
- **The check is on the name.** It proves the ID is a build of the expected image, not what the
  build contains.
- **Every plan reads Glance twice more.** Two list calls, one of them returning every hidden
  build.

## Alternatives considered

**Look the image up by name, most recent first.** Rejected: every rebuild would replace the
cluster.

**Look it up by name and ignore later changes of `image_id`.** Rejected. The plan would stay
empty while nodes created on different dates ran different builds, and the configuration would
no longer say what runs.

**Upload a reference image into the project.** A copy owned by the project would never be
hidden or deleted by anyone else, and storing it costs almost nothing. Rejected for now: it
moves the work of following Ubuntu's releases onto this project, for a risk that two years of
hidden builds have not materialised.
