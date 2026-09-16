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
# v2-fargate adds its ECS execution and task roles here for the same reason:
# the CI guardrail prevents a stack from creating identities. The project has
# only those two workload identities today. If later milestones need many more,
# move identity creation behind an IAM path and permissions boundary rather than
# making account/ an unbounded collection of service roles.

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

# --- service-linked roles -----------------------------------------------

# Not a role this account writes a policy for. A service-linked role is owned by
# the service, carries an AWS-managed policy that cannot be edited, and has a
# fixed name — one per account, not one per environment. Elastic Load Balancing
# uses this one to put ENIs into the subnets an ALB is given, which is how
# traffic reaches targets over private addresses.
#
# It is here for the same reason as everything above it, and the reason is
# sharper than usual. AWS creates this role for you on the first
# CreateLoadBalancer in an account — and bills the caller `iam:CreateServiceLinkedRole`
# for it. The no_escalation guardrail denies `iam:Create*` on `*`, and an
# explicit Deny is terminal: it is not weighed against Allows and is not beaten
# by a more specific one. So there is no policy that could be added to an apply
# role to make its first ALB succeed. The alternative was narrowing the deny to
# let `iam:CreateServiceLinkedRole` through under an `iam:AWSServiceName`
# condition, which trades a permanent guardrail for a one-time bootstrap.
#
# ORDERING. This must be applied before any load balancer is created by hand.
# devops-admin has the permission the pipeline lacks, so a hand-applied ALB
# creates the role as a side effect, and this resource then fails with
# `InvalidInput: Service role name AWSServiceRoleForElasticLoadBalancing has
# been taken in this account`. Recoverable with `terraform import`, and not
# worth the recovery when applying account/ first costs nothing.
#
# Destroying it is asynchronous and fails while any load balancer still exists.
# account/ is never destroyed, so that is a note rather than a problem — but it
# is the reason this belongs here and not in a stack that step 9 tears down
# nightly.
resource "aws_iam_service_linked_role" "elasticloadbalancing" {
  aws_service_name = "elasticloadbalancing.amazonaws.com"

  tags = { Milestone = "v1-network" }
}

# The one that is easy to miss, because nothing in the ECS stack names it. AWS
# creates AWSServiceRoleForECS on the first CreateCluster or CreateService in
# an account and bills the caller `iam:CreateServiceLinkedRole` for it. The
# no_escalation guardrail denies `iam:Create*` on `*`, and an explicit Deny is
# terminal — the same wall in the same place as elasticloadbalancing above,
# found the same way.
#
# ORDERING, identically. Apply this before creating any cluster or service by
# hand. devops-admin has the permission the pipeline lacks, so a hand-made
# cluster creates the role as a side effect and this then fails with
# `InvalidInput: Service role name AWSServiceRoleForECS has been taken in this
# account`. Recoverable with `terraform import`, and cheaper not to need. If
# the account has ever touched ECS in the console, expect exactly that error on
# the first apply.
resource "aws_iam_service_linked_role" "ecs" {
  aws_service_name = "ecs.amazonaws.com"

  tags = { Milestone = "v2-fargate" }
}

# Application Auto Scaling normally creates this role while registering the
# first ECS scalable target. The CI guardrail denies iam:Create*, so account/
# creates it first under an administrator identity.
resource "aws_iam_service_linked_role" "ecs_application_autoscaling" {
  aws_service_name = "ecs.application-autoscaling.amazonaws.com"

  tags = { Milestone = "v2-fargate" }
}

# --- ECS task execution roles -------------------------------------------

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    sid     = "ECSTasksAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  for_each = toset(var.environments)

  name               = "linkforge-ecs-task-execution-${each.key}"
  description        = "Used by ECS to pull the LinkForge image and write container logs for ${each.key}."
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = {
    Environment = each.key
    Milestone   = "v2-fargate"
  }
}

# AWS maintains the exact ECR pull and CloudWatch Logs permissions ECS needs.
# Do not duplicate it as an inline policy: changes to the execution contract
# should arrive from AWS with the managed policy.
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  for_each = aws_iam_role.ecs_task_execution

  role       = each.value.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  for_each = toset(var.environments)

  name               = "linkforge-ecs-task-${each.key}"
  description        = "Application identity for LinkForge ECS tasks in ${each.key}. Its only permission is the ECS Exec channel; application permissions arrive at v4-state."
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = {
    Environment = each.key
    Milestone   = "v2-fargate"
  }
}

# The task role's only permission at v2-fargate, and it is an operational one
# rather than an application one. A Fargate task has no host to open a session
# on, so `aws ecs execute-command` is the only way to stand inside the container
# and ask what it sees — which is how step 4 is proved before a load balancer
# is involved at step 5.
#
# It reaches ssmmessages, one of the three endpoints dev already built at
# v1-network. No new endpoint and no new cost: the SSM host paid for this.
#
# Granted in all three environments because the permission alone does nothing.
# What switches it on is enable_execute_command on the service, which the stack
# decides per environment — and prod should say false.
data "aws_iam_policy_document" "ecs_exec" {
  statement {
    sid    = "ECSExecChannels"
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ecs_task_exec" {
  for_each = aws_iam_role.ecs_task

  name   = "ecs-exec"
  role   = each.value.id
  policy = data.aws_iam_policy_document.ecs_exec.json
}
