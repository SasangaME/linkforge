data "aws_region" "current" {}

# The AMI comes from a public SSM parameter that AWS repoints at every new
# release. `value` is marked sensitive because the data source cannot know a
# parameter is not a secret; this one is public and the AMI ID is the single
# most useful thing in the plan output, so it is unwrapped deliberately.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Gateway endpoint traffic is matched against the security group by prefix
# list, not by CIDR. Without the rule below, dev reaches SSM and fails the
# first time the agent updates itself out of S3 — with no error naming S3.
data "aws_ec2_managed_prefix_list" "s3" {
  name = "com.amazonaws.${data.aws_region.current.region}.s3"
}

# --- security group -----------------------------------------------------

# No inline ingress or egress block, which is two separate decisions.
#
# No ingress is the point of the milestone: nothing in this account can open a
# connection to this host, and it is still reachable. The access mechanism is
# the instance profile, not a port.
#
# No inline egress means Terraform removes the allow-all egress rule AWS
# attaches to every new security group, leaving the rules below as the whole
# of it. Rules are separate resources rather than inline because step 5 adds
# an ALB whose group allows egress to this one while this one allows ingress
# from that one — two inline blocks referencing each other is a cycle.
resource "aws_security_group" "host" {
  name        = "${var.name_prefix}-ssm-host"
  description = "SSM host. No inbound rule at all; outbound to the AWS APIs only."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-ssm-host" })
}

# The agent's control channel, its data channel, and ec2messages — all three
# reach ENIs inside the VPC, so the destination is a security group and not an
# address. This is the tightest egress rule in the project and it is only
# possible because the far end is something this account owns.
#
# `length()` and not a comparison against null, and the difference is the whole
# reason this variable is a list. A count must be known at plan time, and the
# caller passes a security group that does not exist yet — so `id == null` is
# an unknown compared to null, which is unknown, and the plan fails outright
# with "The count value depends on resource attributes that cannot be
# determined until apply". The LENGTH of a one-element list is known even when
# the element inside it is not. See README.md.
resource "aws_vpc_security_group_egress_rule" "endpoints" {
  count = length(var.endpoint_security_group_ids)

  security_group_id            = aws_security_group.host.id
  description                  = "HTTPS to the interface endpoint ENIs"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = var.endpoint_security_group_ids[count.index]

  tags = merge(var.tags, { Name = "${var.name_prefix}-ssm-host-endpoints" })
}

# The NAT path. There is no group on the other side of a NAT gateway, so this
# is as narrow as it goes: one port, every address. Note what that means — the
# environment with a NAT gateway has a strictly looser egress rule than the one
# without, which is the opposite of how the cost table reads.
resource "aws_vpc_security_group_egress_rule" "internet" {
  count = length(var.endpoint_security_group_ids) == 0 ? 1 : 0

  security_group_id = aws_security_group.host.id
  description       = "HTTPS to the AWS APIs through the NAT gateway"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(var.tags, { Name = "${var.name_prefix}-ssm-host-internet" })
}

# Unconditional, because the S3 gateway endpoint is created in every
# environment — it is free, so there is no count switching it off. Redundant
# in an environment that already allows 443 everywhere, and harmless there.
resource "aws_vpc_security_group_egress_rule" "s3" {
  security_group_id = aws_security_group.host.id
  description       = "HTTPS to S3 through the gateway endpoint — agent updates and plugin binaries"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_ec2_managed_prefix_list.s3.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-ssm-host-s3" })
}

# --- the host -----------------------------------------------------------

resource "aws_instance" "this" {
  ami           = nonsensitive(data.aws_ssm_parameter.al2023.value)
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  vpc_security_group_ids = [aws_security_group.host.id]
  iam_instance_profile   = var.instance_profile_name

  # Both stated rather than left to the default. The subnet does not set
  # map_public_ip_on_launch, so this is already false; writing it makes the
  # claim in the milestone — no public address — checkable in the file.
  associate_public_ip_address = false

  # key_name is deliberately absent. There is no key pair anywhere in this
  # project, which is why losing SSM access means rebuilding the host rather
  # than falling back to SSH. That is the intended failure mode.

  # IMDSv2 required. The agent gets its credentials from IMDS and handles the
  # token exchange; hop limit 1 keeps them off anything running in a container
  # on this host, which is nothing today and is the default worth keeping.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # encrypted = true is redundant in us-east-1, where account/baseline.tf turned
  # on EBS encryption by default. It is written anyway because a module should
  # state what it requires rather than inherit it from an account setting it
  # cannot see.
  #
  # It is NOT a safeguard for v10-resilient's second region, which is what this
  # comment used to claim. RunInstances with Encrypted=true on a root mapping
  # from an unencrypted snapshot — which the AL2023 AMI is — may be accepted
  # only because encryption by default is on, in which case this line is what
  # fails the launch in a region without it. Untested. Settle it with one
  # hand-launched instance there before writing any of v10, not with --dry-run.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    health_port = var.health_port
  })

  # user_data runs once, at first boot. Without this, editing the script
  # updates the attribute in state, applies cleanly, and changes nothing on
  # the machine — a change that reports success and has no effect.
  user_data_replace_on_change = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-ssm-host" })

  # The parameter above is repointed by AWS at every AL2023 release, so without
  # this the next unrelated apply proposes replacing the host. What it costs is
  # that patching becomes an explicit `terraform apply -replace` rather than a
  # side effect — the right way round for a machine, and the reason this host
  # is destroyed nightly rather than patched.
  lifecycle {
    ignore_changes = [ami]
  }
}