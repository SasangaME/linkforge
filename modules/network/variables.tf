variable "name_prefix" {
  description = "Prefix for every resource name, normally linkforge-<environment>. The module never builds this from an environment name of its own."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name_prefix))
    error_message = "The name_prefix value goes into resource names: lowercase letters, digits and hyphens only."
  }
}

# The mask matters and the reason is in README.md. Subnet addresses are derived
# with four extra bits, so a block smaller than a /20 cannot be divided and a
# /16 leaves each subnet a /20.
variable "vpc_cidr" {
  description = "Address range of the VPC. Fixed for the life of the VPC: changing it destroys the VPC and everything holding an address in it."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "The vpc_cidr value must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "The vpc_cidr value must be a /20 or larger. Subnets are derived with four extra bits and a smaller block leaves nothing to divide."
  }
}

variable "az_count" {
  description = "Availability zones to spread the subnets across. Two everywhere today."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 4
    error_message = "The az_count value must be between 1 and 4. Four is the address plan's maximum, not the region's."
  }
}

# Not a boolean, because the three environments need three answers rather than
# two: dev has none and reaches the AWS APIs through endpoints, stage has one
# and accepts that it is a single point of failure, prod has one in each zone so
# that losing a zone loses only that zone.
variable "nat_gateway_count" {
  description = "NAT gateways to create. Must be 0, 1, or az_count. Any other number leaves it undefined which private subnets share a gateway."
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1, var.az_count], var.nat_gateway_count)
    error_message = "The nat_gateway_count value must be 0, 1, or equal to az_count."
  }
}

variable "tags" {
  description = "Extra tags for every resource. The provider's default_tags already carry the project-wide four."
  type        = map(string)
  default     = {}
}
