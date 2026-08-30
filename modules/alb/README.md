# `modules/alb`

One internet-facing application load balancer, one target group that health
checks `/health`, one HTTP listener, and the pair of security group rules that
lets the first reach the last. It is the front door to everything the
application will ever serve, built one milestone before there is an application
to serve.

Nothing here names an environment. `dev` is a `name_prefix`, two public subnet
IDs, a list of source ranges and the host's security group, handed in by
[`live/dev/network`](../../live/dev/network/).

## This module outlives the host it points at

[`modules/ssm-host`](../ssm-host/) is deliberately temporary and says so. This
one is the opposite: the load balancer, its security group and its listener are
the same resources at `v2-fargate`, at `v7-edge` and at the end of the project.

What changes at `v2-fargate` is the target and only the target. `target_type`
moves from `instance` to `ip`, because a Fargate task has an ENI and no instance
ID; `target_instance_id` goes null and the attachment resource disappears with
it, because an ECS service registers and deregisters its own tasks and a static
attachment beside it would be removed and recreated on every deployment.

That is why `target_instance_id` is nullable rather than required, and it is why
the target group is written to survive being replaced. See below.

## Interface

| Argument | Type | Default | What it decides |
| --- | --- | --- | --- |
| `name_prefix` | string | — | The load balancer's name and every `Name` tag. Normally `linkforge-<environment>` |
| `vpc_id` | string | — | Where the security group and the target group live |
| `public_subnet_ids` | list(string) | — | Which zones the load balancer's nodes are placed in. At least two |
| `allowed_cidrs` | list(string) | — | Who may open a connection to the listener |
| `target_security_group_id` | string | — | The group this module writes an ingress rule into |
| `target_instance_id` | string | `null` | The instance to register. Null from `v2-fargate` onwards |
| `listener_port` | number | `80` | What the world connects to |
| `target_port` | number | `8080` | What the targets listen on, and what the health check uses |
| `health_check_path` | string | `/health` | The route checked. Must not read a datastore |
| `deregistration_delay` | number | `30` | Seconds before a removed target is actually gone |
| `tags` | map | `{}` | Extra tags. The provider's `default_tags` already carry the project-wide four |

`allowed_cidrs` has **no default**, and that is the same choice
[`modules/network`](../network/) makes with `nat_gateway_count` and
`interface_endpoint_az_count`. This is the only argument in the project that
decides what the public internet may open a connection to, so the stack states
it rather than inheriting a guess. `["0.0.0.0/0"]` is a legitimate answer; it is
just not one this module makes on the caller's behalf.

`public_subnet_ids` is validated at two or more because the API refuses one, and
that requirement is why [`modules/network`](../network/) keeps `az_count` at 2
even in `dev`, where the interface endpoints sit in a single zone. A subnet is
free. A second zone of endpoints is $22 a month.

## The security group pair is one decision and this module owns both halves

Two rules are needed and they reference each other's groups:

| Rule | Lives on | Points at |
| --- | --- | --- |
| `egress_rule.to_targets` | The load balancer's group | The target's group |
| `ingress_rule.targets_from_alb` | **The target's group** | The load balancer's group |

The second is written into a security group this module did not create. That
looks like a layering violation and it is the only arrangement that works.

If this module consumed `modules/ssm-host`'s security group output while that
module consumed this one's, Terraform reports a **cycle between the two
modules** — not between two resources. A module's outputs are a single node in
the graph, so any pair of modules that each read the other's output is circular
even when no individual resource is. One side has to own both rules, and the
load balancer is the side that knows what it forwards to.

This is also the reason [`modules/ssm-host`](../ssm-host/) uses standalone
`aws_vpc_security_group_*_rule` resources instead of inline blocks: Terraform
treats an inline rule set as authoritative and deletes anything it did not
write, so a group with an inline block could not have accepted this rule at all.
That decision was made at step 4 for the sake of this step.

**Two things are absent from the rules and are not missing.**

The targets need no new egress rule. Security groups are stateful, so the reply
to a health check travels back on the connection the load balancer opened — the
host's deliberately narrow egress list, 443 to the endpoints and 443 to the S3
prefix list, stays exactly as it was.

There is no cross-zone setting either. An application load balancer always
balances across zones and the attribute does not exist for it. So the host,
which sits in one private subnet, is reached from nodes in both public subnets.

## AWS names the target group and we name the load balancer

The asymmetry is deliberate and each half has a reason.

`aws_lb_target_group` uses `name_prefix = "lf-"` with
`create_before_destroy = true`, which is why the group's real name is
`lf-` and eight random characters rather than anything readable. `target_type`,
`port`, `protocol` and `vpc_id` are all force-new, and `v2-fargate` changes the
first of them. A replacement while the listener still forwards to the group is
refused as `ResourceInUse`, so the new group has to be created before the old
one is destroyed — and `create_before_destroy` needs a name AWS generates,
because two groups exist at the same moment and a fixed name would collide. The
prefix is capped at six characters, which is what makes it unreadable. The
`Name` tag carries the readable version.

`aws_lb` keeps an explicit `name`, because it is not going to be replaced and
because that string ends up inside the DNS name a human types.

## The listener is plain HTTP and that is not an omission

There is no HTTPS listener because there is no certificate, because there is no
domain name to put on one. ACM, Route 53 and the redirect all arrive together at
`v7-edge`.

The default action is a `forward` and specifically **not** a redirect to 443. A
redirect written now would send every request to a listener that does not exist
— a configuration that applies cleanly, plans clean forever, and returns a
connection error to every client.

`drop_invalid_header_fields = true` is on, against a default of false. The
default exists for clients that send malformed headers; this project has none.

## The resource graph

```
                       allowed_cidrs
                            │
                            ▼
aws_security_group.alb ── ingress_rule.listener  [one per CIDR]
 │                             :80
 │
 ├── egress_rule.to_targets ──────────► the target's security group  :8080
 │        └── referenced_security_group_id
 │
 └── (also creates, on a group it does not own)
     ingress_rule.targets_from_alb ◄── aws_security_group.alb        :8080

aws_lb.this  ── subnets          (public, from modules/network)
 │             └─ security_groups [aws_security_group.alb]
 │
 └── aws_lb_listener.http  :80
          └── default_action forward
                   │
                   ▼
          aws_lb_target_group.this   :8080  HTTP1  target_type=instance
           ├── health_check  GET /health, matcher 200
           └── aws_lb_target_group_attachment.instance  [0 or 1]
                    └── target_id  (from modules/ssm-host)
```

The attachment is the only counted resource, and it is what makes this module
work unchanged at `v2-fargate`.

## What a passing health check proves, and what an apply does not

`terraform validate` sees none of this. It checks references, types and syntax
inside the module and is silent on every part of the graph above that an AWS
API has to accept. A clean apply is barely better: every resource here can be
created successfully with the health check failing on every attempt.

The check that means something is:

```
aws elbv2 describe-target-health --target-group-arn <target_group_arn>
```

| State and reason | What it means |
| --- | --- |
| `healthy` | The whole path works: listener, group, rule, responder |
| `initial` | Fewer than two checks have run. Wait 60 seconds |
| `unhealthy` / `Target.Timeout` | The packet never arrived. The ingress rule this module writes is the suspect |
| `unhealthy` / `Target.FailedHealthChecks` | It arrived and the answer was wrong. The responder or the matcher |
| `unused` | Nothing is registered. `target_instance_id` was null |

The distinction between the two `unhealthy` reasons is the useful part, because
it separates a network fault from an application fault without logging into
anything.

The health check speaks HTTP/1.1, which is why the responder in
[`modules/ssm-host`](../ssm-host/) sets `protocol_version = "HTTP/1.1"` rather
than accepting Python's HTTP/1.0 default. `protocol_version = "HTTP1"` on the
target group here is the same fact stated from the other end.

## Two defaults that would have cost money or time

**`deregistration_delay` defaults to 300 seconds.** A destroy that should take a
minute takes six while a target group drains connections that do not exist. `dev`
is destroyed every night by step 9, and nothing a health responder serves is
worth draining, so it is 30.

**`enable_deletion_protection` is written as false rather than left out.** It is
already false by default. Writing it makes the claim checkable in the file,
because the failure mode of the other value is a nightly destroy that fails with
an error naming the load balancer rather than the setting that saved it.
