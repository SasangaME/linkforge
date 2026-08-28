# LinkForge: Runbook

Almost all work in this project is Terraform code. Some operations are not code, because AWS gives no API or no Terraform resource for them. This file holds those operations.

An operation in this file has three parts: the reason for it, the correct time to do it, and the steps. Each operation also has a check, because a manual operation has no plan output to read.

## Status

| Operation | Milestone | Status |
| --- | --- | --- |
9| Enable Cost Explorer | `v0-bootstrap` | Done |
| Activate the cost allocation tags | `v0-bootstrap` | Done, 2026-08-28 |

## The correct sequence

These two operations have a strict order. A tag key appears in the Billing console only after two conditions are true. Cost Explorer must be active, and one resource must carry the tag.

| Step | Action | Wait |
| --- | --- | --- |
| 1 | Enable Cost Explorer | Up to 24 hours for the first data |
| 2 | Apply the `bootstrap` module. This creates the first resources with the four tags | None |
| 3 | The four tag keys appear in the Billing console | Up to 24 hours |
| 4 | Activate the four tag keys | Up to 24 hours |

All four steps are complete. The sequence closed on 2026-08-28, before milestone `v1-network` created any resource with a real cost. No wait remains.

The warning that this section carried is now spent, but keep it in mind for `v9-govern`. The sequence takes up to three days from a cold start, and you cannot tag a cost after the fact.

## Operation 1: Enable Cost Explorer

**Reason.** Cost Explorer holds the cost history of the project. It also controls the cost allocation tags. The tag keys do not appear in the Billing console until Cost Explorer is active.

**When.** Done. Cost Explorer is active on account `749000381089`.

The date of the activation is not recorded, and Cost Explorer does not report it. The service holds cost data for August 2026, thus it was active at least from the start of that month. This covers the whole life of the `bootstrap` module, so no cost of this project is missing from the history.

**Steps.**

1. Open the Billing and Cost Management console at `https://console.aws.amazon.com/costmanagement/`.
2. In the navigation pane, select **Cost Explorer**.
3. Select the control that starts Cost Explorer.

**Check.** Open Cost Explorer again. The console must show a report page, and not the start page.

The CLI gives a stronger check, because it tests the service and not the console:

```bash
aws ce get-cost-and-usage --time-period Start=2026-08-01,End=2026-08-28 \
  --granularity MONTHLY --metrics UnblendedCost
```

An account without Cost Explorer returns `DataUnavailableException`. An account with it returns an amount. This account returns an amount.

**Note.** Cost Explorer collects data from the day you enable it. It does not show the cost from before that day.

## Operation 2: Activate the cost allocation tags

**Reason.** The `bootstrap` module applies four tags to each resource: `Project`, `Environment`, `ManagedBy`, and `Milestone`. These tags do not divide the bill until you activate them. The `Milestone` tag is the important one. It makes the bill show the cost of each milestone.

**When.** Done, on 2026-08-28.

The activation happened in two parts, which is worth knowing because the first part looked complete and was not. `Project` and `ManagedBy` were activated on 2026-08-14. `Environment` and `Milestone` were left inactive and were found only by a later check. `Milestone` is the key that this operation exists for. A partial activation reports no error and shows no symptom until you read a bill that cannot break the cost down.

**Conditions.** Two conditions must be true before you start:

- Cost Explorer is active. See operation 1.
- One resource or more carries the four tags. The `bootstrap` module does this.

**Steps.**

1. Open the Billing and Cost Management console at `https://console.aws.amazon.com/costmanagement/`.
2. In the navigation pane, select **Cost allocation tags**.
3. Select the four tag keys: `Project`, `Environment`, `ManagedBy`, and `Milestone`.
4. Select **Activate**.

**Alternative.** The console is not the only method. AWS gives the `UpdateCostAllocationTagsStatus` API operation, and the AWS CLI gives `aws ce update-cost-allocation-tags-status`. The command takes a list of tag keys and a status for each key. Read `aws ce update-cost-allocation-tags-status help` for the correct syntax before you use it. Terraform has no resource for this operation.

**Check.** Use the CLI:

```bash
aws ce list-cost-allocation-tags --status Active
```

The result must contain the four tag keys. It does.

Note the price. Each request to the Cost Explorer API costs $0.01. The console is free, and so are the tags themselves. Thus a check of this kind is correct once, by hand, and wrong in a loop, a dashboard, or a scheduled job. The budget in step 5 is the free path to the same knowledge, because it pushes a notification instead of asking a question.

**Note.** The activation applies only to future cost. AWS does not apply a tag to the cost from before the activation. If the four keys do not appear in the console, the cause is almost always one of the two conditions above.

## A note for `v9-govern`

Milestone `v9-govern` moves this account into an AWS Organization. This operation stops the cost allocation tags. An account that becomes a member of an organization loses the active status of its tags. The management account must then activate the tags again.

Thus repeat operation 2 after the account moves. Add this step to the `v9-govern` work.

Also note that only two types of account can open the cost allocation tags manager: a standalone account, and the management account of an organization. Account `749000381089` is a standalone account today, thus it has access.
