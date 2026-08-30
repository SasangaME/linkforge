variable "name_prefix" {
  description = "Prefix for every resource name, normally linkforge-<environment>. The module never builds this from an environment name of its own."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name_prefix))
    error_message = "The name_prefix value goes into resource names: lowercase letters, digits and hyphens only."
  }
}

variable "vpc_id" {
  description = "VPC the host and its security group live in. From modules/network."
  type        = string
}

# Singular, because there is one host. The stack picks the subnet rather than
# the module picking it out of a list, so the zone is a visible decision: dev
# passes private_subnet_ids[0], which is the zone its interface endpoints are
# in. Moving it to [1] is a deliberate test that private DNS is VPC-wide, not
# an accident of ordering.
variable "subnet_id" {
  description = "Private subnet the instance is placed in."
  type        = string
}

variable "instance_type" {
  description = "Instance type. The AMI is x86_64, so a t4g would boot into nothing — the architecture is a matched pair, and the mismatch fails at boot rather than at plan."
  type        = string
  default     = "t3.micro"
}

# The name and not the ARN, and looked up by the stack with a data source
# rather than read out of account/'s state. A missing account/ apply then fails
# at plan with "no matching instance profile" instead of at boot with an
# instance that never registers.
variable "instance_profile_name" {
  description = "Instance profile the host assumes. `linkforge-ssm-host`, from account/workload_roles.tf."
  type        = string
}

# Optional, and the two cases are the two ways a private subnet reaches AWS.
# When it is set the host talks to interface endpoints, whose ENIs are inside
# the VPC and therefore have a security group that can be named. When it is
# empty the host talks through a NAT gateway to the public internet, where there
# is nothing to name but a CIDR. dev sets it; stage and prod do not.
#
# A list holding at most one ID, rather than a nullable string, and it is forced
# rather than stylistic. The two rules below are switched on by `count`, a count
# must be known at plan time, and the caller passes a security group that
# Terraform has not created yet. Comparing an unknown against null yields
# unknown, and the plan fails. `length()` of a one-element list is known even
# when the element is not — so the list is what makes the decision plan-time
# knowable, and the empty list is what "no endpoints" now means.
variable "endpoint_security_group_ids" {
  description = "Security group on the interface endpoint ENIs, as a list of at most one. Empty in an environment that reaches the AWS APIs through a NAT gateway instead."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.endpoint_security_group_ids) <= 1
    error_message = "The endpoint_security_group_ids value names at most one security group. modules/network creates exactly one for its interface endpoints."
  }
}

# 8080 and not 80, so the responder needs no privileged port and no root. The
# ALB target group in step 5 health checks this port, and the container in
# v2-fargate will listen on the same one.
variable "health_port" {
  description = "Port the /health responder listens on."
  type        = number
  default     = 8080

  validation {
    condition     = var.health_port > 1024 && var.health_port < 65536
    error_message = "The health_port value must be above 1024. The responder runs unprivileged and cannot bind lower."
  }
}

variable "tags" {
  description = "Extra tags. The provider's default_tags already carry the project-wide four."
  type        = map(string)
  default     = {}
}