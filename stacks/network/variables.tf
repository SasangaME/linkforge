# Every variable here is a value that differs between environments. Anything
# identical across all three belongs in main.tf as a literal or a local — a
# variable with the same value in every caller is a knob nobody turns and one
# more thing to read.

variable "environment" {
  description = "Environment name, supplying the resource name prefix. Not written by any unit: live/root.hcl derives it from the calling directory's path, the same segment the state key and the Environment tag come from, so a stack cannot name itself one thing and store its state under another."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "The environment value goes into IAM-visible resource names: lowercase letters, digits and hyphens only."
  }
}

variable "vpc_cidr" {
  description = "Address range of the VPC. Fixed for the life of the environment: changing it destroys the VPC and everything holding an address in it."
  type        = string
}

variable "az_count" {
  description = "Availability zones for the subnets. Two everywhere, and it is not an availability decision — a load balancer is refused in one subnet and a subnet costs nothing."
  type        = number
  default     = 2
}

variable "nat_gateway_count" {
  description = "NAT gateways. 0 in dev, 1 in stage, one per zone in prod. Above 1 the network module builds a private route table per zone, which is what makes a zone failure cost prod one zone instead of all of them."
  type        = number
}

# The pair below is the only dimension the three environments differ in: what is
# allowed to cost money while idle. modules/network rejects the case where both
# are zero, because an environment with neither has no route from its private
# subnets to the AWS APIs and it is a mistake that applies cleanly and fails
# silently.
variable "interface_endpoint_az_count" {
  description = "Zones to place the SSM interface endpoints in. Billed per endpoint per zone, so this is a cost decision before it is an availability one. Non-zero is also what wires the host's egress to the endpoints instead of to the internet — see main.tf."
  type        = number
}

variable "allowed_cidrs" {
  description = "Source ranges allowed to reach the load balancer's listener. The one argument in this project that decides what the internet may open a connection to, which is why it has no default anywhere."
  type        = list(string)
}

variable "app_port" {
  description = "Port the targets listen on and the target group health checks. One number, used as the host's health_port and the load balancer's target_port — see main.tf for why it must not become two."
  type        = number
  default     = 8080
}
