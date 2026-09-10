# LinkForge roadmap

| Tag | Outcome | Status |
| --- | --- | --- |
| `v0-bootstrap` | State, OIDC, IAM baseline, and budget | Complete, 2026-08-29 |
| `v1-network` | Private network, SSM host, and ALB | Complete, 2026-09-11 |
| `v2-fargate` | ECR, ECS service, logs, and auto scaling | Not started |
| `v3-pipeline` | Automated releases and multi-stack deploys | Not started |
| `v4-state` | DynamoDB-backed links and statistics | Not started |
| `v5-observable` | Alarms, dashboards, tracing, and SNS | Not started |
| `v6-events` | Asynchronous click-event pipeline | Not started |
| `v7-edge` | CloudFront, DNS, TLS, and WAF | Not started |
| `v8-scale` | Cache, Aurora, and reporting workflows | Not started |
| `v9-govern` | Multi-account governance and cost control | Not started |
| `v10-resilient` | Backup, disaster recovery, and review | Not started |

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
