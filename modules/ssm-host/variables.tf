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
# null the host talks through a NAT gateway to the public internet, where there
# is nothing to name but a CIDR. dev sets it; stage and prod do not.
variable "endpoint_security_group_id" {
  description = "Security group on the interface endpoint ENIs. Null in an environment that reaches the AWS APIs through a NAT gateway instead."
  type        = string
  default     = null
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