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

`v0-bootstrap` is in progress. The repository holds two Terraform modules, and both are applied.

[bootstrap/](bootstrap/) defines the S3 bucket that every later module stores its state in: versioned so a bad apply is recoverable, encrypted, closed to public access, denying any request that does not arrive over TLS, and expiring noncurrent versions after ninety days. Locking is S3's own, not a DynamoDB table — the table was the only option until Terraform 1.10, and the argument that configures one has been deprecated since 1.11.

That module was applied on local state, because the backend it would otherwise use was the thing it was creating. Its state has since moved into the bucket, so the module now records itself in the object store it brought into existence. This happens exactly once in the life of a repository; every module after it has a backend from its first line.

[account/](account/) holds what an account needs once and never again, and it is the first module to use that backend for something other than itself. It defines a GitHub OIDC provider with separate plan and apply roles, so that nothing here ever holds a long-lived AWS key. The plan role trusts pull requests and is read-only apart from taking a state lock — which is not a read, because S3-native locking makes the lock an object. The apply role trusts only `main` and may write state. Both carry a permanent deny on identity mutation, so no later policy can reopen the escalation path, and the apply role gets provisioning permissions one milestone at a time rather than all at once.

The same module defines a monthly cost budget that mails at 50% and 80% of actual spend and at 100% of forecast. A project that stands infrastructure up daily should say so out loud when it costs more than expected. The reasoning behind the thresholds, and the cost model they defend, are in [COST.md](COST.md).

`account/` is applied by hand and stays that way. A CI role that can edit IAM can rewrite its own permissions, which would make the per-milestone scoping of the apply role decorative.

[.github/workflows/plan.yml](.github/workflows/plan.yml) is what turns those two roles from an assertion into something tested. Every pull request into `main` runs `fmt`, `validate` and `plan` under the plan role, and no long-lived AWS key exists in the repository or in Actions for it to fall back on.

The trigger is `pull_request` and could not be anything else. GitHub writes the triggering event into the OIDC token's subject claim, and the trust policy pins that exact string — so a push carries a different subject and fails at STS, before AWS evaluates a single permission. The workflow trigger and the IAM trust policy are one decision written in two places, which is also why a pull request from a fork, getting no token at all, cannot reach this account.

It plans `bootstrap/` rather than `account/`. `bootstrap/` takes no variables and holds no secrets, so its plan output is safe to read in a public log; `account/` would need its alert address passed in as a secret and would then print it in plaintext on the pull request. Making that work meant removing the `profile` argument from `bootstrap/`, since a named local profile does not exist on a runner — both modules now resolve credentials from the environment alone, which is the one mechanism that is correct in both places.

What remains in the milestone is the account baseline — an account-level public access block, default EBS encryption, a password policy. `v0-bootstrap` is done when a pull request can plan against remote state using credentials that exist only for the life of the job.

A few operations have no Terraform resource and no API worth automating: enabling Cost Explorer, activating cost allocation tags, answering an SNS confirmation mail, handing the workflow its role ARN. Those live in [RUNBOOK.md](RUNBOOK.md), each with the reason for it, the moment to do it, and a check — because a manual step has no plan output to read.

## About the infrastructure code

The design is described in prose: which resources, how they connect, and which arguments matter. It is not copy-paste HCL. The purpose is to build the mental model of the resource graph, not to accumulate configuration.
