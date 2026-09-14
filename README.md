# LinkForge

LinkForge is a small URL shortener used to build AWS infrastructure one useful
piece at a time. The application is intentionally simple; the infrastructure
around it is the project.

## What it does

- `POST /links` creates a short link.
- `GET /{code}` redirects to the original URL and records a click.
- `GET /links/{code}/stats` returns click statistics.

The app is a FastAPI service in [`app/`](app/). It currently has a health
endpoint and fixed redirects. Persistent links and analytics arrive later,
when the supporting infrastructure exists.

## Current status

- `v0-bootstrap` — complete: remote Terraform state, GitHub OIDC, IAM baseline,
  and a cost budget.
- `v1-network` — complete: VPC, private access through SSM, and an application
  load balancer.
- `v2-fargate` — in progress: IAM roles are ready; ECR, ECS Fargate, logs, and
  autoscaling remain.
- Next step: add the ECR repository.

The full plan is in [ROADMAP.md](ROADMAP.md).

## Repository layout

```
account/                 Account-wide IAM and security settings
app/                     FastAPI application and container image
bootstrap/               Terraform state bucket
live/<environment>/      Terragrunt configuration for each environment
modules/                 Reusable Terraform resource modules
stacks/                  Root modules that compose the resource modules
.github/workflows/       Planning, deployment, and teardown workflows
```

## Environments

- **dev** is created when needed and destroyed nightly to keep costs down.
- **stage** and **prod** are configured but not deployed yet.
- Every environment uses the same infrastructure code; only its inputs differ.

## How the project grows

Each milestone introduces infrastructure only when the application needs it:

- **v2:** Container registry and ECS service
- **v3:** Build and deployment pipeline
- **v4:** DynamoDB-backed links and stats
- **v5:** Monitoring, alarms, and tracing
- **v6:** Event-driven click analytics
- **v7:** Domain, TLS, CDN, and WAF
- **v8:** Cache, reporting, and database workloads
- **v9–v10:** Multi-account controls, backup, and disaster recovery

## Useful docs

- [ROADMAP.md](ROADMAP.md) — milestones and progress
- [RUNBOOK.md](RUNBOOK.md) — manual setup and operational steps
- [COST.md](COST.md) — cost assumptions and budget decisions
- [live/README.md](live/README.md) — environment layout and state
- [app/README.md](app/README.md) — application details
