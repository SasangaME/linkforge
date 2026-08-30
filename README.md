# LinkForge

LinkForge is a link shortener with click analytics. It is also the application that every piece of infrastructure in this repository exists to serve.

## The product

Three endpoints.

| Endpoint | Behavior |
| --- | --- |
| `POST /links` | Accepts a long URL, returns a short code |
| `GET /{code}` | 302-redirects to the long URL, emits a click event |
| `GET /links/{code}/stats` | Returns click counts, referrers, geography |

That is about 150 lines of Python. It is boring on purpose. The application is never the subject of this project — the resource graph around it is.

## When the application gets written

`v2-fargate`. That is the first milestone with ECR and ECS, and a registry with no image to store and a scheduler with no task to run are not worth building. Before that, `v1-network` proves out private subnets and SSM access against a host that answers `/health` and nothing else.

The code then arrives in the order the infrastructure can support it:

| Milestone | The application | Built by |
| --- | --- | --- |
| `v2-fargate` | `/health` plus a redirect from an in-memory map | `docker build` on your machine |
| `v3-pipeline` | Unchanged — what moves is the build | GitHub Actions, on merge |
| `v4-state` | The three real endpoints, backed by DynamoDB | GitHub Actions |
| `v6-events` | The redirect stops writing click data inline | GitHub Actions |

It stays a stub until `v4-state` for an honest reason: there is no store to write to, so `POST /links` cannot persist anything before then. And the `v6-events` change is the only one carrying real design weight — the redirect has to stay fast, so the click write comes off the request path and onto a queue.

Building more application than the infrastructure can currently serve is exactly the failure mode this ordering exists to prevent.

The application is Python. The framework choice is deferred to `v2-fargate` and matters in four ways only: it must expose a `/health` route for the ALB target group, listen on the port the task definition declares, be async (the redirect blocks on DynamoDB, and a sync worker blocks everything else with it), and run as a single process per container so CPU stays a clean autoscaling signal. The container image is the real interface between the application and everything in this repository — nothing downstream of ECR knows or cares what is inside it, which is also what makes a later change of language cheap.

Scaling is horizontal and lives in the infrastructure, not the app. On ECS that means service auto scaling — `aws_appautoscaling_target` with a target-tracking policy on service CPU or the ALB's `RequestCountPerTarget`. It is the same idea as a Kubernetes HPA, but a different resource with a different API; there is no HPA outside Kubernetes, and this project deliberately stays on ECS. The only thing the application owes horizontal scale is statelessness, which is why the in-memory map at `v2-fargate` is a stub and `v4-state` is where replicas become genuinely interchangeable.

## Why this product and not a to-do app

Every AWS primitive in the roadmap has an honest reason to exist here. Nothing is bolted on to tick a box.

| The product needs | Which forces | Milestone |
| --- | --- | --- |
| Redirects that are fast and read-heavy | DynamoDB, then a cache, then a CDN | `v4-state`, `v8-scale`, `v7-edge` |
| Click events that do not slow the redirect down | Async fan-out: queue, stream, Lambda | `v6-events` |
| Analytics as historical aggregation, not live queries | S3 + Athena + a nightly rollup | `v6-events` |
| A public, abuse-prone endpoint | WAF, rate limiting, edge | `v7-edge` |
| Short links on a real domain | Route 53 + ACM | `v7-edge` |
| Reporting joins over stats | Aurora Serverless | `v8-scale` |
| A URL redirector will be used for phishing | Abuse scanning, and so an event-driven pipeline | `v6-events` |

Each row is a question the product asks. The milestone is the answer.

## How this repository grows

LinkForge starts as one container behind a load balancer and ends as a multi-account, event-driven, observable, cost-governed platform. Each milestone adds only the infrastructure the application needs at that point. The shared foundations — VPC, IAM, state backend, build, deploy path — are paid for once, in `v0-bootstrap`.

See [ROADMAP.md](ROADMAP.md) for the milestone list and current status.

## What exists today

`v0-bootstrap` closed on 2026-08-29 and `v1-network` is in progress. What is *applied* is still only what `v0-bootstrap` applied: the state bucket and the account configuration. The network is written and unbuilt, which is a distinction this repository has learned to make out loud.

### `v0-bootstrap`, closed

Two applied root modules, the pipeline that proves their identities work, and the skeleton of the per-environment layout that every later milestone fills in.

[bootstrap/](bootstrap/) defines the S3 bucket that every later module stores its state in: versioned so a bad apply is recoverable, encrypted, closed to public access, denying any request that does not arrive over TLS, and expiring noncurrent versions after ninety days. Locking is S3's own, not a DynamoDB table — the table was the only option until Terraform 1.10, and the argument that configures one has been deprecated since 1.11.

That module was applied on local state, because the backend it would otherwise use was the thing it was creating. Its state has since moved into the bucket, so the module now records itself in the object store it brought into existence. This happens exactly once in the life of a repository; every module after it has a backend from its first line.

[account/](account/) holds what an account needs once and never again, and it is the first module to use that backend for something other than itself. It defines a GitHub OIDC provider with separate plan and apply roles, so that nothing here ever holds a long-lived AWS key. The plan role trusts pull requests and is read-only apart from taking a state lock — which is not a read, because S3-native locking makes the lock an object. There is one apply role per environment, each trusting a job that declares that environment and each able to write only its own prefix of the state bucket. All of them carry a permanent deny on identity mutation, so no later policy can reopen the escalation path, and they gain provisioning permissions one milestone at a time rather than all at once.

The same module defines a monthly cost budget that mails at 50% and 80% of actual spend and at 100% of forecast. A project that stands infrastructure up daily should say so out loud when it costs more than expected. The reasoning behind the thresholds, and the cost model they defend, are in [COST.md](COST.md).

`account/` is applied by hand and stays that way. A CI role that can edit IAM can rewrite its own permissions, which would make the per-milestone scoping of the apply role decorative.

[.github/workflows/plan.yml](.github/workflows/plan.yml) is what turns those roles from an assertion into something tested. Every pull request into `main` runs `fmt`, `validate` and `plan` under the plan role, and no long-lived AWS key exists in the repository or in Actions for it to fall back on.

The trigger is `pull_request` and could not be anything else. GitHub writes the triggering event into the OIDC token's subject claim, and the trust policy pins that exact string — so a push carries a different subject and fails at STS, before AWS evaluates a single permission. The workflow trigger and the IAM trust policy are one decision written in two places, which is also why a pull request from a fork, getting no token at all, cannot reach this account.

That subject is not the repository's name. GitHub changed the claim for repositories created after 15 July 2026 to carry the numeric owner and repository IDs — `repo:owner@12818777/linkforge@1330896942:pull_request` — and those IDs survive a rename, so trust no longer follows a name that someone else can later claim. The roles were written against the older name-based form and denied every assume until they were corrected. The trust policies had been read back from IAM and confirmed correct at the time they were written, which proved only that they said what they were meant to say; nothing short of assuming the role could show that the string was one GitHub would ever send.

It plans `bootstrap/` rather than `account/`. `bootstrap/` takes no variables and holds no secrets, so its plan output is safe to read in a public log; `account/` would need its alert address passed in as a secret and would then print it in plaintext on the pull request. Making that work meant removing the `profile` argument from `bootstrap/`, since a named local profile does not exist on a runner — both modules now resolve credentials from the environment alone, which is the one mechanism that is correct in both places.

[live/](live/) and [modules/](modules/) are the shape of everything after this milestone: a module holds a resource graph with no environment name in it, and one directory per environment per stack supplies the arguments. Three environments are defined — `dev`, `stage`, `prod` — and one is built.

That asymmetry is a cost decision made before the first apply rather than after it. Three copies of `v1-network` is roughly $150 a month standing against a $10 budget, so `dev` reaches AWS through interface endpoints in a single zone instead of a NAT gateway — about $22 a month against $33, and the load balancer keeps it above the budget either way, so it stays on the daily destroy — while `stage` and `prod` exist as configuration that is checked on every pull request and never applied. What keeps them unbuilt is not a comment: their GitHub Environments do not exist, so GitHub will not mint a token naming them, so their IAM roles cannot be assumed by anyone. Writing all three now fixes the addressing and the module interface while both are still free to change; a CIDR cannot be corrected without destroying the VPC that carries it.

A merge to `main` reaches dev; a `release/x.xx` branch cut from main reaches stage and then prod, with a required reviewer on the last step. That routing is not in this repository and cannot be. A job that declares an environment receives a subject claim naming the environment and not the ref — the environment replaces the branch segment rather than joining it — so there is no branch left in the token for an IAM condition to test. Everywhere else here GitHub asserts and IAM verifies; this is the one control where IAM has nothing to check, and the deployment branch policy is the enforcement rather than a convenience.

The honest limit of that arrangement is that `validate` on an unbuilt environment catches syntax, types and references, and nothing an AWS API has to refuse. The first `stage` apply will find quotas and name collisions — the same lesson as reading a trust policy back from IAM and learning only that it says what it was written to say.

The same module carries the account baseline: an account-level S3 public access block that sits above every bucket policy in the account, EBS encryption on by default, and a console password policy. All three were unset, so each is a default being chosen rather than confirmed, and all three govern only what is created after them — which is the argument for doing them in `v0-bootstrap`, while there is nothing yet to grandfather in. Two are account-global and one, the EBS setting, is regional and quietly covers `us-east-1` alone; the pilot-light region in `v10-resilient` will start without it and no plan in this module will say so.

The password policy is the honest outlier. The account holds one IAM user, it is break-glass, and it has no console password for the policy to govern. It is here because the moment it stops being decorative is the moment somebody creates a console user, which is exactly the moment nobody is thinking about password rules.

It is also the clearest illustration of why `account/` is applied by hand: the permanent deny on identity mutation that every OIDC role carries includes `iam:Update*`, so no CI role in this project can set an account password policy, by construction.

`v0-bootstrap` was done when a pull request could plan against remote state using credentials that exist only for the life of the job, and it closed on 2026-08-29 having done exactly that.

The lesson it closed on is worth carrying, because everything below is subject to it. A merged pull request is not an apply. `account/` is hand-applied by design, so no job in this repository plans it, so merging the account baseline changed nothing in AWS and nothing anywhere said so — green checks, clean tree, three settings still unset for a day. It was found by calling the three APIs and reading back `NoSuchPublicAccessBlockConfiguration`, `false` and `NoSuchEntity`. For a hand-applied module the repository is a statement of intent and only the service API says what is true.

A few operations have no Terraform resource and no API worth automating: enabling Cost Explorer, activating cost allocation tags, answering an SNS confirmation mail, handing the workflow its role ARN. Those live in [RUNBOOK.md](RUNBOOK.md), each with the reason for it, the moment to do it, and a check — because a manual step has no plan output to read.

### `v1-network`, in progress

[modules/](modules/) now holds three module definitions, and nothing calls any of them. That is the honest status: they are written, formatted, and checked by `terraform validate` on every pull request, and no resource described below exists in the account. The stacks under `live/` that would build them are step 6.

[modules/network/](modules/network/) is the VPC, its subnets, and everything that decides where a packet goes — one module for all three environments, because a staging environment that differs from production in its code rather than in its arguments is not testing production. The three environments differ in exactly one dimension, which is what is allowed to cost money while idle, and that difference arrives as three numbers: how many zones, how many NAT gateways, how many zones get interface endpoints. The last two default to zero together and the module rejects that combination, because an environment with neither has no route from its private subnets to the AWS APIs and it is a mistake that applies cleanly, builds every resource, and leaves every instance unreachable with nothing in the plan to say so.

Subnet addresses are derived from the VPC CIDR rather than passed in, with a subnet width that is a constant and not a function of the zone count. The obvious version — enough bits for exactly the zones in use — works, and then the day a third zone is added every subnet is re-derived at a new address and Terraform destroys and recreates all of them along with anything holding an address in them.

The interesting thing in that module is a claim that turned out to be false. `dev` reaches the AWS APIs through interface endpoints instead of a NAT gateway, and this project used to describe that as removing the single largest hourly cost in the milestone. An interface endpoint is billed for every zone it is placed in, and the endpoints had never been added to the figure: three of them across two zones is about $44 a month against a NAT gateway's $33, which made the environment that was on paper the cheapest into the most expensive one in the project. What repairs it is placing `dev`'s endpoints in a single zone, about $22, while the subnets stay in two because a load balancer will not accept one and a subnet is free. The price of that is not money — a fault in that zone costs `dev` its SSM access entirely, which is the right trade in an environment rebuilt daily and the wrong one anywhere else.

[modules/ssm-host/](modules/ssm-host/) is one instance in a private subnet that answers `/health` and nothing else. Its purpose is to prove the network rather than to run anything: a machine with no public address, no key pair and no inbound rule of any kind, reachable anyway. The security group has no ingress rule — not a narrow one, none — and reachability comes from the instance profile, because the agent dials out to Session Manager and the session runs back down the connection the host itself opened. Access here is an IAM decision, not a network one.

Its egress is where the environments part company, and the shape of that is worth stating because it inverts the cost table. With interface endpoints the far end of the connection is an ENI inside the VPC, so the rule names a security group. With a NAT gateway the far end is the public internet and a rule can name nothing but a CIDR. The environment that pays for the NAT gateway ends up with the looser egress rule and the cheap one ends up with the tighter.

The role and instance profile that host assumes are in [account/](account/) and not in the module, and that placement was found rather than chosen: every CI apply role carries a permanent deny on `iam:Create*`, `iam:Attach*` and `iam:Add*`, which covers creating a role and creating an instance profile. A stack that made its own would apply from a laptop and fail from the pipeline — the worse of the two failures, because it works for whoever wrote it.

[modules/alb/](modules/alb/) is the front door, and the first module here whose resources outlive the milestone that wrote them: the load balancer, its security group and its listener are the same objects at `v2-fargate` and at `v7-edge`, and only the target changes, from an instance to an ECS service. Two of its decisions were forced rather than chosen. It writes an ingress rule into a security group it did not create, because the rule pair is circular — the load balancer allows egress to the host, the host allows ingress from the load balancer — and two modules each reading the other's output is a cycle Terraform reports at the module level, where no individual resource is in a loop. And its target group is named by AWS rather than by us, because `target_type` is force-new, `v2-fargate` changes it, and a target group a listener still forwards to cannot be destroyed before its replacement exists; `create_before_destroy` needs a generated name, and the prefix AWS allows is six characters.

The one thing that module refuses to decide is who may reach it. `allowed_cidrs` has no default, in the same way the network module rejects the combination of no NAT gateway and no endpoints: the argument that decides what the public internet can open a connection to is stated by the stack, not guessed by the module.

What remains is the stacks that call these modules, the first workflow that applies rather than plans, and a scheduled destroy. The last of those is not polish. Every cost in this milestone is hourly, so `dev` is cheap when it is short-lived, and the only thing keeping it short-lived today is memory: about six cents an hour is ten cents for an evening's work and $38 for an environment forgotten for a month. The number that decides the bill is not in any `.tf` file, which is the argument for making the destroy a property of the repository rather than a habit.

One gap this milestone will meet and nothing before it could have found: `linkforge-gha-apply-dev` holds state access and the escalation deny and nothing else, so it cannot create a VPC, a subnet, a security group, an instance or a load balancer. The first apply from CI fails at `ec2:CreateVpc` before a single resource exists, and would fail again on `elasticloadbalancing:CreateLoadBalancer` after that. That is the *permissions grow per milestone* design arriving for the first time, and it is a hand-applied change to `account/` for the same reason everything there is.

## About the infrastructure code

[ROADMAP.md](ROADMAP.md) describes each milestone's design in prose: which resources, how they connect, and which arguments matter. It is deliberately not HCL. The purpose of that document is to build the mental model of the resource graph before any of it is typed.

The modules themselves are of course real Terraform, and they carry the reasoning inline rather than only in the READMEs — the comment next to an argument is where someone reading a diff will actually find it. Each module also has a README covering the interface, the resource graph, and the specific things the graph does not show: an implicit dependency, an argument whose default silently does nothing, a rule whose absence fails quietly rather than loudly.
