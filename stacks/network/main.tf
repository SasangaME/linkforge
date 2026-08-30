# The `v1-network` stack: one VPC, one host reachable only over Session Manager,
# and one load balancer in front of it. Three environments call this directory
# with different arguments and identical code, because a staging environment
# that differs from production in its code rather than in its arguments is not
# testing production.
#
# Before step 8 this composition was copied into live/dev/network,
# live/stage/network and live/prod/network. Consolidating it here was worth
# doing at exactly this moment: dev had been destroyed, so its state held no
# resources and no address could be orphaned by the move. Done a day later it
# would have needed `terraform state mv` for every resource in it.

locals {
  name_prefix = "linkforge-${var.environment}"

  # Derived, not passed in, and that is the repair of a trap rather than a
  # tidy-up. Each stack used to state its own endpoint_security_group_ids, and
  # the wrong answer was the plausible one: modules/network creates that
  # security group unconditionally, so its output is a real ID even in an
  # environment with no endpoints attached to it. A stack that passed it
  # through gave the host one egress rule to an empty group and suppressed the
  # rule to the internet — a clean plan, a clean apply, and an instance that
  # never appears in Session Manager with nothing anywhere naming the cause.
  #
  # Now the wiring follows the argument that decides it, in one place, and the
  # mistake cannot be made from a caller. This is the strongest single argument
  # for consolidating the stack rather than only its backend block.
  #
  # It is also count-safe: interface_endpoint_az_count is a variable, so the
  # length of this list is known at plan time. A list built from a resource
  # attribute would not be — see modules/alb for what that costs.
  endpoint_security_group_ids = var.interface_endpoint_az_count > 0 ? [module.network.endpoint_security_group_id] : []
}

# Looked up by name rather than read out of account/'s state. A
# terraform_remote_state data source would couple this stack to the layout of
# another state file; a name is a contract that survives a state move. If
# account/ has not been applied this fails at plan with "no matching instance
# profile", rather than at boot with an instance that never registers.
#
# The profile is one shared IAM identity across all three environments. That is
# acceptable only because the role holds AmazonSSMManagedInstanceCore and
# nothing else, so there is no environment-specific privilege to leak across.
# It stops being acceptable at v2-fargate, when a task role names a table and a
# bucket; account/workload_roles.tf records the answer for that day.
data "aws_iam_instance_profile" "ssm_host" {
  name = "linkforge-ssm-host"
}

module "network" {
  source = "../../modules/network"

  name_prefix                 = local.name_prefix
  vpc_cidr                    = var.vpc_cidr
  az_count                    = var.az_count
  nat_gateway_count           = var.nat_gateway_count
  interface_endpoint_az_count = var.interface_endpoint_az_count
}

module "host" {
  source = "../../modules/ssm-host"

  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id

  # [0], and what the index means depends on the environment. In dev it is the
  # zone the interface endpoints are in. In stage, with one shared NAT gateway
  # and one shared route table, it is the zone whose egress does not cross a
  # boundary to reach the gateway. In prod, with a gateway and a table per
  # zone, it is arbitrary. One line, three different reasons for being right.
  subnet_id = module.network.private_subnet_ids[0]

  instance_profile_name       = data.aws_iam_instance_profile.ssm_host.name
  endpoint_security_group_ids = local.endpoint_security_group_ids

  health_port = var.app_port
}

module "alb" {
  source = "../../modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  allowed_cidrs     = var.allowed_cidrs

  # The same var.app_port that reached the host above as health_port. The two
  # modules cannot check each other, and before step 8 the thing keeping them
  # equal was a local repeated in three stack files. Now it is one variable
  # with one default, which is the difference between a convention and a fact.
  target_port              = var.app_port
  target_security_group_id = module.host.security_group_id

  # A list of one, because at this milestone a target is a machine. v2-fargate
  # empties it and lets the ECS service register and deregister its own tasks.
  target_instance_ids = [module.host.instance_id]
}
