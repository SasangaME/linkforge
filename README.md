# LinkForge

LinkForge is a link shortener with click analytics. It is also the application that every piece of infrastructure in this repository exists to serve.

## The product

Three endpoints.

| Endpoint | Behavior |
| --- | --- |
| `POST /links` | Accepts a long URL, returns a short code |
| `GET /{code}` | 302-redirects to the long URL, emits a click event |
| `GET /links/{code}/stats` | Returns click counts, referrers, geography |

That is about 150 lines of application code in any language. It is boring on purpose. The application is never the subject of this project — the resource graph around it is.

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

## About the infrastructure code

The design is described in prose: which resources, how they connect, and which arguments matter. It is not copy-paste HCL. The purpose is to build the mental model of the resource graph, not to accumulate configuration.
