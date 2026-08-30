variable "name_prefix" {
  description = "Prefix for every resource name, normally linkforge-<environment>. The module never builds this from an environment name of its own."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name_prefix))
    error_message = "The name_prefix value goes into resource names: lowercase letters, digits and hyphens only."
  }

  # The load balancer's name is this plus "-alb", and AWS caps that at 32.
  # Caught here rather than by the API, because the API refuses it after the
  # security group and its rules have already been created.
  validation {
    condition     = length(var.name_prefix) <= 28
    error_message = "The name_prefix value must be 28 characters or fewer. A load balancer name is capped at 32 and this one gains a '-alb' suffix."
  }
}

variable "vpc_id" {
  description = "VPC the load balancer and its security group live in. From modules/network."
  type        = string
}

# Public, and at least two. A load balancer is placed in subnets in two
# separate zones and the API refuses one — which is why modules/network keeps
# az_count at 2 even in dev, where the endpoints sit in a single zone. A subnet
# is free; a second zone of interface endpoints is not.
variable "public_subnet_ids" {
  description = "Public subnets the load balancer's nodes are placed in, one per zone."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "The public_subnet_ids value must name at least two subnets, in two zones. An application load balancer cannot be created in one."
  }
}

# No default, deliberately. This is the only argument in the project that
# decides what the internet may open a connection to, so the stack states it
# rather than inheriting it. dev may narrow this to one address; nothing here
# guesses on its behalf.
variable "allowed_cidrs" {
  description = "Source ranges allowed to reach the listener. 0.0.0.0/0 is the public front door; a single /32 is a private demonstration."
  type        = list(string)

  validation {
    condition     = length(var.allowed_cidrs) > 0
    error_message = "The allowed_cidrs value must name at least one range. A load balancer no one may reach is a $16 a month resource with no purpose."
  }

  validation {
    condition     = alltrue([for c in var.allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "Every allowed_cidrs entry must be a valid IPv4 CIDR block."
  }
}

variable "listener_port" {
  description = "Port the load balancer listens on. 80, and plain HTTP, until v7-edge brings a certificate and the domain that justifies one."
  type        = number
  default     = 80
}

# 8080, matching modules/ssm-host's health_port and the container port that
# v2-fargate will use. The two are one number in two modules and the stack is
# what keeps them equal.
variable "target_port" {
  description = "Port the targets listen on. The health check uses the same port."
  type        = number
  default     = 8080
}

variable "target_security_group_id" {
  description = "Security group on the targets. This module writes an ingress rule into it — see README.md for why that is not the caller's job."
  type        = string
}

# Optional, and null is the v2-fargate case rather than an error. An ECS
# service registers and deregisters its own tasks, so a target group with a
# static attachment would fight it.
variable "target_instance_id" {
  description = "Instance to register, for the one milestone where a target is a machine rather than a service. Null leaves the target group empty."
  type        = string
  default     = null
}

variable "health_check_path" {
  description = "Route the target group checks. Must not read a datastore: one fault there would fail every target at once."
  type        = string
  default     = "/health"
}

# The default is 300, and it is the reason a destroy that should take a minute
# takes six. dev is destroyed nightly by step 9, and there is nothing in flight
# to drain from a health responder.
variable "deregistration_delay" {
  description = "Seconds the target group waits for in-flight requests before removing a target. Low here because nothing this milestone serves is worth draining."
  type        = number
  default     = 30

  validation {
    condition     = var.deregistration_delay >= 0 && var.deregistration_delay <= 3600
    error_message = "The deregistration_delay value must be between 0 and 3600 seconds."
  }
}

variable "tags" {
  description = "Extra tags. The provider's default_tags already carry the project-wide four."
  type        = map(string)
  default     = {}
}