# `modules/network`

The VPC, its subnets, and everything that decides where a packet goes. One
module for all three environments, because a staging environment that differs
from production in its code rather than in its arguments is not testing
production.

Nothing here names an environment. `dev` is a `name_prefix` and a `vpc_cidr`
handed in by [`live/dev/network`](../../live/dev/network/).

## Interface

| Argument | Type | Default | What it decides |
| --- | --- | --- | --- |
| `name_prefix` | string | — | The `Name` tag on every resource. Normally `linkforge-<environment>` |
| `vpc_cidr` | string | — | The address range, and by derivation every subnet in it |
| `az_count` | number | `2` | How many zones the subnets spread across |
| `nat_gateway_count` | number | `0` | `0`, `1`, or `az_count`. Nothing else is meaningful |
| `interface_endpoint_az_count` | number | `0` | How many zones get SSM interface endpoints. `0` creates none |
| `tags` | map | `{}` | Extra tags. The provider's `default_tags` already carry the project-wide four |

Two of these are fixed for the life of the VPC. `vpc_cidr` cannot be changed at
all — a correction destroys the VPC and everything holding an address in it.
`az_count` can be raised, and the address plan below is what makes that safe.

The last two default to `0` together, which the module rejects. An environment
with no NAT gateway and no interface endpoints has no route from its private
subnets to the AWS APIs, and it is the kind of mistake that applies cleanly:
every resource builds, every instance is unreachable, and the plan says nothing.
A caller has to state how its private subnets reach AWS.

## Addresses are derived, not passed

Subnet CIDRs are computed from `vpc_cidr` with `cidrsubnet`. The alternative is
passing explicit lists from each stack, which puts the same arithmetic in three
places and invites one of them to be wrong.

The derivation has one trap, and avoiding it is the reason for the constant
`max_azs = 4`. The obvious version computes the width of a subnet from
`az_count` — enough bits for exactly the zones in use. It works, and then the
day a third zone is added every subnet is re-derived at a new address, and
Terraform destroys and recreates all of them along with anything holding an
address in them. The width has to be a constant.

So four extra bits give sixteen blocks, allocated four to a tier:

| Tier | Index range | `dev`, from `10.0.0.0/16` |
| --- | --- | --- |
| Public | 0–3 | `10.0.0.0/20`, `10.0.16.0/20`, … |
| Private | 4–7 | `10.0.64.0/20`, `10.0.80.0/20`, … |
| Reserved | 8–11 | Unused |
| Reserved | 12–15 | Unused |

A `/20` is 4094 usable addresses, which is more than a public subnet holding one
load balancer and one NAT gateway will ever want. Uniformity is worth more than
the saving: the rule is `tier * 4 + zone` and it stays true whatever is built.

Raising `az_count` from 2 to 3 now adds one subnet per tier and moves none of
the existing ones. Tier 2 is where a database subnet group lands at `v8-scale`,
below everything already allocated.

`stage` and `prod` derive the same shape from `10.1.0.0/16` and `10.2.0.0/16`.

## NAT is a count, and the route tables follow it

`live/README.md` commits the three environments to three different answers, and
a boolean can only hold two of them.

| | `nat_gateway_count` | Private route tables | Default route |
| --- | --- | --- | --- |
| `dev` | `0` | One, shared | **None** |
| `stage` | `1` | One, shared | To the single gateway |
| `prod` | `az_count` | One per zone | To the gateway in the same zone |

Prod needs a table per zone because a shared table cannot say "route to the
gateway in your own zone". Point every zone at one gateway and a zone failure
takes down subnets in zones that are still healthy, and every byte that survives
crosses a zone boundary and is billed for it.

The interesting column is dev's. Zero gateways means zero default routes, so
dev's private subnets have **no path off the VPC at all**. That is the design
and not an omission: everything they reach, they reach through a VPC endpoint,
and anything without an endpoint is unreachable rather than slow. A NAT gateway
would hide that distinction behind a default route, and hide about $33 a month
behind it too.

`nat_gateway_count` is validated against `[0, 1, az_count]`. Two gateways across
three zones has no defined meaning — it does not say which two zones get one, or
which table the third zone uses — so it is rejected rather than resolved by
whatever the `count` arithmetic happens to do.

## The resource graph

```
aws_vpc
 ├── aws_internet_gateway
 ├── aws_subnet.public   [az_count]  ──┐
 │    └── aws_route_table.public ──── aws_route → internet gateway
 ├── aws_subnet.private  [az_count]  ──┤
 │    └── aws_route_table.private [1 or az_count]
 │         └── aws_route → NAT gateway   (absent when the count is 0)
 ├── aws_eip.nat [n] ── aws_nat_gateway [n] ── sits in a public subnet
 │
 ├── aws_security_group.endpoints ── 443 in from the VPC CIDR, nothing out
 ├── aws_vpc_endpoint.interface [3, when the count is not 0]
 │        └── an ENI in the first N private subnets, per service
 └── aws_vpc_endpoint.s3 ── attaches to the private route tables, not a subnet
```

Two edges in that graph are not visible in it.

**`aws_nat_gateway` declares `depends_on` the internet gateway.** A NAT gateway
needs a route to the internet when it is created, and the only connection
between the two resources runs through a route table that Terraform is free to
build in parallel. Without the dependency the apply fails intermittently, which
is worse than failing.

**`aws_vpc` sets both DNS attributes** because of something that does not exist
yet. An interface endpoint's private DNS works by overriding the service's
public hostname inside the VPC, and it cannot do that unless the VPC resolves
hostnames. Setting them now is free. Discovering they are unset is a debugging
session in which the SSM agent quietly times out against a public address.

## Endpoints, and why there are two unrelated kinds

Both are `aws_vpc_endpoint`. They have almost nothing else in common.

| | Gateway | Interface |
| --- | --- | --- |
| What it is | An entry in a route table | An ENI in a subnet, with a private IP |
| Attaches to | Route tables | Subnets |
| Security group | None — the concept does not apply | Required |
| Services | S3 and DynamoDB only | Everything else |
| Cost | **Free** | **Per endpoint, per zone, per hour** |

The S3 gateway endpoint is created in every environment, because free is free.
The SSM agent pulls its own updates and some plugin binaries from S3, so without
it dev works until the day the agent tries to update itself.

### The three interface endpoints

`ssm` is the control API — registration and commands. `ssmmessages` is the
Session Manager data channel, which carries the shell session itself.
`ec2messages` is the older agent-to-service channel, still used during
registration. Missing any one leaves the host half-working, which is harder to
diagnose than a host that does not work at all.

### `private_dns_enabled` is the whole thing

Without it the endpoints exist, are billed, and are used by nothing. The agent
resolves `ssm.<region>.amazonaws.com` to a public address, has no route to it in
dev, and times out. The instance never registers and never appears in Session
Manager, and there is no error anywhere that names the cause.

It also depends on `enable_dns_support` and `enable_dns_hostnames` being set on
the VPC, which is why `main.tf` sets both for a reason that did not exist yet
when it was written.

### The cost, which is the reason for a separate count

An interface endpoint is billed **for each zone it is placed in**. Three
endpoints across two zones is about $44 each month; one NAT gateway is about
$33. So "endpoints instead of a NAT gateway" is cheaper in a one-zone diagram
and dearer in a two-zone one, and the claim has to be checked rather than
repeated.

`interface_endpoint_az_count` is what makes it true. dev sets it to `1` — about
$22 — while `az_count` stays at `2`, because the load balancer will not accept
one subnet and a subnet costs nothing anyway. The endpoints are taken from the
front of the private tier, so zone `a` gets them.

A host in zone `b` still reaches an endpoint in zone `a`: private DNS is
VPC-wide and resolves to whatever ENIs exist. The traffic crosses a zone
boundary and is billed for it at a rate that does not matter here. What the
single zone actually costs is availability — lose zone `a` and dev loses SSM
access entirely. That is the right trade in an environment rebuilt daily and the
wrong one anywhere else.

## Outputs

| Output | Consumed by |
| --- | --- |
| `vpc_id` | Every security group and endpoint built on this network |
| `vpc_cidr_block` | The endpoint security group's source range, step 3 |
| `availability_zones` | Ordering for the subnet lists |
| `public_subnet_ids` | The load balancer, step 5 |
| `private_subnet_ids` | The host, step 4. The interface endpoints, step 3 |
| `private_route_table_ids` | The S3 gateway endpoint, step 3 — it attaches to route tables, not subnets |
| `public_route_table_id` | The same, if anything public ever needs S3 |
| `nat_gateway_public_ips` | Empty in dev. The addresses an egress allowlist would name |
| `endpoint_security_group_id` | A rule written against the endpoints rather than against the network |
| `interface_endpoint_dns_names` | Debugging. Compare what the endpoint claims to what the host resolves |

`vpc_cidr_block` is read back off the resource rather than echoed from the
variable, so the output stays true to what AWS holds rather than to what was
asked for.

## Not in this module

The host is step 4 and the load balancer is step 5; both belong elsewhere. The
load balancer in particular gets its own module, because at `v2-fargate` its
target group points at an ECS service and it becomes part of the service rather
than part of the network.
