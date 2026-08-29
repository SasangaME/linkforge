data "aws_caller_identity" "current" {}

locals {
  state_bucket_arn = "arn:aws:s3:::linkforge-tfstate-${data.aws_caller_identity.current.account_id}"
}

# --- state access ------------------------------------------------------

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

data "aws_iam_policy_document" "state_write" {
  source_policy_documents = [data.aws_iam_policy_document.state_read.json]

  statement {
    sid       = "WriteState"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${local.state_bucket_arn}/*/terraform.tfstate"]
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

# --- apply role ---------------------------------------------------------

resource "aws_iam_role" "gha_apply" {
  name               = "linkforge-gha-apply"
  description        = "Assumed by GitHub Actions on main. Provisioning permissions grow per milestone; none in v0."
  assume_role_policy = data.aws_iam_policy_document.gha_apply_trust.json
}

resource "aws_iam_role_policy" "gha_apply_state" {
  name   = "state-access"
  role   = aws_iam_role.gha_apply.id
  policy = data.aws_iam_policy_document.state_write.json
}

resource "aws_iam_role_policy" "gha_apply_guardrail" {
  name   = "no-escalation"
  role   = aws_iam_role.gha_apply.id
  policy = data.aws_iam_policy_document.no_escalation.json
}