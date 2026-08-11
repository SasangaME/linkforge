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
| `v0-bootstrap` | Not started |
| `v1-network` | Not started |
| `v2-fargate` | Not started |
| `v3-pipeline` | Not started |
| `v4-state` | Not started |
| `v5-observable` | Not started |
| `v6-events` | Not started |
| `v7-edge` | Not started |
| `v8-scale` | Not started |
| `v9-govern` | Not started |
| `v10-resilient` | Not started |


