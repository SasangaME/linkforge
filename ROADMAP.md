# LinkForge — Milestone Roadmap

LinkForge is one application. It is not a group of separate projects.

At the start, LinkForge is one container behind a load balancer. Each milestone adds more infrastructure to the same application. At the end, LinkForge is a platform with many accounts, asynchronous events, monitoring, and cost control.

Each milestone adds only the infrastructure that the application needs at that time.

## Why this project uses one application

Each separate AWS project needs the same basic parts. These parts are a VPC, the IAM roles, a state backend, a build step, and a deploy path. You must build these parts before the project does useful work.

This project builds these parts one time, in milestone `v0-bootstrap`. Each milestone after `v0-bootstrap` adds only the new parts.

The result is that this project covers many AWS services in a short time. Separate projects use most of that time on the same basic parts.

## About the infrastructure code

This document gives the Terraform design in words. It does not give the HCL code.

For each milestone, the text tells you which resources to use. The text also tells you how the resources connect, and which arguments are important. The purpose is to learn the resource graph.

The application code in the container is simple. It is not the subject of this project. The language is Python.

## When the application is written

The application appears in milestone `v2-fargate`. This is the first milestone with ECR and ECS. ECR has no image to store, and ECS has no task to run, until the application exists.

Milestone `v1-network` needs no application. The host in that milestone answers on `/health` only. Its purpose is to prove that the private subnets and SSM access work.

The application then grows with the infrastructure that supports it.

| Milestone | What the application does | Who builds the image |
| --- | --- | --- |
| `v1-network` | Nothing. A `/health` answer only | Not applicable |
| `v2-fargate` | `/health`, and a redirect from a map in memory | You, with `docker build` and `docker push` |
| `v3-pipeline` | No change | GitHub Actions, on each merge |
| `v4-state` | The three real endpoints, with DynamoDB | GitHub Actions |
| `v6-events` | `GET /{code}` sends the click event to SQS | GitHub Actions |

The application stays a stub until `v4-state`. Before that milestone there is no database, thus `POST /links` cannot keep a link.

The change in `v6-events` is the only one with an important design point. The redirect must stay fast. Therefore the application does not write the click data during the request. It sends the data to a queue instead.

The application is a URL shortener in Python. Select the framework in milestone `v2-fargate`. The infrastructure has two conditions only:

- The application must answer on a `/health` route. The ALB target group uses this route. This route must not read from DynamoDB. If it does, one fault in DynamoDB makes all tasks unhealthy at the same time.
- The application must listen on the port that the ECS task definition gives.

Two more conditions come from horizontal scale:

- Use an asynchronous framework. The redirect waits for DynamoDB. A synchronous worker stops all other requests during this wait.
- Run one process in each container. Do not run many workers in one container and also scale the number of tasks. Two scale controls together make the CPU metric incorrect.

The container image is the interface between the application and the infrastructure. No resource after ECR knows the contents of the image. Thus a change of language later is a small change.

## How this project scales the service

This project uses ECS, and not Kubernetes. ECS has no HorizontalPodAutoscaler. The equivalent function in ECS is **service auto scaling**. The resources are `aws_appautoscaling_target` and `aws_appautoscaling_policy`. A target tracking policy holds a metric at a value. The usual metrics are the CPU of the service and the count of requests for each target in the ALB.

The application does not change for scale. It must only be stateless. Milestone `v2-fargate` keeps the links in memory, thus the tasks are not equal at that time. Milestone `v4-state` moves the links to DynamoDB and removes this problem.

## Milestones

| Tag | Milestone | New resources |
| --- | --- | --- |
| `v0-bootstrap` | Basic account setup | State backend, OIDC, billing limit |
| `v1-network` | A network and a host that you can access | VPC, subnets, SSM, ALB |
| `v2-fargate` | A service in a container | ECR, ECS Fargate, logs, ECS service auto scaling. The application is written here |
| `v3-pipeline` | Automatic release to production | GitHub Actions with OIDC, blue-green release, IaC scan, multi-stack apply |
| `v4-state` | Permanent data storage | DynamoDB, S3, KMS, Secrets Manager |
| `v5-observable` | Monitoring and alerts | Alarms, dashboards, Logs Insights, X-Ray, SNS |
| `v6-events` | An asynchronous pipeline for click data | SQS, Lambda, Firehose, S3, Athena, EventBridge |
| `v7-edge` | Public access at the edge | CloudFront, ACM, Route 53, WAF |
| `v8-scale` | Better performance and a relational database | ElastiCache, Aurora with RDS Proxy, Step Functions |
| `v9-govern` | Many accounts and cost control | Organizations, SCPs, Config, Budgets, resource tags |
| `v10-resilient` | Disaster recovery and a Well-Architected review | AWS Backup, a pilot-light region, WAR review |

## Status

| Tag | Status |
| --- | --- |
| `v0-bootstrap` | Complete, 2026-08-29 |
| `v1-network` | In progress |
| `v2-fargate` | Not started |
| `v3-pipeline` | Not started |
| `v4-state` | Not started |
| `v5-observable` | Not started |
| `v6-events` | Not started |
| `v7-edge` | Not started |
| `v8-scale` | Not started |
| `v9-govern` | Not started |
| `v10-resilient` | Not started |

The table above changes at the end of a milestone only. Thus it holds no detail during a milestone. The tables below give that detail: the milestone in progress first, then the one most recently closed.

### Inside `v1-network`

| Step | Work | Status |
| --- | --- | --- |
| 1 | The `dev` GitHub Environment, with its deployment branch rule | Done |
| 2 | `modules/network`. The VPC, the subnets, and the difference between the environments expressed as arguments | Done |
| 3 | The interface endpoints that let `dev` reach the AWS APIs without a NAT gateway | Done |
| 4 | The host in a private subnet, reached over SSM. No key pair, no bastion, no inbound rule | Done |
| 5 | The load balancer, and a target group that health checks `/health` | Done |
| 6 | `live/dev/network`, applied. `live/stage/network` and `live/prod/network`, written and validated only | Done |
| 7 | The first workflow that applies. It declares `environment: dev`, and it is what tests step 1 | Done |
| 8 | The Terragrunt decision, once the same backend block stands in three directories | Done |
| 9 | The scheduled destroy of `dev`. The environment becomes ephemeral by construction rather than by memory | Not started |

Step 1 is the only step of this milestone that is not code. It is [RUNBOOK.md](RUNBOOK.md) operation 5, and it blocks every step after it: an apply role whose trust policy pins `:environment:dev` cannot be assumed until an environment of that name exists to put the claim in the token.

Steps 1 and 7 are one test in two parts, in the same shape as steps 4 and 7 of `v0-bootstrap`. Step 1 creates the environment. Step 7 is the first job that declares one, and until it ran, the claim the per-environment trust policies rest on — that GitHub writes the environment in place of the ref rather than beside it — was an assumption. A settings page proves the environment exists. It does not prove that the subject GitHub sends is the subject IAM was told to expect.

It ran on 2026-08-30 and the claim held. The evidence is not a green check: it is CloudTrail recording `CreateVpc`, `CreateLoadBalancer` and `RunInstances` under the session name `linkforge-apply-dev-<run id>`, which only `linkforge-gha-apply-dev` can produce and which nothing could have produced if the subject had been wrong. That closes the last untested claim carried out of `v0-bootstrap`.

Step 2 was written and merged long before anything called it; step 6 is where the pipeline built it for the first time, and it came up correct. See [modules/network/README.md](modules/network/README.md) for the address plan and for why the subnet width is a constant rather than a function of `az_count`.

Steps 2 and 3 carry the cost decision. The three environments differ in one dimension only, which is what is allowed to cost money while idle, and that difference has to arrive as an input to the module rather than as three copies of it.

The arithmetic behind that difference was wrong until this milestone checked it, and the corrected version is the reason step 9 exists. An interface endpoint is billed for each availability zone it is placed in, so three endpoints across two zones is about $44 each month against a NAT gateway's $33 — endpoints are cheaper than a NAT gateway in a one-zone diagram and dearer in a two-zone one. `dev` places its endpoints in a single zone, which brings that to about $22 and makes the claim true; the subnets stay in two zones because the load balancer in step 5 requires it. A single-zone endpoint means a zone fault costs `dev` its SSM access, which is the right trade in an environment that is rebuilt daily.

What that leaves is roughly six cents an hour for the whole of `dev`. Two hours a day is about $3 each month and the same environment forgotten for a month is about $38, so the number that decides the bill is not in any `.tf` file. That is step 9.

Step 4 is the reason the private subnets are worth building before there is an application. The host answers `/health` and nothing else. Its job is to prove that a machine with no public address, no inbound rule and no key pair is reachable, and that the endpoints in step 3 are what makes it so.

It landed in two parts, and the split was found rather than chosen. The role and the instance profile are in `account/workload_roles.tf` and not in the module, because every apply role carries a permanent deny on `iam:Create*`, `iam:Attach*` and `iam:Add*` — which covers `CreateRole`, `CreateInstanceProfile` and `AddRoleToInstanceProfile`. A stack that made its own profile would apply from a laptop and fail from the pipeline, and that is the worse of the two failures, because it works for whoever wrote it.

The machine itself is [modules/ssm-host](modules/ssm-host/). Built for the first time at step 6, where it registered with Session Manager over the endpoints from step 3 and answered the load balancer's health check. What it is built to demonstrate is that reachability here is an IAM decision and not a network one. The security group has no ingress rule of any kind; the agent dials out to Session Manager and the session runs back down the connection the host itself opened.

Its egress is where the three environments differ, and the difference arrives as an argument rather than as a second copy of the module. With interface endpoints the far end of the connection is an ENI inside this VPC, so the rule can name its security group. With a NAT gateway the far end is the public internet, and a rule can name nothing but a CIDR. So the environment that pays for the NAT gateway ends up with the looser egress rule and the cheap one ends up with the tighter, which is the reverse of how the cost table reads. See [modules/ssm-host/README.md](modules/ssm-host/README.md) for that and for the S3 prefix list rule, which is the one omission in this module that fails silently rather than loudly.

Step 5 is [modules/alb](modules/alb/), and it is the first module in this
project whose resources outlive the milestone that wrote them. The load
balancer, its security group and its listener are the same resources at
`v2-fargate` and at `v7-edge`; only the target changes, from an instance to an
ECS service. That is the reason it is a third directory rather than more
resources inside `network/`, and it is the mirror of the reason `ssm-host/` is
its own directory — one module is built to be deleted and one is built to be
kept, and neither should be tangled in the other.

Written and merged, which is not applied. Nothing calls it until step 6, so the
only thing checking it is `terraform validate`, exactly as with steps 2 and 4.

Two things in it were decided by constraints rather than by preference. The
first is that this module writes an ingress rule into a security group it did
not create — the host's. The rule pair is circular by nature, the load balancer
allowing egress to the host while the host allows ingress from the load
balancer, and two modules that each read the other's output is a cycle Terraform
reports at the module level even though no single resource is in a loop. One
side owns both rules. That is also what step 4's separate rule resources were
for: an inline block is authoritative and would have deleted anything added from
outside it.

The second is that the target group is named by AWS rather than by us.
`target_type` is force-new and `v2-fargate` changes it from `instance` to `ip`,
and a target group cannot be destroyed while a listener still forwards to it. So
the new one has to exist before the old one goes, which needs
`create_before_destroy`, which needs a generated name, whose prefix AWS caps at
six characters. The load balancer keeps a readable name for the opposite reason:
it is not going to be replaced, and its name is inside the DNS name people type.

The one exposure decision in the milestone is an argument with no default.
`allowed_cidrs` is what the internet may open a connection to, and the module
refuses to guess on a stack's behalf — the same shape as `nat_gateway_count` and
`interface_endpoint_az_count` rejecting their own default pair.

What none of this proves is that a target ever passes a check. That is step 6,
and the test is `aws elbv2 describe-target-health`, not a clean apply: every
resource here can be created successfully with the health check failing every
time. `Target.Timeout` and `Target.FailedHealthChecks` are the two answers worth
knowing apart, because they separate a security group fault from a responder
fault without logging into anything.

Step 6 is where the addressing fixed in `v0-bootstrap` is spent. `dev` is `10.0.0.0/16`, `stage` is `10.1.0.0/16`, `prod` is `10.2.0.0/16`, and all three are written. See [live/README.md](live/README.md) for the layout and for what makes an unapplied environment unreachable rather than merely unbuilt.

Steps 6 and 7 also met a gap that nothing before them could have found. `linkforge-gha-apply-dev` held state access and the escalation deny and nothing else, so it could not create a VPC, a subnet, an endpoint, a security group or an instance — the first apply from CI would have failed on `ec2:CreateVpc`, before a single resource existed. That is the *grows per milestone* line in [RUNBOOK.md](RUNBOOK.md) coming due for the first time, and it was a hand-applied change to `account/` for the same reason everything there is: a role that can write its own permissions makes the scoping decorative.

The permissions this milestone needs are the EC2 network surface, the `elasticloadbalancing` actions that step 5 added to it, plus `iam:PassRole` scoped to `linkforge-ssm-host` alone — a host cannot be given a profile the applying role may not pass, and an unscoped `PassRole` hands the pipeline every role in the account. It is also the first permission set that has to allow deletes, because step 9 destroys `dev` nightly with the same role.

One item in it could not be granted at all. Elastic Load Balancing creates `AWSServiceRoleForElasticLoadBalancing` on the first `CreateLoadBalancer` in an account and bills the caller `iam:CreateServiceLinkedRole` for it — an action the escalation guardrail denies on `*`, and an explicit deny is terminal rather than weighed. So no policy added to an apply role could have made its first load balancer succeed. The role is created once in `account/`, declared rather than acquired as a side effect, which also fixes the ordering: an admin who applies a load balancer first creates it implicitly and the Terraform resource then fails as already taken.

### What steps 6 and 7 proved, and what only the apply could have found

`dev` was built end to end by the pipeline on 2026-08-30 — not by a laptop — and the target group reported `healthy` with `/health` answering 200 through the load balancer. Then it was destroyed. That sequence is the milestone: the ALB, the target group, the ingress rule the ALB module writes into a group it does not own, the endpoints, and a host with no address, no key pair and no inbound rule, all working together and all reachable only because of an IAM decision.

Two defects survived `fmt`, `validate`, review and a clean plan, and both were found by the apply refusing:

- **A `count` cannot be unknown at plan time.** The target group attachment was switched on with `var.target_instance_id == null ? 0 : 1`. The instance does not exist when the plan is made, so its ID is unknown, so the comparison is unknown, so the count is unknown — and Terraform will not build a graph it cannot size. The argument became a list and the count became `length()`, because the length of a one-element list is known even when the element is not. It is also the shape the argument wants on the day a second target appears. `modules/ssm-host` took the same change for the same reason.
- **AWS validates a security group rule description against a fixed character set,** and it excludes the em dash, the apostrophe, the backtick and angle brackets — every character this repository writes prose with. `InvalidParameterValue` arrives at apply, after the group and its earlier rules already exist. Comments above a resource are free to say anything; strings that cross the API are not.

Neither is a mistake a review catches, and that is the point worth keeping: `validate` reads one directory's references and types, and a plan reasons about a graph. Only the API refuses.

Step 8 was the decision, and the answer was to adopt Terragrunt. What tipped it was not the line count.

The duplication was measured before deciding, because "the same nine lines appear nine times" turned out to overstate it. Comparing `dev` to `stage` line by line, code only, the backend and provider blocks were 26 lines per stack of which **two** differed. `main.tf` and `outputs.tf` differed in five and six lines, and those differences were the environments themselves. About 48 lines of genuinely un-parameterisable duplication, not ninety.

Forty-eight lines does not buy a new tool. Three things did.

**The state key is the one value where a typo is silent and destructive.** A stack pointed at another environment's key adopts that environment's state and plans to destroy the difference. Terraform's own answer — partial configuration, `init -backend-config="key=..."` — removes the same lines and turns a literal that is right by construction into a flag every human and every workflow has to get right. Terragrunt derives the key from the unit's directory path, so it cannot disagree with where the file lives. The `Environment` tag is derived from the same path segment, so a stack can no longer write dev's state while tagging its resources prod.

**Consolidating the stack removed a trap, not just repetition.** Each environment used to state its own `endpoint_security_group_ids`, and the wrong answer was the plausible one — `modules/network` creates that security group unconditionally, so its output is a real ID even where no endpoint is attached to it, and passing it through gave the host an egress rule to an empty group, no route to the internet, a clean apply, and an instance that never appeared in Session Manager. That wiring now derives from `interface_endpoint_az_count` inside [stacks/network](stacks/network/), in one place, and the mistake cannot be made from a caller.

**The moment was free and would not have stayed free.** `dev` had been destroyed, so its state held no resources and no address could be orphaned by moving the composition out of `live/`. A day later the same change needs `terraform state mv` for every resource in it.

What it costs is worth stating. A binary that is now on the apply path, pinned by version *and* SHA-256 because it runs with the apply role's credentials. `run --all` walks the whole tree, so a careless invocation from `live/` would build the two environments this project has decided not to build. And one module publishing every environment's outputs means two of them are always empty in any given environment, which is a real loss of signal recorded in that file rather than hidden.

The layout is [stacks/network](stacks/network/) for the code, [live/root.hcl](live/root.hcl) for what is generated, and one `terragrunt.hcl` per environment holding arguments and nothing else.

Step 9 makes the daily destroy a property of the repository rather than a habit. Every cost in this milestone is hourly, so `dev` is cheap when it is short-lived and the only thing keeping it short-lived today is memory. A scheduled workflow that destroys `live/dev/network` overnight turns a forgotten environment into one evening rather than one month, and returns the $10 budget alarm to being a backstop instead of the primary control.

It comes after step 7 because it needs the same apply role and the same `environment: dev` declaration, and it is the second job to prove that path. Two things about it are worth deciding rather than discovering: a schedule reaches AWS with nobody watching, so the destroy is scoped to the one stack by path and never runs `-auto-approve` against anything under `live/stage` or `live/prod`; and `stage` and `prod` are safe from it for the same reason they are unbuilt, which is that no environment exists to mint them a token.

### Inside `v0-bootstrap`, closed 2026-08-29

| Step | Work | Status |
| --- | --- | --- |
| 1 | The safety rails of the repository. The `.gitignore` file, written before the first apply | Done |
| 2 | The `bootstrap` module. The S3 state bucket, applied with local state | Done |
| 3 | The `backend` block, and the move of the state into the bucket | Done |
| 4 | The GitHub OIDC provider, with a plan role and an apply role | Done |
| 5 | The billing limit. A budget, an SNS topic, and an email subscription | Done |
| 6 | The account baseline. Public access block, EBS encryption, password policy | Done |
| 7 | The first workflow. `fmt`, `validate`, and `plan` on each pull request | Done |
| 8 | The environment split. `dev`, `stage`, and `prod` defined; `dev` alone applied | Done |

Steps 1 to 3 give a state backend that holds its own state. This is the part that each later milestone uses.

Steps 4 and 7 are one test in two parts. Step 4 makes the roles. Step 7 proves that they work. `v0-bootstrap` is complete when a pull request makes a plan that reads the state from S3 with OIDC credentials, and no identity in the pipeline holds an access key.

Step 8 is placed inside `v0-bootstrap` and not inside `v1-network` for one reason. The first resource with an address is created in `v1-network`, and a VPC CIDR cannot be changed after that — a correction destroys the VPC and everything holding an address in it. The same is true of the module interface: an environment that differs from production in its code rather than in its arguments is not testing production, and that is a property you build in or lose. Both are free to decide now and expensive to decide later.

Five operations of this milestone are not Terraform code. They are in [RUNBOOK.md](RUNBOOK.md), and all five are done. Cost Explorer and the cost allocation tags closed on 2026-08-28, before milestone `v1-network` makes the first resources with a real cost. The budget alert subscription and the plan role repository variable were confirmed on 2026-08-29, and the account module was applied by hand the same day.

The sixth operation, creating the GitHub Environments, belongs to `v1-network` and not here. Nothing in `v0-bootstrap` applies anything, so no job in this milestone ever declares an environment or needs a token that names one.
