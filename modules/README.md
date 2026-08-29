# `modules/`

Reusable module definitions. Environment-agnostic by construction: no
environment name, no CIDR, no instance count, and no account ID appears as a
literal in here. Everything that differs between `dev`, `stage` and `prod`
arrives as an argument from the calling stack in [`../live/`](../live/).

The test is mechanical. If a module cannot produce prod by changing its
arguments alone, prod is not being tested by staging, and the difference will be
discovered on the day it matters.

Two modules today, both from `v1-network` and neither of them called yet:

| Module | What it is |
| --- | --- |
| [`network/`](network/) | The VPC, its subnets, its endpoints, and everything that decides where a packet goes |
| [`ssm-host/`](ssm-host/) | One instance in a private subnet with no inbound rule, reachable over Session Manager |

Nothing calls either until `live/dev/network` exists, so the only thing checking
them is `terraform validate` on every pull request. A module directory validates
standalone — `validate` needs no variable values and no credentials — which
catches syntax, types and references, and nothing an AWS API has to refuse.

`ssm-host/` is deliberately temporary. The host it builds is replaced by an ECS
service at `v2-fargate`, and it is a separate directory rather than three more
resources in `network/` so that removing it is a deletion rather than an
unpicking.
