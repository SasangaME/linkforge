# Every output here exists to be fed to a command, not to be read. None of them
# has ever been read, because this stack is validated and never applied — which
# is the point of writing them now rather than on the day prod is first built.

output "alb_dns_name" {
  description = "curl http://<this>/health. One of the two things that would actually prove this environment."
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
  description = "Unlike stage, this carries no routing consequence: with a NAT gateway in every zone the host leaves through its own zone's gateway whichever subnet it landed in."
  value       = module.host.availability_zone
}

output "nat_gateway_public_ips" {
  description = "Two addresses, one per zone, and both of them have to appear in any egress allowlist a third party asks for. An allowlist built from one is an outage in the other zone."
  value       = module.network.nat_gateway_public_ips
}

# Prod-only, and it is the observable form of nat_gateway_count > 1. Two IDs
# here means the per-zone routing this environment pays for actually exists;
# one means the module built a shared table and a zone failure takes both
# zones with it. That is the check to run on the first apply, because nothing
# else in this stack looks different when it is wrong.
output "private_route_table_ids" {
  description = "One per zone in prod, against one in total everywhere else. The count is the difference this environment is paying for."
  value       = module.network.private_route_table_ids
}

output "vpc_id" {
  description = "For the by-hand describe calls that check the applied thing rather than the plan."
  value       = module.network.vpc_id
}
