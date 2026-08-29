# LinkForge: Runbook

Almost all work in this project is Terraform code. Some operations are not code, because AWS gives no API or no Terraform resource for them. This file holds those operations.

An operation in this file has three parts: the reason for it, the correct time to do it, and the steps. Each operation also has a check, because a manual operation has no plan output to read.

## Status

| Operation | Milestone | Status |
| --- | --- | --- |
| Enable Cost Explorer | `v0-bootstrap` | Done |
| Activate the cost allocation tags | `v0-bootstrap` | Done, 2026-08-28 |
| Confirm the budget alert subscription | `v0-bootstrap` | Done, 2026-08-29 |
| Set the plan role repository variable | `v0-bootstrap` | Done, 2026-08-29 |

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

## Operation 3: Confirm the budget alert subscription

**Reason.** The `account` module creates an SNS topic, an email subscription, and a budget. Terraform creates the subscription, but it cannot confirm it. AWS sends a mail with a link, and only the owner of the inbox can open that link. Until then the subscription holds the status `PendingConfirmation` and the topic delivers nothing.

This is the failure that this operation exists to prevent. The apply reports success, the console shows the subscription, and the alert path is dead. The budget then passes a threshold in silence.

**When.** After each apply that creates the subscription. This is normally once. It repeats if the subscription is destroyed, or if `budget_alert_email` changes, because a new address is a new subscription.

Note also that AWS deletes a subscription that stays unconfirmed for three days. If you miss the mail, run `terraform apply` again to make a new one.

**Steps.**

1. Open the inbox named in `account/account.tfvars`.
2. Find the mail from `no-reply@sns.amazonaws.com`, with the subject `AWS Notification - Subscription Confirmation`.
3. Select the link **Confirm subscription**.
4. Stop there. Read the warning below before you select anything else.

The mail can land in the spam folder. It comes from an address that the inbox has not seen before.

**Do not select an unsubscribe link.** The page that opens after a confirmation reads `Subscription confirmed!`, and it offers a link to unsubscribe. Each delivered notification carries the same link in its footer, and Gmail also shows its own **Unsubscribe** control beside the sender, because SNS sets the `List-Unsubscribe` header. Any of the three deactivates the subscription, and the inbox then receives a mail that begins `Your subscription to the topic below has been deactivated`.

Close the tab at the confirmation page. The recovery, if this happens, is in the next section.

**Check.** Read the `PendingConfirmation` attribute of the exact subscription that Terraform holds:

```bash
export AWS_PROFILE=dev

aws sns get-subscription-attributes \
  --subscription-arn "$(terraform -chdir=account state show \
      aws_sns_topic_subscription.budget_alerts_email | awk '/^ *arn /{print $3}' | tr -d '\"')" \
  --query 'Attributes.PendingConfirmation' --output text
```

`false` means the subscription is confirmed and delivers. `true` means the mail is not yet answered. A `NotFound` error means the subscription no longer exists.

**Do not use `list-subscriptions-by-topic` for this.** That call was the first check written here, and it is wrong. It returns subscriptions that were destroyed, as an entry whose ARN is the literal string `Deleted`, and it can omit a live subscription entirely for a long time. On 2026-08-29 it reported a single `Deleted` entry while a confirmed subscription was working. A check that reports a dead subscription and hides a live one is worse than no check.

The console is no better. It shows the subscription in every state.

The stronger check tests delivery and not configuration, because a confirmed subscription still proves nothing about the topic policy:

```bash
aws sns publish \
  --topic-arn "$(terraform -chdir=account output -raw budget_alert_topic_arn)" \
  --subject "LinkForge test" --message "Test of the budget alert path."
```

The mail must arrive. This is the check that closes the third item of the `v0-bootstrap` definition of done.

Run this test once only. Each delivered mail carries an unsubscribe link, thus each test creates another chance to break the subscription for no new knowledge.

Note that this test publishes as `devops-admin`, and the budget publishes as the service principal `budgets.amazonaws.com`. Thus the test proves the subscription, and not the topic policy that lets Budgets in. The policy has no test short of a real threshold. Read it instead: it must allow `SNS:Publish` to that service principal, with `aws:SourceAccount` equal to this account.

### Recovery from an unsubscribe

Two facts make this worth its own section.

**Terraform does not detect the deactivation.** The state holds the subscription, the API reports it as `Deleted`, and `terraform plan` reports `No changes`. Thus the alert path is dead and the plan says the account is correct. This is the strongest example in the project of a check that reassures and proves nothing.

**Therefore `plan` is not a check for this resource.** Use `get-subscription-attributes`, as in the check above.

Recover by forcing a replacement, because Terraform will not do it alone:

```bash
terraform -chdir=account apply \
  -replace=aws_sns_topic_subscription.budget_alerts_email \
  -var-file=account.tfvars
```

This destroys the dead subscription, creates a new one, and sends a new confirmation mail. Then return to the steps above.

Expect **two** mails from a replacement, and read them in the correct order. The destroy sends `Your subscription to the topic below has been deactivated`, because SNS mails the endpoint whenever a subscription is removed, including a removal by Terraform. The create sends the new confirmation request. The deactivation mail refers to the old subscription and is not a fault. Answer the confirmation mail and ignore the other.

The console offers a second path. SNS → Topics → `linkforge-budget-alerts` → Subscriptions → **Request confirmation**. That path sends the mail without touching the state, and it is correct when the subscription is `PendingConfirmation`. It is not correct when the subscription is `Deleted`, because there is no longer a subscription to confirm.

## Operation 4: Set the plan role repository variable

**Reason.** The pull request workflow assumes the plan role by ARN. GitHub Actions cannot read Terraform state, thus it cannot read the `gha_plan_role_arn` output, thus the ARN must be given to the repository by hand.

Terraform has no resource for this. A GitHub repository variable is managed by the `github` provider, and that provider needs a GitHub token with repository administration rights. Holding such a token to set one string is a worse trade than setting the string by hand, so this project does not adopt the provider.

**Why a variable and not a secret.** The ARN is not credential material. A secret is masked in the log, and the masking hides the exact value you need to read on the day an assume fails. The account ID inside the ARN is already committed in both backend blocks, where it must be a literal string, so nothing is concealed by treating it as a secret.

Note that a repository variable is visible to anyone who can read the Actions logs, and it appears unmasked there. That is intended.

**When.** Once, before the first pull request. Repeat if the role is destroyed and recreated under another name. Repeat also at `v9-govern`, where the account changes and the ARN changes with it.

**Steps.**

1. Read the value from the `account` module:

   ```bash
   export AWS_PROFILE=dev
   terraform -chdir=account output -raw gha_plan_role_arn
   ```

   Today it returns `arn:aws:iam::749000381089:role/linkforge-gha-plan`.

2. Open `https://github.com/SasangaME/linkforge/settings/variables/actions`.
3. Select **New repository variable**.
4. Set the name to `AWS_PLAN_ROLE_ARN` and the value to the ARN from step 1.
5. Select **Add variable**.

The `gh` CLI does the same in one command, if it is ever installed on this machine:

```bash
gh variable set AWS_PLAN_ROLE_ARN --body "$(terraform -chdir=account output -raw gha_plan_role_arn)"
```

**Check.** There is no AWS-side check, because this value lives in GitHub. Two checks exist.

The weak check is the settings page. The variable must appear in the list, with the correct value.

The strong check is the workflow. Open a pull request and read the **whoami** step. It must print:

```
arn:aws:sts::749000381089:assumed-role/linkforge-gha-plan/linkforge-plan-<run id>
```

Any other identity means the variable holds the wrong ARN.

**The failure signature when it is unset.** This is worth knowing, because the message does not name the cause. An unset variable expands to an empty string, so `role-to-assume` is empty, and `configure-aws-credentials` fails with a complaint about credentials rather than about a missing variable. If that step fails on a fresh repository, check this operation first.

## A note for `v9-govern`

Milestone `v9-govern` moves this account into an AWS Organization. This operation stops the cost allocation tags. An account that becomes a member of an organization loses the active status of its tags. The management account must then activate the tags again.

Thus repeat operation 2 after the account moves. Add this step to the `v9-govern` work.

Also note that only two types of account can open the cost allocation tags manager: a standalone account, and the management account of an organization. Account `749000381089` is a standalone account today, thus it has access.
