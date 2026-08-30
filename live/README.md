# `live/`

One directory per environment, one subdirectory per stack:

```
live/<environment>/<stack>/
```

Since step 8, a directory here is a **Terragrunt unit**, not a Terraform root
module. It holds one `terragrunt.hcl` and no `.tf` at all.

The root module every unit runs is [`stacks/network`](../stacks/network/), which
composes the three modules in [`modules/`](../modules/). The unit supplies
arguments; [`root.hcl`](root.hcl) supplies everything derivable from the unit's
own path — the state key, the `Environment` tag, and the stack source. So
`live/dev/network` and `live/prod/network` run identical code and differ only in
`inputs`, which is what "a staging environment that differs from production in
its code is not testing production" means in practice rather than as an
intention.

Nothing derived is written into these directories. Terragrunt generates
`backend.tf` and `provider.tf` into `.terragrunt-cache`, and the repository is
copied there on every run, which is why the module paths inside `stacks/network`
resolve at all.

`v1-network` wrote the first three: [`dev/network`](dev/network/), [`stage/network`](stage/network/) and [`prod/network`](prod/network/). Each calls the same three modules and differs only in its arguments.

## What is applied

| Environment | Applied | Reachable from CI |
| --- | --- | --- |
| `dev` | Built on demand, then destroyed | Yes |
| `stage` | No — configuration only | No |
| `prod` | No — configuration only | No |

`dev` is not standing. It was built end to end by the pipeline on 2026-08-30,
verified, and destroyed the same evening; the state file is still there with a
lineage and a serial and no resources in it. That is the intended steady state
until step 9 makes the teardown automatic — every cost in this milestone is
hourly, so the number that decides the bill is how many hours the environment
existed, and nothing in any `.tf` file decides that.

An empty state file is not the same as no state file, and the difference
matters on the next apply: the lineage is what lets Terraform recognise the
state as the same one rather than refusing to write over a stranger's.

Stage and prod are written and checked but never built. That is a deliberate
cost decision, not an unfinished one: three environments of `v1-network` is
about $150 a month standing against a $10 budget, and the point of writing all
three now is that the shape is fixed before the first `terraform apply`, not
retrofitted after it.

What makes stage and prod unreachable is not a comment or a missing file. It is
that their GitHub Environments do not exist, so GitHub will not mint a token
carrying `:environment:prod`, so `linkforge-gha-apply-prod` cannot be assumed by
anyone — including by a workflow that asks for it. The IAM role exists. It is
inert. See [RUNBOOK.md](../RUNBOOK.md), operation 5.

The cost of this is worth stating plainly. `terraform validate` on every pull
request catches syntax, type and reference errors in an environment nobody
builds. It cannot catch an IAM denial, a service quota, an unavailable
availability zone, or a name that collides with something already in the
account. The first `stage` apply will be a debugging session, not a formality —
the same shape as reading a trust policy back from IAM and learning nothing
about whether GitHub would ever send that string.

## How a change reaches an environment

```
merge to main ─────────────────► dev
                    │
                    └─ cut release/x.xx ──► stage ──► prod
                                                  (reviewer)
```

| Environment | Deployment branches | Gate |
| --- | --- | --- |
| `dev` | `main` | None |
| `stage` | `release/*` | None |
| `prod` | `release/*` | Required reviewer |

`release/*` is a name pattern, not a regular expression: its `*` does not cross
a `/`, so it matches `release/1.02` and not `release/1.02/hotfix`. There is no
way to express "two digits, a dot, two digits" in a deployment branch rule, and
that is not what makes this safe.

What makes it safe is worth stating plainly, because the diagram hides it. Stage
and prod share a branch pattern, so the branch is not what separates them — the
required reviewer on prod is. A commit that can reach stage can reach prod, and
one human stands between. The branch pattern decides which commits are
candidates; the reviewer decides which one ships.

Which makes the creation of a `release/*` branch the actual perimeter, and it is
closed with a repository ruleset restricting who may create one — not with
anything in this repository. That, the deployment branch rules, and the required
reviewer are all GitHub-side, and none of them is visible to AWS.

They have to be. A job that declares an environment gets a subject claim naming
the environment and *not* the ref: the environment replaces the branch segment
rather than joining it, so there is no branch left in the token for an IAM
condition to test. This is the one control in the project that Terraform cannot
express and a plan will never show. [RUNBOOK.md](../RUNBOOK.md), operation 5.

## State

One bucket, `linkforge-tfstate-749000381089`, for every environment. The key is
the path relative to this directory:

```
<environment>/<stack>/terraform.tfstate
```

so `live/dev/network` writes `dev/network/terraform.tfstate`, and the S3-native
lock sits beside it as `dev/network/terraform.tfstate.tflock`.

Since step 8 that sentence is enforced rather than merely true. The key is
`path_relative_to_include()` in [`root.hcl`](root.hcl), so it is the directory
path by construction and a unit cannot be pointed at another environment's
state by editing a literal. That was the strongest single argument for adopting
Terragrunt: a wrong state key is the one mistake in this repository that is
both silent and destructive, because a stack that adopts another environment's
state plans to destroy the difference.

Three buckets would mean three bootstraps, because a state bucket is the one
thing that cannot store its own state until it exists. The isolation that
matters is the write, and it comes from the prefix in the role policy rather
than from the bucket boundary: `linkforge-gha-apply-dev` is scoped to
`dev/*/terraform.tfstate` and cannot write prod's state whether or not prod's
state is somewhere else. Separate buckets begin to earn their keep when the
environments are in separate accounts, because a bucket policy is then the
cross-account boundary — and even then the usual answer keeps state in one
shared account. That is `v9-govern`.

## Address allocation

Assigned now, before anything is built, because a VPC CIDR cannot be changed —
correcting one means destroying the VPC and everything with an address in it.

| Environment | VPC CIDR |
| --- | --- |
| `dev` | `10.0.0.0/16` |
| `stage` | `10.1.0.0/16` |
| `prod` | `10.2.0.0/16` |

Non-overlapping, so that peering or a transit gateway later is a decision rather
than a re-address. Nothing peers today.

## The environments are not identical

They differ in exactly one dimension: what is allowed to cost money while idle.

| | `dev` | `stage` | `prod` |
| --- | --- | --- | --- |
| Availability zones | 2 | 2 | 2 |
| NAT gateway | None | One, shared | One per zone |
| Interface endpoints | Three, in one zone | None | None |
| Load balancer | One | One | One |
| Cost per hour | ~$0.053 | ~$0.073 | ~$0.113 |
| Standing cost | ~$38 | ~$49 | ~$82 |

`dev` reaches AWS APIs through interface endpoints rather than a NAT gateway.

This paragraph used to say that doing so removes the single largest hourly cost
in `v1-network`, and put dev at about $16. Both were wrong, because an interface
endpoint is billed for every zone it is placed in and the endpoints were never
added to the figure. Three endpoints across two zones is about $44 a month
against a NAT gateway's $33 — which made dev, on paper the cheapest environment
here, the most expensive one in the project.

What fixes it is placing dev's endpoints in **one** zone, about $22, which is
what `interface_endpoint_az_count` exists to say. The subnets stay in two zones
because a load balancer will not accept one and a subnet is free. The price of
the single zone is not money: a fault in that zone costs dev its SSM access
entirely, which is the right trade in an environment rebuilt daily and the wrong
one anywhere else.

Dev is still destroyed at the end of the day. About $38 a month is well above
the budget, and the load balancer alone would be. What the correction changed is
the size of the number, not the habit — and because the habit is the control,
`v1-network` step 9 stops leaving it to memory. At about five cents an hour, a
two-hour session is ten cents and a forgotten month is $38; the whole difference
is hours, and nothing in Terraform decides those.

`stage` matches prod's topology at the smallest size that still has the
topology. One NAT gateway is a single point of failure, which is acceptable in
an environment whose job is to prove the graph is correct, and not acceptable in
prod.

This asymmetry has to be an *input* to the network module and never three
divergent copies of it. A staging environment that differs from prod in its code
rather than in its arguments is not testing prod.

[`modules/network`](../modules/network/) now carries it as three arguments:
`az_count`, `nat_gateway_count`, and `interface_endpoint_az_count`. The last two
default to zero together, which the module rejects — an environment with neither
has no route from its private subnets to the AWS APIs, and it is a mistake that
applies cleanly and fails silently. Every column of the table above is four
numbers in a stack file and nothing else.

## Terragrunt

Adopted at `v1-network` step 8, on **v1.1.4**, pinned by version and SHA-256 in
both workflows because the binary runs with the credentials those jobs assume.

What it does here is narrow on purpose:

| | |
| --- | --- |
| `terraform` block | Sources [`stacks/<name>`](../stacks/), derived from the unit's path. The `//` makes Terragrunt copy the whole repository into the cache, which is what lets `stacks/network` reference `../../modules/*` |
| `generate "backend"` | Writes the S3 backend, key derived from the unit's path |
| `generate "provider"` | Writes the provider, `Environment` tag derived from the same path |
| `inputs` | Only `environment`, for the same reason |

It is deliberately **not** using Terragrunt's `remote_state` block, which manages
the state bucket — creating one that does not exist and enforcing settings on
one that does. That bucket belongs to [`bootstrap/`](../bootstrap/), which gave
it versioning, encryption, a public access block and a policy. Two things
managing one bucket is drift with no owner, so Terragrunt is a code generator
here and nothing else.

### What this bought, beyond deleting lines

The duplication was 48 un-parameterisable lines, which is not enough to justify
a tool. Deriving the state key from the directory is, and consolidating the
composition into `stacks/network` removed a trap each stack could previously get
wrong in silence — see that directory's `main.tf` for the
`endpoint_security_group_ids` wiring that is now impossible to state incorrectly.

### The cost, stated plainly

`terragrunt run --all` walks the whole tree. Run from `live/`, it would build
`stage` and `prod` — the two environments this project has decided not to build.
Nothing in this repository guards against that, and CI cannot do it by accident
because it names one unit; a laptop can. It joins the existing gap that
`devops-admin` could always apply `live/stage/network` by hand, which is
accepted risk until the account split at `v9-govern`.

The other cost is in [`stacks/network/outputs.tf`](../stacks/network/outputs.tf):
one module publishes every environment's outputs, so two are always empty in any
given environment.

### Running it

```
cd live/dev/network
terragrunt run -- plan
terragrunt run -- apply
```

`run --` and not the bare shortcut: Terragrunt parses its own flags first, so a
Terraform flag it does not recognise is an error about an unknown Terragrunt
flag rather than a passthrough. The `--` ends Terragrunt's arguments.

One caution for saved plans. Terraform runs inside `.terragrunt-cache/<hash>/<hash>`,
so `-out=tfplan` writes into a scratch directory named by a content hash.
[`apply.yml`](../.github/workflows/apply.yml) passes an absolute path for
exactly this reason.
