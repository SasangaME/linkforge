data "aws_caller_identity" "current" {}

locals {
  state_bucket_arn = "arn:aws:s3:::linkforge-tfstate-${data.aws_caller_identity.current.account_id}"
}

# --- state access ------------------------------------------------------

# Read across every environment, and that is not an oversight: the plan role
# carries ReadOnlyAccess, so narrowing which state files it may read would hide
# nothing it cannot already reach through the API. The `*` in an IAM resource
# pattern crosses `/`, so these two patterns matched `account/terraform.tfstate`
# before the environments existed and match `dev/network/terraform.tfstate` now.
data "aws_iam_policy_document" "state_read" {
  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]
  }

  statement {
    sid       = "ReadState"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${local.state_bucket_arn}/*/terraform.tfstate"]
  }

  statement {
    sid    = "ManageLock"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${local.state_bucket_arn}/*.tflock"]
  }
}

# One bucket holds every environment's state, separated by key prefix. The
# boundary that matters is the write, and a prefix scoped into the role policy
# draws it exactly where a separate bucket would — without bootstrapping two
# more buckets that cannot store their own state. Separate buckets start earning
# their keep when the environments are in separate accounts, because a bucket
# policy is then the cross-account boundary. That is `v9-govern`.
data "aws_iam_policy_document" "env_state" {
  for_each = toset(var.environments)

  # Not narrowed with an s3:prefix condition. The backend lists the bucket to
  # find its object, and a condition that is fractionally too tight fails as a
  # missing state file rather than as a denial — an hour of debugging to hide
  # a set of key names that are not the sensitive part. The objects are.
  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]
  }

  statement {
    sid    = "ReadWriteOwnState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${local.state_bucket_arn}/${each.key}/*/terraform.tfstate"]
  }

  # The lock is an object, so releasing it is a delete. This is the one place
  # an apply role is allowed to delete anything in the bucket, and it is scoped
  # to the same prefix — a stuck lock in dev cannot be cleared by prod's role,
  # which is the correct answer to "who broke this".
  statement {
    sid    = "ManageOwnLock"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${local.state_bucket_arn}/${each.key}/*.tflock"]
  }
}

# --- permanent guardrail ------------------------------------------------

data "aws_iam_policy_document" "no_escalation" {
  statement {
    sid    = "DenyIdentityMutation"
    effect = "Deny"
    actions = [
      "iam:Add*",
      "iam:Attach*",
      "iam:Change*",
      "iam:Create*",
      "iam:Delete*",
      "iam:Detach*",
      "iam:Put*",
      "iam:Remove*",
      "iam:Set*",
      "iam:Update*",
      "iam:Upload*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyAccountControl"
    effect = "Deny"
    actions = [
      "organizations:*",
      "account:*",
    ]
    resources = ["*"]
  }
}

# --- plan role ----------------------------------------------------------

resource "aws_iam_role" "gha_plan" {
  name               = "linkforge-gha-plan"
  description        = "Assumed by GitHub Actions on pull requests. Read-only, plus state lock."
  assume_role_policy = data.aws_iam_policy_document.gha_plan_trust.json
}

resource "aws_iam_role_policy_attachment" "gha_plan_readonly" {
  role       = aws_iam_role.gha_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "gha_plan_state" {
  name   = "state-access"
  role   = aws_iam_role.gha_plan.id
  policy = data.aws_iam_policy_document.state_read.json
}

resource "aws_iam_role_policy" "gha_plan_guardrail" {
  name   = "no-escalation"
  role   = aws_iam_role.gha_plan.id
  policy = data.aws_iam_policy_document.no_escalation.json
}

# --- apply roles, one per environment -----------------------------------

resource "aws_iam_role" "gha_apply" {
  for_each = toset(var.environments)

  name               = "linkforge-gha-apply-${each.key}"
  description        = "Assumed by GitHub Actions jobs declaring `environment: ${each.key}`. Provisioning permissions grow per milestone; none in v0."
  assume_role_policy = data.aws_iam_policy_document.gha_apply_trust[each.key].json
}

resource "aws_iam_role_policy" "gha_apply_state" {
  for_each = toset(var.environments)

  name   = "state-access"
  role   = aws_iam_role.gha_apply[each.key].id
  policy = data.aws_iam_policy_document.env_state[each.key].json
}

resource "aws_iam_role_policy" "gha_apply_guardrail" {
  for_each = toset(var.environments)

  name   = "no-escalation"
  role   = aws_iam_role.gha_apply[each.key].id
  policy = data.aws_iam_policy_document.no_escalation.json
}
