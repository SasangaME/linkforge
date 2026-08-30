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
| `v3-pipeline` | Automatic release to production | GitHub Actions with OIDC, blue-green release, IaC scan |
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
| 6 | `live/dev/network`, applied. `live/stage/network` and `live/prod/network`, written and validated only | Not started |
| 7 | The first workflow that applies. It declares `environment: dev`, and it is what tests step 1 | Not started |
| 8 | The Terragrunt decision, once the same backend block stands in three directories | Not started |
| 9 | The scheduled destroy of `dev`. The environment becomes ephemeral by construction rather than by memory | Not started |

Step 1 is the only step of this milestone that is not code. It is [RUNBOOK.md](RUNBOOK.md) operation 5, and it blocks every step after it: an apply role whose trust policy pins `:environment:dev` cannot be assumed until an environment of that name exists to put the claim in the token.

Steps 1 and 7 are one test in two parts, in the same shape as steps 4 and 7 of `v0-bootstrap`. Step 1 creates the environment. Step 7 is the first job that declares one, and until it runs, the claim the per-environment trust policies rest on — that GitHub writes the environment in place of the ref rather than beside it — is an assumption. A settings page proves the environment exists. It does not prove that the subject GitHub sends is the subject IAM was told to expect.

Step 2 is written and merged, which is not the same as applied. Nothing calls the module until step 6, and until then the only thing checking it is `terraform validate` in CI. See [modules/network/README.md](modules/network/README.md) for the address plan and for why the subnet width is a constant rather than a function of `az_count`.

Steps 2 and 3 carry the cost decision. The three environments differ in one dimension only, which is what is allowed to cost money while idle, and that difference has to arrive as an input to the module rather than as three copies of it.

The arithmetic behind that difference was wrong until this milestone checked it, and the corrected version is the reason step 9 exists. An interface endpoint is billed for each availability zone it is placed in, so three endpoints across two zones is about $44 each month against a NAT gateway's $33 — endpoints are cheaper than a NAT gateway in a one-zone diagram and dearer in a two-zone one. `dev` places its endpoints in a single zone, which brings that to about $22 and makes the claim true; the subnets stay in two zones because the load balancer in step 5 requires it. A single-zone endpoint means a zone fault costs `dev` its SSM access, which is the right trade in an environment that is rebuilt daily.

What that leaves is roughly six cents an hour for the whole of `dev`. Two hours a day is about $3 each month and the same environment forgotten for a month is about $38, so the number that decides the bill is not in any `.tf` file. That is step 9.

Step 4 is the reason the private subnets are worth building before there is an application. The host answers `/health` and nothing else. Its job is to prove that a machine with no public address, no inbound rule and no key pair is reachable, and that the endpoints in step 3 are what makes it so.

It landed in two parts, and the split was found rather than chosen. The role and the instance profile are in `account/workload_roles.tf` and not in the module, because every apply role carries a permanent deny on `iam:Create*`, `iam:Attach*` and `iam:Add*` — which covers `CreateRole`, `CreateInstanceProfile` and `AddRoleToInstanceProfile`. A stack that made its own profile would apply from a laptop and fail from the pipeline, and that is the worse of the two failures, because it works for whoever wrote it.

The machine itself is [modules/ssm-host](modules/ssm-host/). Written and merged, which is not applied — nothing calls it until step 6, so the only thing checking it is `terraform validate` in CI, exactly as with step 2. What it is built to demonstrate is that reachability here is an IAM decision and not a network one. The security group has no ingress rule of any kind; the agent dials out to Session Manager and the session runs back down the connection the host itself opened.

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

Step 6 is where the addressing fixed in `v0-bootstrap` is spent. `dev` is `10.0.0.0/16`, `stage` is `10.1.0.0/16`, `prod` is `10.2.0.0/16`, and only the first is applied. See [live/README.md](live/README.md) for the layout and for what makes an unapplied environment unreachable rather than merely unbuilt.

Steps 6 and 7 also meet a gap that nothing before them could have found. `linkforge-gha-apply-dev` holds state access and the escalation deny and nothing else, so it cannot create a VPC, a subnet, an endpoint, a security group or an instance — the first apply from CI fails on `ec2:CreateVpc`, before a single resource exists. That is the *grows per milestone* line in [RUNBOOK.md](RUNBOOK.md) coming due for the first time, and it is a hand-applied change to `account/` for the same reason everything there is: a role that can write its own permissions makes the scoping decorative.

Worth deciding before writing it rather than during. The permissions this milestone needs are the EC2 network surface, the `elasticloadbalancing` actions that step 5 added to it, plus `iam:PassRole` scoped to `linkforge-ssm-host` alone — a host cannot be given a profile the applying role may not pass, and an unscoped `PassRole` hands the pipeline every role in the account. It is also the first permission set that has to allow deletes, because step 9 destroys `dev` nightly with the same role.

Step 8 is a decision and possibly no change. Terragrunt was deferred in `v0-bootstrap` because the duplication it removes did not exist yet. Step 6 creates it. Revisit it there rather than assuming either answer.

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
