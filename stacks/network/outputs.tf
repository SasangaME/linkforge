# Every output here exists to be fed to a command. A clean apply says nothing
# about whether any of this works.
#
# Consolidating three stacks into one module has a cost, and it lands here.
# Each environment used to publish only the outputs that meant something in it:
# dev had the endpoint DNS names, stage and prod had the NAT gateway addresses,
# prod alone had the route table IDs. One module publishes all of them to all
# three, so two are always empty in any given environment. That is a real loss
# of signal and it was the price of removing the duplication — recorded here
# rather than hidden, because an output that is structurally empty reads like a
# check that passed.

output "alb_dns_name" {
  description = "curl http://<this>/health. One of the two things that actually prove this environment."
  value       = module.alb.dns_name
}

output "target_group_arn" {
  description = "The other one. `aws elbv2 describe-target-health --target-group-arn <this>` — every resource here can be created successfully with the health check failing on every attempt, and the plan looks identical either way."
  value       = module.alb.target_group_arn
}

output "host_instance_id" {
  description = "`aws ssm start-session --target <this>`. The only handle the host has: no address, no key pair, no inbound rule."
  value       = module.host.instance_id
}

output "host_availability_zone" {
  description = "Zone the host landed in. Compare it to the endpoint zone where endpoints exist, and to the NAT gateway zone where one shared gateway does."
  value       = module.host.availability_zone
}

# Empty wherever interface_endpoint_az_count is 0.
output "interface_endpoint_dns_names" {
  description = "What the interface endpoints answer to, keyed by service. Empty in an environment that reaches AWS through a NAT gateway. Where it is populated, a host resolving ssm.<region>.amazonaws.com to an address outside the VPC CIDR means private DNS never took effect."
  value       = module.network.interface_endpoint_dns_names
}

# Empty wherever nat_gateway_count is 0.
output "nat_gateway_public_ips" {
  description = "Addresses this environment's private subnets appear from. Empty in dev. Where there is more than one, an egress allowlist built from a single address is an outage in the other zone."
  value       = module.network.nat_gateway_public_ips
}

# One everywhere except prod, and the count is the point.
output "private_route_table_ids" {
  description = "One per zone when nat_gateway_count is above 1, one in total otherwise. In prod, two IDs is the only observable form of the per-zone routing it pays for — nothing else in the stack looks different when it is wrong."
  value       = module.network.private_route_table_ids
}

output "vpc_id" {
  description = "For the by-hand describe calls that check the applied thing rather than the plan."
  value       = module.network.vpc_id
}
