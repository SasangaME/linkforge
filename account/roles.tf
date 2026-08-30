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

# --- provisioning -------------------------------------------------------
#
# One document shared by every environment rather than one each, and every
# resource is "*". That is forced rather than lazy: CreateVpc, CreateSubnet and
# CreateLoadBalancer name a resource that does not exist yet, so there is
# nothing to scope an ARN to.
#
# State the consequence plainly. linkforge-gha-apply-dev can create a VPC and
# tag it prod. The only thing separating the environments today is which state
# file each role may write. Resource-level separation between environments is
# an account boundary, and the account boundary is v9-govern.
#
# The usual half-measure is a condition on aws:RequestTag/Project, and it half
# works — several EC2 calls tag after create rather than on create, so it denies
# a subset of the apply and leaves the stack partly built. A failure that stops
# in the middle is worse than a permission that is honestly wide.
#
# The no_escalation guardrail still attaches to all of these roles, so nothing
# below reaches IAM except the two statements that name one specific resource.
data "aws_iam_policy_document" "provisioning" {
  statement {
    sid    = "Network"
    effect = "Allow"
    actions = [
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcAttribute",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:DescribeSubnets",
      "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:DescribeInternetGateways",
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:DescribeRouteTables",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:CreateNatGateway",
      "ec2:DeleteNatGateway",
      "ec2:DescribeNatGateways",
      "ec2:AllocateAddress",
      "ec2:ReleaseAddress",
      "ec2:DescribeAddresses",
      "ec2:DescribeAddressesAttribute",
      "ec2:CreateVpcEndpoint",
      "ec2:DeleteVpcEndpoints",
      "ec2:ModifyVpcEndpoint",
      "ec2:DescribeVpcEndpoints",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribePrefixLists",
      "ec2:DescribeManagedPrefixLists",
      "ec2:GetManagedPrefixListEntries",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:DescribeTags",
    ]
    resources = ["*"]
  }

  # Separate from the block above because these are the actions that decide
  # what may open a connection to what, and they are worth being able to read
  # on their own in the console.
  statement {
    sid    = "SecurityGroups"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
    ]
    resources = ["*"]
  }

  # DescribeInstanceCreditSpecifications is not padding: t3 is a burstable
  # family, the provider reads the credit specification on every refresh, and
  # without it a plan fails after the instance exists rather than before.
  statement {
    sid    = "Instance"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeInstanceAttribute",
      "ec2:ModifyInstanceAttribute",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceCreditSpecifications",
      "ec2:ModifyInstanceMetadataOptions",
      "ec2:DescribeImages",
      "ec2:DescribeVolumes",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeIamInstanceProfileAssociations",
      "ec2:AssociateIamInstanceProfile",
      "ec2:DisassociateIamInstanceProfile",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "LoadBalancer"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerAttributes",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:DescribeTags",
    ]
    resources = ["*"]
  }

  # The two IAM statements that survive the guardrail, because it denies
  # mutation and these read and delegate. PassRole is the dangerous one and it
  # is scoped twice: to one role ARN, and to the one service allowed to receive
  # it. Without the condition, a role that can pass this to lambda.amazonaws.com
  # can run code as it.
  statement {
    sid       = "PassTheHostRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ssm_host.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  # What the stack's data source calls. A denial here reads as "no matching
  # instance profile found", which is indistinguishable from account/ never
  # having been applied.
  statement {
    sid       = "ReadTheInstanceProfile"
    effect    = "Allow"
    actions   = ["iam:GetInstanceProfile"]
    resources = [aws_iam_instance_profile.ssm_host.arn]
  }

  # The AL2023 AMI parameter. Note the empty account field in the ARN — public
  # parameters are owned by AWS, so it is a double colon and not this account's
  # ID. Scoped to the AMI path: this is not a general grant to read SSM
  # parameters, which is where secrets live from v4-state onwards.
  statement {
    sid       = "ReadPublicAmiParameter"
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:*::parameter/aws/service/ami-amazon-linux-latest/*"]
  }
}

resource "aws_iam_role_policy" "gha_apply_provisioning" {
  for_each = toset(var.environments)

  name   = "provisioning"
  role   = aws_iam_role.gha_apply[each.key].id
  policy = data.aws_iam_policy_document.provisioning.json
}