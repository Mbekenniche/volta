# What broke

How the platform failed, and what changed because of it.

## A state lock the platform cannot take

With the lock on, `tofu plan` failed at once: OpenTofu locks by writing an object with
`If-None-Match: *`, and Swift 2.30.1 answers every conditional write `501 NotImplemented`. The
state runs without a lock, and [ADR 2](adr/0002-store-the-state-in-swift-without-a-lock.md) says
what stands in.

## A CLI that showed the cluster's ports open to the internet

`openstack security group rule list` printed `0.0.0.0/0` for the rules scoped to a security group:
etcd, the kubelet, the API. The raw API said `remote_ip_prefix: null`, and so did the state; the
client fills the empty field for display. Rules are now checked against the API, not the table.

## A health monitor refused for a type that was fine

Every fresh build failed its first apply on a health monitor: "TCP is not a valid option for
type". Octavia reports any database error during a monitor's creation that way, whatever the
type. The monitors were created while the pools' members were being added; they now wait for
the members, and the next build took one apply.

## A rule on `main` that let a red pull request through

The rule protecting `main` was saved without its required checks. A test pull request with a
duplicated key in Traefik's values failed its checks, merged anyway, and Argo CD turned Traefik
into a one-replica Deployment for six minutes, until a revert. The checks are now required.

## A destroy that forgot half the platform

`make down` timed out on the router's interface. Two servers, the bastion and the load balancer
were still running, without a delete request, but no longer in the state: it had shrunk from
91 to 43 KB at the destroy's first write. They were deleted by hand. The cause is not found;
what is left is now listed after every destroy.
