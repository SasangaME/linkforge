locals {
  name_prefix = "linkforge-dev"

  # One number, not two. modules/ssm-host takes it as health_port and
  # modules/alb takes it as target_port, and neither module can check that the
  # caller kept them equal. If they diverge, the target group health checks a
  # port nothing is listening on: the apply is clean, every resource is
  # created, and the target sits at Target.Timeout forever. A local is the only
  # thing in this project that keeps them one value.
  app_port = 8080
}

# Looked up by name rather than read out of account/'s state. A
# terraform_remote_state data source would couple this stack to the layout of
# another state file; a name is a contract that survives a state move. If
# account/ has not been applied this fails at plan with "no matching instance
# profile", rather than at boot with an instance that never registers.
data "aws_iam_instance_profile" "ssm_host" {
  name = "linkforge-ssm-host"
}

module "network" {
  source = "../../../modules/network"

  name_prefix = local.name_prefix
  vpc_cidr    = "10.0.0.0/16"

  # Two zones, and it is not an availability decision. A load balancer is
  # refused in one subnet, and a subnet costs nothing.
  az_count = 2

  # The whole cost position of this environment, in two numbers. No NAT
  # gateway; three interface endpoints in a single zone. A fault in that zone
  # costs dev its SSM access entirely, which is the right trade in an
  # environment rebuilt daily and the wrong one anywhere else.
  nat_gateway_count           = 0
  interface_endpoint_az_count = 1
}

module "host" {
  source = "../../../modules/ssm-host"

  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id

  # [0] and not an arbitrary index. The endpoints are placed in the first
  # interface_endpoint_az_count private subnets, so index 0 is the zone that
  # has them. [1] would still work — private DNS is VPC-wide, not per subnet —
  # and would send every agent packet across a zone boundary at a cent a
  # gigabyte. Worth testing once on purpose; not worth changing by accident.
  subnet_id = module.network.private_subnet_ids[0]

  instance_profile_name = data.aws_iam_instance_profile.ssm_host.name

  # Set here, null in stage and prod. Read the comment in those stacks before
  # copying this line into them.
  endpoint_security_group_id = module.network.endpoint_security_group_id

  health_port = local.app_port
}

module "alb" {
  source = "../../../modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids

  # Open, and stated rather than defaulted, because the module refuses to guess
  # on the stack's behalf. What is behind it this milestone is a listener that
  # returns the two characters "ok". The narrow alternative — a /32 for the
  # machine doing the verifying — writes a home address into a public git
  # history permanently and has to be retyped every time the ISP moves it.
  allowed_cidrs = ["0.0.0.0/0"]

  target_port              = local.app_port
  target_security_group_id = module.host.security_group_id

  # The one milestone where a target is a machine. v2-fargate sets this to null
  # and lets the ECS service register and deregister its own tasks.
  target_instance_id = module.host.instance_id
}