# LinkForge: Runbook

Almost all work in this project is Terraform code. Some operations are not code, because AWS gives no API or no Terraform resource for them. This file holds those operations.

An operation in this file has three parts: the reason for it, the correct time to do it, and the steps. Each operation also has a check, because a manual operation has no plan output to read.

## Status

| Operation | Milestone | Status |
| --- | --- | --- |
| Enable Cost Explorer | `v0-bootstrap` | Not done |
| Activate the cost allocation tags | `v0-bootstrap` | Not done |

## The correct sequence

These two operations have a strict order. A tag key appears in the Billing console only after two conditions are true. Cost Explorer must be active, and one resource must carry the tag.

| Step | Action | Wait |
| --- | --- | --- |
| 1 | Enable Cost Explorer | Up to 24 hours for the first data |
| 2 | Apply the `bootstrap` module. This creates the first resources with the four tags | None |
| 3 | The four tag keys appear in the Billing console | Up to 24 hours |
| 4 | Activate the four tag keys | Up to 24 hours |

Step 2 is done. The `bootstrap` module is applied, and its six resources carry the four tags. Thus steps 1, 3, and 4 remain, and step 1 is the one that holds the rest.

Thus the time from step 1 to a tagged bill is up to three days. Start the sequence early. Milestone `v1-network` creates the first resources with a large cost, and you cannot tag that cost after the fact.

## Operation 1: Enable Cost Explorer

**Reason.** Cost Explorer holds the cost history of the project. It also controls the cost allocation tags. The tag keys do not appear in the Billing console until Cost Explorer is active.

**When.** Now, and the correct time has passed. The plan was to do this before the apply of the `bootstrap` module. That module is applied, thus the sequence below has started late.

This is not a fault that you can repair. Cost Explorer collects no data from the past. The cost of `bootstrap` is about $0, thus the loss is nothing. The condition is now urgent for a different reason: the four tag keys cannot appear until Cost Explorer is active, and the two waits after that are up to 24 hours each. Milestone `v1-network` makes the first resources with a real cost.

**Steps.**

1. Open the Billing and Cost Management console at `https://console.aws.amazon.com/costmanagement/`.
2. In the navigation pane, select **Cost Explorer**.
3. Select the control that starts Cost Explorer.

**Check.** Open Cost Explorer again. The console must show a report page, and not the start page.

**Note.** Cost Explorer collects data from the day you enable it. It does not show the cost from before that day.

## Operation 2: Activate the cost allocation tags

**Reason.** The `bootstrap` module applies four tags to each resource: `Project`, `Environment`, `ManagedBy`, and `Milestone`. These tags do not divide the bill until you activate them. The `Milestone` tag is the important one. It makes the bill show the cost of each milestone.

**When.** After the tag keys appear in the console. This is up to 24 hours after you apply the `bootstrap` module.

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

The result must contain the four tag keys.

**Note.** The activation applies only to future cost. AWS does not apply a tag to the cost from before the activation. If the four keys do not appear in the console, the cause is almost always one of the two conditions above.

## A note for `v9-govern`

Milestone `v9-govern` moves this account into an AWS Organization. This operation stops the cost allocation tags. An account that becomes a member of an organization loses the active status of its tags. The management account must then activate the tags again.

Thus repeat operation 2 after the account moves. Add this step to the `v9-govern` work.

Also note that only two types of account can open the cost allocation tags manager: a standalone account, and the management account of an organization. Account `749000381089` is a standalone account today, thus it has access.
