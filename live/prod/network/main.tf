locals {
  name_prefix = "linkforge-prod"

  # Same reasoning as dev and stage: modules/ssm-host takes it as health_port
  # and modules/alb takes it as target_port, and nothing but this local keeps
  # them equal. The failure is a clean apply where the target group checks a
  # port nothing listens on.
  app_port = 8080

  # A local here and a literal in the other two stacks, because prod is the
  # only environment where a second argument is derived from it. Written as a
  # number in both places, a third zone would mean editing two values, and
  # editing one of them silently demotes prod to a shared NAT gateway — a
  # change that applies cleanly, halves the bill, and removes the property that
  # makes this environment prod.
  az_count = 2
}

# The same profile name as dev and stage. One IAM identity shared by every
# environment's host, which is acceptable only because the role holds
# AmazonSSMManagedInstanceCore and nothing else — there is no
# environment-specific privilege here to leak across. It stops being acceptable
# at v2-fargate, when a task role names a table and a bucket, and prod is the
# environment where that matters. account/workload_roles.tf already records the
# answer: an IAM path with a required permissions boundary, not more roles
# listed by hand.
data "aws_iam_instance_profile" "ssm_host" {
  name = "linkforge-ssm-host"
}

module "network" {
  source = "../../../modules/network"

  name_prefix = local.name_prefix

  # 10.2, non-overlapping with dev's 10.0 and stage's 10.1, so that peering or
  # a transit gateway later is a decision rather than a re-address. A VPC CIDR
  # cannot be changed: it is decided before the first apply, or it is decided
  # by destroying the VPC and everything holding an address in it.
  vpc_cidr = "10.2.0.0/16"

  az_count = local.az_count

  # One NAT gateway per zone, and this is the only argument in the project that
  # changes the shape of the route tables rather than the count of something. A
  # shared private route table cannot express "route to the gateway in your own
  # zone", so above 1 the module builds one table per zone. That is what makes
  # a zone failure cost prod one zone instead of all of them, and it is the
  # single difference between this file and stage's that is about availability
  # rather than about money.
  #
  # It is also the most expensive line in the repository: about $66 a month in
  # gateways alone, before a byte is processed.
  nat_gateway_count           = local.az_count
  interface_endpoint_az_count = 0
}

module "host" {
  source = "../../../modules/ssm-host"

  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id

  # [0], and unlike stage the index carries no routing consequence here. With a
  # gateway in every zone the module builds a route table per zone, so a host
  # in any private subnet reaches the internet through its own zone's gateway
  # and never crosses a boundary to do it. The index is arbitrary in prod and
  # is not arbitrary in stage, which is worth knowing before someone
  # "harmonises" the three files.
  subnet_id = module.network.private_subnet_ids[0]

  instance_profile_name = data.aws_iam_instance_profile.ssm_host.name

  # Empty, and written rather than omitted, for the same reason as stage: the
  # default is already [] and this line exists so the difference from dev is
  # visible in the file instead of being an argument that is missing.
  #
  # It must not be [module.network.endpoint_security_group_id].
  # modules/network creates that group unconditionally, so the output is a real
  # ID here even with interface_endpoint_az_count at 0 and no endpoint ENI
  # attached to it. Passing it would give the host one egress rule to an empty
  # group and suppress the rule to the internet, because the module treats the
  # two as alternatives — a clean plan, a clean apply, and an instance that
  # never appears in Session Manager with nothing anywhere naming the cause.
  endpoint_security_group_ids = []

  health_port = local.app_port
}

module "alb" {
  source = "../../../modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids

  # Open, and the value in this file is the one that will need revisiting
  # first. Today it fronts a responder that returns "ok". At v7-edge the public
  # front door becomes CloudFront, and a load balancer that stays open to
  # 0.0.0.0/0 behind it can be reached directly, bypassing WAF and the
  # certificate — so this narrows to the com.amazonaws.global.cloudfront
  # .origin-facing prefix list on that day. Noted here rather than in dev
  # because dev is where being bypassed does not matter.
  allowed_cidrs = ["0.0.0.0/0"]

  target_port              = local.app_port
  target_security_group_id = module.host.security_group_id

  # A list of one, because at this milestone a target is a machine — and a
  # single machine in a single subnet is not a prod topology. It is not meant
  # to be: this host exists to prove the private subnets and SSM work, and
  # v2-fargate empties this list and replaces it with an ECS service that
  # registers its own tasks across both zones.
  target_instance_ids = [module.host.instance_id]
}
