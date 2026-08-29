# LinkForge: Cost Model

This project creates infrastructure and destroys it each day. Thus you must know which costs the destroy operation removes. Many costs do not stop when you destroy the stack.

This file is the cost part of `v0-bootstrap`. The budget resources control the cost. This file gives the reasons for the budget values.

## Two terms

This file uses two terms for cost.

| Term | Meaning |
| --- | --- |
| Standing cost | The cost for one month, if the resources operate for all of that month |
| Minimum cost | The cost for one month, after you destroy the stack |

The minimum cost is the cost of LinkForge in a month with no work. The minimum cost increases only when you add a resource that the destroy operation does not remove.

## Three classes of cost

Each cost on the bill is in one of three classes. The class controls how you manage the cost. The size of the cost does not control this.

| Class | Behavior | How to manage it |
| --- | --- | --- |
| Hourly cost | You pay for each hour that the resource exists. Use does not change this cost | Destroy the stack each day |
| Use cost | You pay for each request, each GB, and each function call | No action. This cost is very small in this project |
| Remaining cost | You pay each month after the destroy operation, because the stack does not contain the resource | Delete the resource, or accept the cost |

The third class is the reason for this file. The NAT Gateway costs about $33 each month. This is the largest number in the early milestones, but it is also the safest. The destroy operation removes the NAT Gateway each evening.

The costs that cause a problem are small. Examples are a hosted zone, a KMS key, a log group with no retention period, and a WAF web ACL. You do not destroy these resources, because they are not the subject of your work.

## Prices from the AWS pricing pages

These prices are for `us-east-1`. The early milestones use these resources.

| Resource | Price | Cost for one month |
| --- | --- | --- |
| NAT Gateway | `$0.045` each hour, and `$0.045` for each GB | About $33, and the data cost |
| Application Load Balancer | `$0.0225` each hour, and `$0.008` for each LCU hour | About $16, and the LCU cost |
| Interface VPC endpoint | `$0.01` each hour, **for each zone**, and `$0.01` for each GB | About $7 for each zone |
| Gateway VPC endpoint | No charge | $0 |
| Public IPv4 address | `$0.005` each hour, for each address | Applies to the ALB and to the EIP of each NAT Gateway |
| AWS Budgets, alerts only | No charge, for any quantity of budgets | $0 |
| AWS Budgets, with actions | The first two are free, then `$0.10` each day | $0, if the budgets send alerts only |

The two endpoint rows are the same Terraform resource and they are not the same kind of cost. A gateway endpoint is an entry in a route table, and it is free. An interface endpoint is a network interface in a subnet, and you pay for **each zone that it is placed in**.

That multiplier changes an answer. Milestone `v1-network` needs three interface endpoints for SSM. In one zone they cost about $22 each month, which is less than a NAT Gateway. In two zones they cost about $44, which is more. "Endpoints instead of a NAT Gateway" is cheaper or dearer depending on a number that does not appear in the sentence.

The numbers below do not include the public IPv4 address cost. It is small, about $4 for each address each month, and the earlier estimates in this file were written without it. Add it from the first real bill rather than from this table.

The next table gives approximate values. These values are not exact prices. When you complete a milestone, get the true cost from Cost Explorer. Then replace the value in the table. An estimate that you compare with the true bill has much more value than an estimate that you do not compare.

## Cost of each milestone

| Milestone | Largest cost | Standing cost | Minimum cost | Notes |
| --- | --- | --- | --- | --- |
| `v0-bootstrap` | S3 state, OIDC, budgets | About $0 | About $0 | The state objects are very small. OIDC and the budget alerts are free |
| `v1-network` | Interface endpoints, ALB | About $38 | $0 | The value is for `dev`, the only environment that is built. All costs are hourly. Thus the destroy operation removes all of them |
| `v2-fargate` | Fargate tasks, ECR, logs | About $15 | Low | The ECR images and the logs remain. Give the log group a retention period |
| `v3-pipeline` | GitHub Actions | About $0 | $0 | Free for a public repository. You do not pay for this compute |
| `v4-state` | KMS, Secrets Manager | Low | **Yes** | You pay for each key and each secret every month, even when nothing operates |
| `v5-observable` | Alarms, dashboards | Low | **Yes** | You pay for each alarm and each dashboard every month. The quantity increases quickly |
| `v6-events` | SQS, Lambda, Firehose, Athena | About $0 | It increases | Almost all costs are use costs. The S3 storage remains, and each click event makes it larger |
| `v7-edge` | WAF, Route 53 | Medium | **Yes** | You pay each month for the WAF web ACL, for each WAF rule, and for the hosted zone. You do not destroy these resources each day. The domain registration is a separate annual cost |
| `v8-scale` | Aurora, ElastiCache, RDS Proxy | **High** | Low | This milestone is much more expensive than the others. Here the daily destroy becomes necessary |
| `v9-govern` | AWS Config | Low | **Yes** | AWS Config records each configuration item and each rule result. It does this continuously, for the full account |
| `v10-resilient` | Backup storage, second Region | Medium | **Yes** | A pilot-light Region makes the minimum cost larger. It does not make the standing cost larger |

Two different shapes are in this table. The standing cost increases quickly at `v8-scale`, and it stays high. The minimum cost increases in small permanent steps, and it starts at `v4-state`. You manage these two costs with different methods.

## The value of the daily destroy

Milestones `v1-network` to `v3-pipeline` have a standing cost of about $53 each month. Their minimum cost is almost $0. If you operate this infrastructure for two hours each day, the cost is about $4 each month.

State that as a rate, because the rate is the part you control. `dev` after `v1-network` costs about **five cents each hour**. A session of two hours costs ten cents. The same environment left for one month costs about $38. The infrastructure is identical in both sentences. Only the hours differ.

Thus the number that decides this bill is not in any `.tf` file, and it is not the budget either. It is whether the environment is destroyed. Milestone `v1-network` step 9 makes that automatic, because a control that depends on memory is not a control.

This ratio is the reason for the daily destroy. It is also the reason that `v0-bootstrap` did not select EKS. The EKS control plane costs about $73 each month. You pay this cost even when no application operates. Thus a destroy operation cannot make EKS cheap.

Use the same test for each new decision. Select the resource whose cost stops when the resource stops.

## The budget in `v0-bootstrap`

Step 5 creates one monthly cost budget for the full account. The budget sends an email at 50% and at 80% of the actual cost, and at 100% of the forecast cost. Do not create one budget for each milestone.

AWS does not charge for budget alerts. Thus the price is not the reason for this decision. The reason is the quality of the alert. Eleven budgets give eleven alerts. Each alert is small, and soon you ignore all of them. One budget for the full account answers the only necessary question: is this month different from the last month?

Cost Explorer answers the question about each milestone, and it uses the tags. A budget cannot do this.

The budget must send alerts only. A budget action can stop resources automatically. This function is not correct for this project. It moves the budget into the paid class. It also adds an automatic destroy operation to an account that you use to learn. Examine this function again at `v9-govern`. Cost control is the subject of that milestone.

## Three environments, one of them built

The repository defines `dev`, `stage`, and `prod`. It applies `dev` only.

The arithmetic is the whole argument. A `v1-network` environment in the shape of production costs about $50 each month: about $33 for the NAT Gateway and about $16 for the load balancer. Three copies is about $150 each month. The budget is $10.

The daily destroy does not solve this. It solves the cost of an environment you work in, because you destroy that environment at the end of the day. It does not solve the cost of two environments you do not work in, because you never stand them up to destroy them. The cheapest environment is the one that is only code.

Thus the three environments are not the same shape.

| | `dev` | `stage` | `prod` |
| --- | --- | --- | --- |
| Applied | Yes | No | No |
| Zones | 2 | 2 | 2 |
| NAT Gateway | None | One, shared | One for each zone |
| Interface endpoints | Three, in one zone | None | None |
| Load balancer | One | One | One |
| Cost for each hour | About `$0.053` | About `$0.073` | About `$0.113` |
| Standing cost | About $38 | About $49 | About $82 |

`dev` reaches the AWS APIs through interface endpoints and not through a NAT Gateway.

The first version of this file said that this removes the largest hourly cost of the milestone, and that `dev` is cheaper by two thirds. Both statements were wrong, and the reason is the per-zone multiplier above. Three endpoints in two zones cost about $44 each month, and a NAT Gateway costs about $33. Written that way, `dev` was the most expensive environment in the project and the cheapest one on paper.

`dev` places its endpoints in **one zone**, which costs about $22 and makes the original claim true. The subnets stay in two zones, because a load balancer does not accept one subnet, and a subnet is free. The cost of the single zone is not money. It is that a fault in that zone costs `dev` its SSM access, which is acceptable in an environment that is rebuilt each day and is not acceptable anywhere else.

The destroy is still necessary. About $38 each month is far above the $10 budget, and the load balancer alone is above it. What changed is only the size of the number.

Two rules follow, and both are about correctness and not about cost.

The difference between the environments must be an argument to a module, and never a second copy of the module. An environment that differs from production in its code does not test production. It tests itself.

The `stage` and `prod` columns are the shape those environments will have on the day they are built. They are not a cost today. Write the numbers before the environment exists, because an estimate written after the first bill is not an estimate.

## Cost allocation tags

The tag set is `Project`, `Environment`, `ManagedBy`, and `Milestone`. The `Milestone` tag is the important one. It makes the bill show the cost of each milestone.

This is correct only if you activate the tags as cost allocation tags in the Billing console. Three facts about this operation are important:

- Terraform has no resource for the activation of a user-defined tag. You use the console or the AWS CLI.
- A tag key appears only after Cost Explorer is active and one resource carries the tag. Then the key can take 24 hours to appear, and 24 hours more to activate.
- The activation applies only to future cost. AWS does not apply the tags to the cost from before the activation.

Thus start this sequence early. Milestone `v1-network` creates the first resource with a large cost, and the tags must be active before that milestone. If you wait until you need the data, the data does not exist.

## Rules

1. Give each log group a retention period when you create it. The default value is "never expire". This is a remaining cost, and it always increases.
2. Destroy the stack at the end of each session. From `v1-network`, this controls the difference between a small bill and a large bill. Milestone `v1-network` step 9 adds a scheduled destroy for `dev`, because this rule is the only one in this file that depends on a person remembering it.
3. Examine the minimum cost each month. In a week with no work, the bill must stay at about the same value. If it does not, a resource exists outside the stack.
4. When you complete a milestone, record the true cost. Then replace the estimate in the table above.
5. Read the unit of a price and not only the number. An interface endpoint is priced for each zone, a NAT Gateway for each gateway, and a log group for each GB that it keeps. The unit is where an estimate goes wrong, and the error is a multiple and not a rounding.
