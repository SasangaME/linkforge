locals {
  name_prefix = "linkforge-stage"

  # Same reasoning as dev: modules/ssm-host takes it as health_port and
  # modules/alb takes it as target_port, and nothing but this local keeps them
  # equal. The failure is a clean apply where the target group checks a port
  # nothing listens on.
  app_port = 8080
}

# The same profile name as dev, and that is worth noticing here rather than in
# dev, because dev is where it looks obviously fine and stage is where it stops
# being. `linkforge-ssm-host` is one IAM identity shared by every environment's
# host. Harmless today — the role holds AmazonSSMManagedInstanceCore and
# nothing else, so there is no environment-specific privilege to leak across.
# It stops being harmless at v2-fargate, when a task role gets a table name and
# a bucket in it, and account/workload_roles.tf already says what the answer is
# then: an IAM path with a permissions boundary, not more roles listed by hand.
data "aws_iam_instance_profile" "ssm_host" {
  name = "linkforge-ssm-host"
}

module "network" {
  source = "../../../modules/network"

  name_prefix = local.name_prefix

  # 10.1, not 10.0. Non-overlapping with dev and prod so that peering or a
  # transit gateway later is a decision rather than a re-address — and a VPC
  # CIDR cannot be changed, so it is decided before the first apply or it is
  # decided by destroying the VPC and everything holding an address in it.
  vpc_cidr = "10.1.0.0/16"

  az_count = 2

  # Prod's topology at the smallest size that still has the topology. One NAT
  # gateway is a single point of failure, which is the right trade in an
  # environment whose job is to prove the resource graph is correct and the
  # wrong one in the environment that serves people.
  #
  # Note what this pair costs against dev's. A NAT gateway is about $33 a month
  # against dev's ~$22 of single-zone endpoints, so stage is dearer — but it is
  # dearer for the reason that makes it stage, which is that it routes the way
  # prod routes.
  nat_gateway_count           = 1
  interface_endpoint_az_count = 0
}

module "host" {
  source = "../../../modules/ssm-host"

  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id

  # [0] and it matters more here than in dev. With nat_gateway_count = 1 the
  # module builds one shared private route table, so every private subnet
  # routes through the gateway in zone 0 whichever zone it is in. The index is
  # not what makes this work; it is what decides whether the host's egress
  # crosses a zone boundary to reach the gateway. [0] is the one that does not.
  subnet_id = module.network.private_subnet_ids[0]

  instance_profile_name = data.aws_iam_instance_profile.ssm_host.name

  # Empty, and written rather than omitted. The default is already [] so this
  # line changes nothing — it exists so that the difference from dev is visible
  # in the file rather than being an argument that is missing.
  #
  # It must not be [module.network.endpoint_security_group_id]. modules/network
  # creates that security group unconditionally, so the output is a real ID
  # here even though interface_endpoint_az_count is 0 and no endpoint ENI is
  # attached to it. Passing it would give the host one egress rule to an empty
  # group and suppress the rule to the internet, because the module treats the
  # two as alternatives. The result is a clean plan, a clean apply, and an
  # instance that never appears in Session Manager, with nothing anywhere
  # naming the cause. The output being a real ID rather than null is exactly
  # what makes this the dangerous line to copy across from dev.
  endpoint_security_group_ids = []

  health_port = local.app_port
}

module "alb" {
  source = "../../../modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids

  # Same answer as dev and the same reasoning: what is behind this listener is
  # a responder that returns "ok". It is a value to revisit at v2-fargate, when
  # what is behind it is the application, and at v7-edge, when the front door
  # moves to CloudFront and the load balancer's own exposure should narrow to
  # the CloudFront prefix list rather than stay open.
  allowed_cidrs = ["0.0.0.0/0"]

  target_port              = local.app_port
  target_security_group_id = module.host.security_group_id

  # A list of one, because at this milestone a target is a machine. v2-fargate
  # empties it and lets the ECS service register and deregister its own tasks.
  target_instance_ids = [module.host.instance_id]
}
