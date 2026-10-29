# What broke, and how it was fixed

How a platform fails and recovers says more about it than what it does on a good day. This page grows as the project does.

## A version constraint that OpenTofu never checked

A typo in `required_version`, the
operator `=>`, which does not exist, passed `tofu validate` without a word. Testing the edge
cases showed why: OpenTofu 1.12.5, the version used here, does not enforce a `required_version`
written in a `.tf` file. Even `">= 99.0.0"`, or plain garbage, passes `init` and `plan` there,
while the same constraint in a `.tofu` file stops the run with `Incompatible module`. The
[documentation](https://opentofu.org/docs/language/settings/) now describes that setting as
kept for compatibility with Terraform, and adds a `language` block for OpenTofu's own
constraints. The configuration in [`infra/`](../infra/) uses the `.tofu` extension, so its version
constraint is enforced.

## A CLI that showed the cluster's internal ports open to the internet

After the first
`apply`, `openstack security group rule list`, and `rule show` as well, printed `0.0.0.0/0` as
the remote side of the six rules scoped to the security group itself: etcd, kubelet, the
Kubernetes API, Flannel, ICMP and node-to-node egress. Neutron refuses a rule that sets both a
remote prefix and a remote group, so the display could not be literal. The raw API response
(`GET /v2.0/security-group-rules`) carries `remote_ip_prefix: null` for those rules, and the
OpenTofu state agrees: nothing was exposed. The client, python-openstackclient 10.3.0, fills
the empty field for display. Security group rules are now verified against the API response,
not against the client's table.

## A state lock the platform cannot take

With `use_lockfile = true`, `tofu plan` failed
before doing anything. OpenTofu takes that lock by writing an object with `If-None-Match: *`,
and Swift 2.30.1, which serves the S3 API here, answers every conditional write with `501
NotImplemented`: "Conditional object PUTs are not supported." The header is checked before the
signature, so the same answer comes back for a key that does not exist, which made it possible
to confirm without any credential. Upstream Swift accepts the header from 2.36.0. Until the
platform runs it, the state has no lock, and
[ADR 0006](adr/0006-store-the-state-in-swift-without-a-lock.md) says what stands in.

## An S3 key the automation was not allowed to create

`openstack ec2 credentials create`,
run with the application credential, was refused: "Using method 'application_credential' is
not allowed for managing additional application credentials." The message matches a check
Keystone added to S3 key creation in April 2026 (bug 2142138), because a restricted credential
could otherwise create a key with all of its owner's rights. The key was created once with the
account password.

## A migration that restarted the state's history

After `tofu init -migrate-state`, the state
in Swift was at serial 1 with a new lineage, where the local one had been at serial 10. Every
resource was there: 21 entries, and an empty plan. On the first write to an empty backend,
OpenTofu 1.12.5 re-reads the destination, finds nothing, and resets the lineage and serial it
had just copied (`PersistState`, `internal/states/remote/state.go`). No harm done, but it is
worth knowing before comparing an old copy of the state with the live one.

## An argument the provider's schema advertised, and refused

The nodes pin their image by ID,
because Glance republishes its images under the same name: the Ubuntu 24.04 build of 14
September was replaced on 28 September, and looking it up by name would have replaced the whole
cluster at the next plan. Checking that ID failed first. The provider schema lists `id` as an
optional argument of the `openstack_images_image_v2` data source, and `tofu validate` rejected
it as an "Invalid or unknown key": that `id` is the field the plugin SDK adds to every data
source, 53 of the 54 here. The pinned ID is now checked against the builds carrying the expected
name, visible and hidden, which another data source can list.

## A firewall rule that k3s would have outranked

The servers had to keep their pods away from
the metadata service, which hands out the user data, join token included. The first design was a
rule in the node's `FORWARD` chain. Reading the code of k3s's network policy controller, an
embedded kube-router, before writing that rule showed why it would not hold: the controller
creates a firewall chain for every pod, even when no NetworkPolicy exists, inserts into `FORWARD`,
after its own rules, an `ACCEPT` for the traffic that passed it, and moves its own jump back to
the top of the chain at every sync. Whether the node's rule landed before or after that `ACCEPT`
would have depended on which started first. The rule lives in an nftables table of its own
instead, where a `drop` stands whatever another table accepts; see
[ADR 0012](adr/0012-pass-the-join-token-in-user-data.md).

## A cloud-init template that was not YAML

The servers' cloud-init became an OpenTofu template,
with `%{ if }` directives to tell the first server from the others. Indented like the YAML around
them, the directives kept their leading spaces, and the template engine added them to the next
line: the lines inside the condition came out with twice their indentation, the block meant to
become `config.yaml` ended after two lines, and the document no longer parsed. cloud-init cannot
apply a document that does not parse. Rendering the template with dummy values and parsing the
result, with `yq` and then `cloud-init schema` on a node, caught it before any server was
replaced. The directives now start at column 0.

## A load balancer that reported healthy members with nothing behind them

Right after the
health monitor of the 443 pool was created, before Traefik was installed, its three members
showed `ONLINE`, while those of the 80 pool had been in `ERROR` for minutes. Nothing listened on
that port: `ss` on a node found no socket on 30443. A minute later, they turned `ERROR` as well.
A new monitor reports its members up for about a minute after it is created, so a green load
balancer proves nothing until then. The members are now read minutes after Traefik starts, and
the [cluster services runbook](runbooks/cluster-services.md) says so.

## An application that would never turn healthy

Once Argo CD delivered the demo, the site
answered and its certificate was issued, yet Argo CD kept reporting the demo as progressing, and
the root application with it. The `Ingress` was the holdout: Argo CD calls an `Ingress` healthy only
once its status carries an address, and this one carried none. Traefik fills that status by
copying its own Service's, and its Service is a `NodePort`, with no address to copy: the address
lives on the Octavia load balancer, outside the cluster. Traefik now publishes the stable public
address itself (`ingressEndpoint.ip`), with the copy disabled; left on, both settings reached
Traefik. The demo turned healthy, and the address joined the values written on both sides of the
line between OpenTofu and Argo CD; see [ADR 0017](adr/0017-draw-the-line-between-opentofu-and-argo-cd.md).

## A self-healing cluster that left a manual change in place

Scaled by hand to three replicas,
the demo stayed at three for minutes, with self-healing on. Its Deployment did not declare a
replica count: Kubernetes had filled one in, and Argo CD enforces only what the manifest declares.
Its own best practices leave `replicas` out of Git on purpose, when an autoscaler owns it. Nothing
in Git contradicted three replicas, so there was nothing to heal. The manifest now declares one,
and the same command is undone.

## A cloud-init error on a healthy cluster

After the rebuild of 2026-10-11, `cloud-init status`
read `error` on two of the three servers, while all three nodes were `Ready`. Both had started k3s
a few seconds before the first server listened, and k3s exited at once: "failed to get CA certs
… connection refused". The installation script, which starts the service, failed with it, and so
did cloud-init's `runcmd`. systemd restarted k3s, and the two servers joined 17 and 31 s after the
first one was ready. On the build measured on 2026-10-02, the joining server had started two
seconds after the first, and nothing restarted. A node's state is now read from the cluster, not
from cloud-init; see the amendment to [ADR 0013](adr/0013-install-k3s-from-cloud-init.md).
