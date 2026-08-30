# --- what an apply role may build ---------------------------------------
#
# The third policy on every apply role, after the state prefix and the
# guardrail. It is the one file in account/ that grows at every milestone, which
# is why it is a file rather than another section of roles.tf: roles.tf is about
# who the identities are, and this is about what one of them may do this month.
#
# It is attached to all three environments, not just dev. The roles for stage
# and prod stay inert because GitHub will not mint a token carrying an
# environment claim it holds no record of — see oidc.tf. Promotion should be a
# GitHub Environment and a branch, never an IAM change made under time pressure.
#
# Everything here is `v1-network`: the VPC and its routing, the interface and
# gateway endpoints, the SSM host, and the load balancer in front of it. The
# guardrail still sits over all of it, so nothing below can touch identity even
# by accident.
#
# Two things are deliberately not done, and both would look like improvements.
#
# No resource ARNs on the EC2 statements. Most EC2 mutations either take no
# resource-level permission at all or take one that only becomes meaningful with
# a tag condition, and tag-on-create conditions have to be right for every
# resource in the module or the apply fails halfway with a denial that names an
# action rather than the condition that refused it. The account holds one
# project, so the boundary the tags would draw already exists at the account
# edge. This gets revisited when v9-govern splits the accounts, which is the
# milestone that makes it a real boundary rather than a written one.
#
# No speculative actions. Where it was not certain an action was needed it was
# left out, because an over-granted policy is invisible and an under-granted one
# fails by name — Terraform prints the exact action STS refused. Adding one line
# is a two-minute hand-apply; discovering a year later that CI could delete
# something it never needed is not.

data "aws_iam_policy_document" "provisioning" {

  # --- read ---------------------------------------------------------------

  # `plan` refreshes every resource on every run, so this is what the pipeline
  # spends most of its time doing. Not one EC2 Describe action supports a
  # resource ARN — `*` is not this statement declining to narrow, it is the only
  # form the API will accept — and none of them can change anything.
  statement {
    sid    = "ReadEC2"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ec2:GetManagedPrefixListEntries",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadELB"
    effect    = "Allow"
    actions   = ["elasticloadbalancing:Describe*"]
    resources = ["*"]
  }

  # --- the network --------------------------------------------------------

  # The Delete half is not optional. Step 9 destroys dev every night with this
  # same role, and a policy that can create but not delete fails partway through
  # a destroy — leaving orphaned resources and a state file that disagrees with
  # the account, which is worse than not being able to destroy at all.
  statement {
    sid    = "ManageVPC"
    effect = "Allow"
    actions = [
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",

      "ec2:CreateInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",

      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:ModifySubnetAttribute",

      # Zero of these in dev, where nat_gateway_count is 0. They are here
      # because stage and prod share this policy and because a permission that
      # only appears on the day it is needed is a permission nobody tested.
      "ec2:AllocateAddress",
      "ec2:ReleaseAddress",
      "ec2:CreateNatGateway",
      "ec2:DeleteNatGateway",

      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:ReplaceRouteTableAssociation",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:ReplaceRoute",

      "ec2:CreateVpcEndpoint",
      "ec2:DeleteVpcEndpoints",
      "ec2:ModifyVpcEndpoint",
    ]
    resources = ["*"]
  }

  # Rules are separate resources in every module here — aws_vpc_security_group
  # _ingress_rule rather than an inline block — so both the Authorize and the
  # Revoke sides are exercised on an ordinary change, not only on a destroy.
  statement {
    sid    = "ManageSecurityGroups"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
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

  # Its own statement because tagging is its own failure mode: every resource in
  # every module carries the four-tag default_tags set, so a missing CreateTags
  # does not fail one resource — it fails all of them, immediately after the
  # create call that already succeeded.
  statement {
    sid    = "TagEC2"
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }

  # --- the host -----------------------------------------------------------

  statement {
    sid    = "ManageInstances"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:StopInstances",
      "ec2:StartInstances",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyInstanceMetadataOptions",

      # Set at launch by RunInstances; these three are the update path, when the
      # profile changes on a host that already exists.
      "ec2:AssociateIamInstanceProfile",
      "ec2:DisassociateIamInstanceProfile",
      "ec2:ReplaceIamInstanceProfileAssociation",
    ]
    resources = ["*"]
  }

  # The AMI comes from a public SSM parameter AWS repoints at every AL2023
  # release. Public, but still a read that has to be allowed — and scoped to the
  # one path, because this is the only reason the pipeline touches SSM at all.
  # The account field of the ARN is empty: the parameter belongs to AWS.
  statement {
    sid    = "ReadAMIParameter"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = ["arn:aws:ssm:*::parameter/aws/service/ami-amazon-linux-latest/*"]
  }

  # --- the load balancer --------------------------------------------------

  statement {
    sid    = "ManageELB"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:SetIpAddressType",

      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",

      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:SetRulePriorities",

      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]
    resources = ["*"]
  }

  # No iam:CreateServiceLinkedRole, and it is not an omission — the guardrail
  # denies it and an explicit Deny cannot be overridden, so the line would be
  # dead text. AWSServiceRoleForElasticLoadBalancing is created once by hand in
  # workload_roles.tf, which is what makes CreateLoadBalancer above reachable.

  # --- identity, read only ------------------------------------------------

  # The stack looks the instance profile up with a data source rather than
  # reading account/'s state, so a missing account/ apply fails at plan with
  # "no matching instance profile" instead of at boot with a host that never
  # registers. That lookup is this permission. Get* is not in the guardrail's
  # deny list; these are reads.
  statement {
    sid    = "ReadWorkloadIdentity"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetInstanceProfile",
    ]
    resources = [
      aws_iam_role.ssm_host.arn,
      aws_iam_instance_profile.ssm_host.arn,
    ]
  }

  # The one genuinely escalation-adjacent permission in this file, and the only
  # one scoped to a single ARN. Handing a role to an instance is handing that
  # role's credentials to whatever runs on it, so an unscoped PassRole is an
  # unscoped account: launch a host, attach any role, read its credentials from
  # IMDS. PassRole is not caught by the guardrail — the deny covers Add, Attach,
  # Change, Create, Delete, Detach, Put, Remove, Set, Update and Upload — so
  # this condition is the whole of the boundary.
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
}

resource "aws_iam_role_policy" "gha_apply_provisioning" {
  for_each = toset(var.environments)

  name   = "provisioning"
  role   = aws_iam_role.gha_apply[each.key].id
  policy = data.aws_iam_policy_document.provisioning.json
}
