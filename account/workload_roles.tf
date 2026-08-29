# --- workload roles -----------------------------------------------------
#
# Roles that an AWS service assumes on behalf of the workload, as against the
# roles in roles.tf that GitHub Actions assumes on behalf of the pipeline.
#
# They live in account/ for a reason found rather than chosen. Every apply role
# carries the no_escalation guardrail, which denies iam:Create*, iam:Attach*
# and iam:Add* on every resource — and CreateRole, AttachRolePolicy,
# CreateInstanceProfile and AddRoleToInstanceProfile are all in that set. A
# CI apply of live/dev/network could never create this role. The stack would
# work from a laptop and fail from the pipeline, which is the worst of the two.
#
# Keeping it here also survives step 9. live/dev/network is destroyed nightly;
# an IAM role standing idle costs nothing, and a profile that outlives the
# instance is one less thing the scheduled destroy has to get right.
#
# This stops scaling at v2-fargate, when a task role and an execution role
# arrive per environment. The answer then is to narrow the guardrail to an IAM
# path — allow writes under /linkforge/service/ with a required permissions
# boundary, deny everywhere else — not to keep adding roles here.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    sid     = "EC2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm_host" {
  name               = "linkforge-ssm-host"
  description        = "Assumed by EC2 instances reached over Session Manager. No key pair and no inbound rule; this role is the whole access mechanism."
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = { Milestone = "v1-network" }
}

# The AWS-managed policy, not a copy of it. It grants the agent's calls to ssm,
# ssmmessages and ec2messages — the same three services step 3 built endpoints
# for — and AWS extends it when the agent needs a new one. A hand-written
# equivalent is a policy that goes stale without saying so.
resource "aws_iam_role_policy_attachment" "ssm_host_core" {
  role       = aws_iam_role.ssm_host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# An instance profile is a container for exactly one role, and the profile is
# what an EC2 instance names. A role on its own cannot be attached to an
# instance. Two resources for one logical thing, always.
resource "aws_iam_instance_profile" "ssm_host" {
  name = "linkforge-ssm-host"
  role = aws_iam_role.ssm_host.name

  tags = { Milestone = "v1-network" }
}