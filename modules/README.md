# `modules/`

Reusable module definitions. Environment-agnostic by construction: no
environment name, no CIDR, no instance count, and no account ID appears as a
literal in here. Everything that differs between `dev`, `stage` and `prod`
arrives as an argument from the caller.

The test is mechanical. If a module cannot produce prod by changing its
arguments alone, prod is not being tested by staging, and the difference will be
discovered on the day it matters.

That test says nothing about who the caller is, and since `v2-fargate` there are
two answers. Three of these modules are called once per environment, from a root
module in [`../stacks/`](../stacks/) that a Terragrunt unit in
[`../live/`](../live/) supplies arguments to. `ecr/` is called once in total,
from [`../account/`](../account/), because the artifact it holds is the one
thing the three environments must not each own a separate copy of. Being
environment-agnostic is what lets a module be called either way; it was never a
claim that every module is called three times.

Four modules are implemented across `v1-network` and `v2-fargate`:

| Module | What it is |
| --- | --- |
| [`network/`](network/) | The VPC, its subnets, its endpoints, and everything that decides where a packet goes |
| [`ssm-host/`](ssm-host/) | One instance in a private subnet with no inbound rule, reachable over Session Manager |
| [`alb/`](alb/) | The front door. A load balancer, a target group that health checks `/health`, and the rules that connect the two |
| [`ecr/`](ecr/) | The shared container image repository and its storage lifecycle policy |

Each of them also validates standalone — `validate` needs no variable values and
no credentials — which is the only check a module gets in the window between
being written and first being called. It catches syntax, types and references,
and nothing an AWS API has to refuse.

The four have different lifespans, and it is worth knowing which is which
before deciding where a resource belongs.

`ssm-host/` is deliberately temporary. The host it builds is replaced by an ECS
service at `v2-fargate`, and it is a separate directory rather than three more
resources in `network/` so that removing it is a deletion rather than an
unpicking.

`alb/` is the opposite. Its load balancer, security group and listener are the
same resources at `v2-fargate` and at the end of the project; only the target
changes, from an instance to an ECS service. That is why it is a third
directory rather than resources inside `network/` — a module whose contents
outlive the milestone that wrote them should not be entangled with one whose
contents do not.

`alb/` also breaks the rule that a module only writes to resources it creates:
it puts an ingress rule on the target's security group. A pair of modules that
each read the other's output is a cycle at the module level, so one side owns
both halves of the rule pair. [`alb/README.md`](alb/README.md) has the detail.

`ecr/` is shared rather than environment-specific. A build is verified in dev
and promoted to stage and prod by digest, so all three environments run the
same bytes. `account/` owns it because no environment should own another one's
image supply. Its lifecycle policy removes untagged images without guessing
which tagged digest a running environment still needs.
