# `modules/ssm-host`

One EC2 instance in a private subnet, an HTTP responder on `/health`, and a
security group with no inbound rule. It exists to prove a claim that
[`modules/network`](../network/) can only assert: that a machine with no public
address, no key pair and no open port is reachable, and that the interface
endpoints are what makes it so.

Nothing here names an environment. `dev` is a `name_prefix`, a subnet, and a
security group ID handed in by [`live/dev/network`](../../live/dev/network/).

## This module is temporary and that is the design

The host is replaced by an ECS service at `v2-fargate`, which is why it is a
separate directory rather than three more resources inside `modules/network`.
Removing it is deleting one folder and one `module` block. Folded into the
network graph it would have to be unpicked from it instead, in the milestone
with the most other things going on.

What survives the deletion is the shape of the thing: a private subnet, an
instance profile as the entire access mechanism, an egress rule naming the far
end, and a `/health` route on port 8080 that a target group can check. The
container at `v2-fargate` inherits all four.

## Interface

| Argument | Type | Default | What it decides |
| --- | --- | --- | --- |
| `name_prefix` | string | — | The `Name` tag on every resource. Normally `linkforge-<environment>` |
| `vpc_id` | string | — | Where the security group lives |
| `subnet_id` | string | — | Which private subnet, and so which zone |
| `instance_profile_name` | string | — | `linkforge-ssm-host`, from `account/workload_roles.tf` |
| `endpoint_security_group_id` | string | `null` | How the host reaches the AWS APIs. Set means endpoints; null means a NAT gateway |
| `instance_type` | string | `t3.micro` | Matched to the AMI's architecture, which is x86_64 |
| `health_port` | number | `8080` | What the responder binds and [`modules/alb`](../alb/) health checks |
| `tags` | map | `{}` | Extra tags. The provider's `default_tags` already carry the project-wide four |

`subnet_id` is singular and it is the caller that indexes the list. That is
deliberate: `dev` passes `private_subnet_ids[0]`, which is the zone its
interface endpoints are in, and a module that picked `[0]` for itself would
hide that decision. Moving it to `[1]` is a test that private DNS is VPC-wide
rather than an accident of ordering — see below.

`instance_profile_name` is a name and not an ARN, and the stack resolves it
with `data "aws_iam_instance_profile"` rather than reading `account/`'s state.
A missing `account/` apply then fails at plan with *no matching instance
profile*, instead of at boot with an instance that never registers and no error
anywhere naming the cause.

## There is no ingress rule

Not a narrow one. None. The security group is created with no inline `ingress`
block and no `aws_vpc_security_group_ingress_rule` resource, so nothing in this
account — nothing on the internet, nothing in the VPC, nothing in the same
subnet — can open a connection to this host.

It is still reachable, and the mechanism is `AmazonSSMManagedInstanceCore` on
the instance profile. The agent dials **out** to Session Manager and the
session runs back down the connection it made. Reachability is an IAM decision
here, not a network one, which is the single thing this module is built to
demonstrate.

Two consequences worth stating rather than discovering:

- **There is no key pair anywhere in this project.** `key_name` is absent from
  `aws_instance` on purpose. Losing SSM access means rebuilding the host, and
  there is no SSH fallback to reach for. That is the intended failure mode of a
  machine that is destroyed nightly.
- **[`modules/alb`](../alb/) adds the first inbound rule this group has ever
  had**, from the load balancer, on `health_port` — and it adds it from over
  there rather than from here. That is why the rules in this module are
  separate resources; see below.

## Egress is where the environments differ

The host has to reach three SSM services and S3. *How* it reaches them is the
one thing that is not the same in `dev` as in `stage` and `prod`, and it
arrives as an argument rather than as two copies of the module.

| | `endpoint_security_group_id` | Rules created |
| --- | --- | --- |
| `dev` | The network module's endpoint group | 443 to that group, 443 to the S3 prefix list |
| `stage`, `prod` | `null` | 443 to `0.0.0.0/0`, 443 to the S3 prefix list |

The asymmetry is real and not a modelling convenience. With interface
endpoints the far end of the connection is an ENI in this VPC, so it has a
security group and the rule can name it — the tightest egress rule in the
project, and it only exists because both ends belong to this account. With a
NAT gateway the far end is the public internet, and a security group can name
nothing but a CIDR.

Which is worth reading twice, because it inverts the cost table: the
environment that pays for a NAT gateway ends up with the *looser* egress rule,
and the cheap one ends up with the tighter. Endpoints are a security control
that happens to be priced like a network one.

### Three things are missing from those rules and belong nowhere

The list above is 443 and nothing else. No DNS, no NTP, no metadata. All three
work anyway, because none of them is filtered by a security group:

| Traffic | Destination | Why no rule |
| --- | --- | --- |
| DNS | The VPC resolver, at the VPC base address plus two | Security groups do not filter traffic to the Amazon-provided DNS server |
| Instance metadata | `169.254.169.254` | Link-local. Answered by the hypervisor, never on the network |
| Clock | `169.254.169.123`, Amazon Time Sync | Link-local, same reason |

DNS is the one that matters here, and it matters more than it would anywhere
else. `private_dns_enabled` on the interface endpoints is the entire mechanism
by which this host reaches SSM — resolution is not a supporting detail, it is
the thing. So the egress rules read as complete while silently resting on a
resolver that appears in none of them, and a reader checking whether the list
is sufficient has no way to tell from the file. Hence this table.

### The S3 rule is a prefix list, and it is not optional

Traffic to a **gateway** endpoint is matched against the security group by
prefix list, not by CIDR — the destination is still S3's public address range,
and a rule written against `0.0.0.0/0` or against the VPC CIDR does not cover
it. `data "aws_ec2_managed_prefix_list"` resolves
`com.amazonaws.<region>.s3` to the ID AWS maintains.

Leaving it out fails in the worst available way. The agent registers, Session
Manager works, and the environment looks correct — until the agent tries to
update itself or fetch a plugin binary out of S3, at which point it fails with
nothing in any log naming S3 as the destination that was refused.

The rule is unconditional because the S3 gateway endpoint is unconditional:
`modules/network` creates it in every environment, since it is free. In an
environment already allowing 443 to `0.0.0.0/0` it is redundant, and it stays
anyway — it says what the traffic is for, and it is the rule that keeps working
if the blanket one is ever narrowed.

### Rules are separate resources, unlike the endpoint group

[`modules/network/endpoints.tf`](../network/endpoints.tf) uses an inline
`ingress` block, which is correct there because nothing outside that module
ever adds to it.

This group is different. [`modules/alb`](../alb/) allows egress from the load
balancer's group to *this* group while this group allows ingress from *that*
one, and two inline blocks referencing each other is a dependency cycle
Terraform refuses to resolve. `aws_vpc_security_group_egress_rule` — one rule
per resource — is what made step 5 an addition rather than a rewrite, and an
inline block here would have been worse than a cycle: Terraform treats an
inline rule set as authoritative and deletes anything it did not write, so the
load balancer's rule would have been created and then removed on the next
apply.

Inline blocks and rule resources on the same security group fight: Terraform
treats the inline set as authoritative and deletes anything it did not write.
Pick one per group. This one has picked.

## The resource graph

```
data aws_ssm_parameter.al2023 ──────────► aws_instance.this
data aws_ec2_managed_prefix_list.s3 ──┐        │
                                      │        ├─ iam_instance_profile  (from account/)
aws_security_group.host               │        ├─ subnet_id             (from modules/network)
 ├── egress_rule.endpoints  [0 or 1] ─┼────────┴─ vpc_security_group_ids
 │      └── referenced_security_group_id  ── the endpoint ENIs
 ├── egress_rule.internet   [1 or 0]
 │      └── cidr_ipv4 0.0.0.0/0           ── through the NAT gateway
 └── egress_rule.s3         [always]
        └── prefix_list_id                ── the S3 gateway endpoint

                          (no ingress rule of any kind)
```

The two counted rules are mutually exclusive: exactly one is created, and which
one is the only structural difference between `dev` and `prod` in this module.

## Two `aws_instance` defaults that silently do nothing

Both are the same failure shape — an apply that succeeds and changes nothing.

**`user_data` runs once, at first boot.** Editing the script updates the
attribute in state, reports success, and leaves the running machine exactly as
it was. `user_data_replace_on_change = true` is what makes an edit reach the
host, by replacing the instance. Without it the responder can be several edits
behind the repository with a clean plan the whole time.

**The AMI moves under you.** The public SSM parameter is repointed at every
AL2023 release, so the next unrelated apply proposes destroying and recreating
the host for reasons that have nothing to do with the change under review.
`lifecycle { ignore_changes = [ami] }` pins it to whatever was current at
create time.

What that costs is patching. The host never picks up a new AMI on its own; it
takes an explicit `terraform apply -replace`. That is the right way round for a
machine — and it is barely a cost here, because step 9 destroys and rebuilds
`dev` nightly, so the host is never more than a day older than the parameter.

`nonsensitive()` on the parameter is also deliberate. The data source marks
every value sensitive because it cannot know which parameters are secrets; this
one is a public AMI ID, and it is the single most useful line in the plan
output. Unwrapping it is the difference between reading which image you are
about to launch and reading `(sensitive value)`.

## What the host actually runs

A Python `http.server` on `health_port`, under a systemd unit, started by
`user_data`. `200 ok` on `/health` and `404` on everything else.

The handler sets `protocol_version = "HTTP/1.1"`, and that is not a default.
`BaseHTTPRequestHandler` speaks HTTP/1.0 unless told otherwise, so without the
line an ALB's HTTP/1.1 health check receives a 1.0 answer and opens a fresh TCP
connection every thirty seconds forever. Whether a target group rejects that was
never established — the line exists to make the question not arise.

It is safe only because every response sets `Content-Length`. Under 1.1 a
response without one does not error, it hangs the client until a timeout, so
that header is load-bearing and any branch added later has to set it. The
`timeout = 5` beside it is the other half of the same change: under 1.0 every
connection closed after a single response, and under 1.1 with keep-alive a
connection holds its thread until the client goes away.

Nothing in the script installs a package. That is not thrift — `dev` has no
default route, so a `dnf install` does not fail, it hangs until cloud-init
times out. Python 3 and the SSM agent are both preinstalled on AL2023, and the
module depends on exactly that.

The unit runs `DynamicUser=yes`, which is why `health_port` is validated above
1024: a transient unprivileged user cannot bind a privileged port. The default
request logger is suppressed, because a target group polling every thirty
seconds writes one line to the journal every thirty seconds forever.

`set -x` is on. Output lands in `/var/log/cloud-init-output.log`, and that file
is the first place to look when the instance registers in Session Manager and
`/health` does not answer — the two are independent, and this is the module
where that becomes obvious.

One trap in the template: the heredocs are quoted (`<<'PY'`), which stops
**bash** expanding anything inside them. It does not stop Terraform, which runs
`templatefile` over the whole file first — which is exactly why `${health_port}`
resolves. Unquoting either heredoc would let a `$` in the Python leak into the
shell.

## One argument whose behaviour is unverified

`encrypted = true` on the root volume is redundant in `us-east-1`, where
[`account/baseline.tf`](../../account/baseline.tf) turned on EBS encryption by
default. It is written anyway, because a module should state what it requires
rather than inherit it from an account setting it cannot see.

What it is **not** is a safeguard for `v10-resilient`'s second region, which is
what this argument was originally justified as. `RunInstances` with
`Encrypted=true` on a root device mapping from an unencrypted snapshot — which
the AL2023 AMI is — may be accepted only *because* encryption by default is
enabled in the region. If that is so, this line does nothing here and is
precisely what fails the launch in a region without the setting.

Untested in either direction, and deliberately left that way rather than
resolved with something that looks like a test. `run-instances --dry-run`
checks permissions and returns `DryRunOperation` without fully validating the
request, so a pass would prove nothing about the behaviour in question. The
real test is one hand-launched instance in a region with the setting off, and
it belongs at the start of `v10-resilient` rather than here.

## Zones, and what the single-zone endpoint costs

`dev` places its interface endpoints in one zone to halve their bill, and puts
the host in that same zone by passing `private_subnet_ids[0]`.

The host does not have to be there. Private DNS is VPC-wide, so an instance in
zone `b` resolves `ssm.<region>.amazonaws.com` to the ENI in zone `a` and the
session works; the traffic crosses a zone boundary and is billed at a rate that
does not matter at this size. Passing `[1]` instead is a one-character
experiment that proves it, and it is worth running once.

What the single zone actually costs is availability. Lose zone `a` and `dev`
loses SSM access entirely, wherever the host is. That is the right trade in an
environment rebuilt daily and the wrong one anywhere else, which is the whole
argument for `interface_endpoint_az_count` being a separate number from
`az_count`.

## Outputs

| Output | Consumed by |
| --- | --- |
| `instance_id` | `aws ssm start-session --target`, and [`modules/alb`](../alb/)'s target group |
| `private_ip` | The host's only address. There is no public one |
| `availability_zone` | Compare against the endpoint zones. Different is fine and costs a cross-zone hop |
| `security_group_id` | [`modules/alb`](../alb/), which adds this group's first ingress rule |
| `health_port` | The target group's port and health check |

## Not in this module

The load balancer is step 5 and gets its own module, because at `v2-fargate`
its target group points at an ECS service and it becomes part of the service
rather than part of the network.

The IAM role and instance profile are in [`account/`](../../account/), not
here, and that placement was found rather than chosen. Every CI apply role
carries a permanent deny on `iam:Create*`, `iam:Attach*` and `iam:Add*`, which
covers `CreateRole`, `AttachRolePolicy`, `CreateInstanceProfile` and
`AddRoleToInstanceProfile`. A stack that created its own profile would apply
from a laptop and fail from the pipeline — the worst of the two outcomes,
because it works for whoever wrote it.
