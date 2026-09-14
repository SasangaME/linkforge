# LinkForge roadmap

| Tag | Outcome | Status |
| --- | --- | --- |
| `v0-bootstrap` | State, OIDC, IAM baseline, and budget | Complete, 2026-08-29 |
| `v1-network` | Private network, SSM host, and ALB | Complete, 2026-09-11 |
| `v2-fargate` | ECR, ECS service, logs, and auto scaling | In progress |
| `v3-pipeline` | Automated releases and multi-stack deploys | Not started |
| `v4-state` | DynamoDB-backed links and statistics | Not started |
| `v5-observable` | Alarms, dashboards, tracing, and SNS | Not started |
| `v6-events` | Asynchronous click-event pipeline | Not started |
| `v7-edge` | CloudFront, DNS, TLS, and WAF | Not started |
| `v8-scale` | Cache, Aurora, and reporting workflows | Not started |
| `v9-govern` | Multi-account governance and cost control | Not started |
| `v10-resilient` | Backup, disaster recovery, and review | Not started |

## `v0-bootstrap`

| Step | Work | Status |
| --- | --- | --- |
| 1 | Repository safety rails, including `.gitignore` | Done |
| 2 | `bootstrap` module and S3 state bucket, initially using local state | Done |
| 3 | Remote backend configuration and state migration | Done |
| 4 | GitHub OIDC provider with plan and apply roles | Done |
| 5 | Budget, SNS topic, and email subscription | Done |
| 6 | Account baseline: public access block, EBS encryption, password policy | Done |
| 7 | Pull-request workflow: `fmt`, `validate`, and `plan` | Done |
| 8 | `dev`, `stage`, and `prod` configuration, with dev applied first | Done |

- Steps 1–3 establish the remote state backend used by every later milestone.
- Steps 4 and 7 are one end-to-end test: the roles are created, then a pull
  request proves they can plan against S3 without long-lived access keys.
- The environment split happens here because VPC CIDRs and module interfaces
  are cheap to settle before networking exists, but expensive to change after.
- Manual setup is recorded in [RUNBOOK.md](RUNBOOK.md): Cost Explorer, cost
  allocation tags, the budget subscription, the plan-role repository variable,
  and the hand-applied account module are complete.
- GitHub Environments belong to `v1-network`, since this milestone does not
  apply an environment-specific stack.

## `v1-network`

| Step | Work | Status |
| --- | --- | --- |
| 1 | `dev` GitHub Environment | Done |
| 2 | Network module | Done |
| 3 | Interface endpoints | Done |
| 4 | SSM-only private host | Done |
| 5 | ALB and health check | Done |
| 6 | Dev network apply and verification | Done |
| 7 | Dev apply workflow | Done |
| 8 | Terragrunt live layout | Done |
| 9 | Nightly dev destroy | Done |

- `dev` is the only built environment; `stage` and `prod` are configuration only.
- [.github/workflows/destroy.yml](.github/workflows/destroy.yml) destroys only
  `live/dev/network` at midnight Asia/Colombo.
- Modules composed by `stacks/network` are included automatically. A new
  `live/dev/<stack>` unit needs its own destroy step, after its dependants.

`v1-network` closed on 2026-09-11 after the scheduled-destroy workflow ran successfully.

## `v2-fargate`

| Step | Work | Status |
| --- | --- | --- |
| 1 | Python application stub, Dockerfile, and endpoint tests | Done |
| 2 | ECS task roles, autoscaling service-linked role, and CI provisioning permissions | Done |
| 3 | ECR repository | Not started |
| 4 | ECS cluster, task definition, service, and CloudWatch logs | Not started |
| 5 | Replace the instance target with an IP target group for ECS | Not started |
| 6 | Service auto scaling | Not started |
| 7 | Build, push, deploy, and verify the dev image | Not started |
| 8 | Add the v2 resources to the nightly dev destroy | Not started |

The committed [`app/`](app/) stub exposes `/health` and fixed in-memory
redirects on port 8080. It is deliberately stateless and has no release
automation; persistent links arrive at `v4-state` and automated builds at
`v3-pipeline`.
