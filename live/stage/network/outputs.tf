# Every output here exists to be fed to a command, not to be read. None of them
# has ever been read, because this stack is validated and never applied — which
# is the point of writing them now rather than on the day stage is first built.

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
  description = "With one shared NAT gateway this should be the same zone the gateway is in. If it is not, the host's egress crosses a zone boundary to reach it."
  value       = module.host.availability_zone
}

# Replaces dev's interface_endpoint_dns_names, which would be an empty map
# here. This is the stage and prod equivalent question — not "did private DNS
# take effect" but "what address does this environment leave from". It is the
# answer to give anyone who asks for an egress allowlist, and it is why the
# module exposes it at all.
output "nat_gateway_public_ips" {
  description = "Addresses this environment's private subnets appear from. The one output here that dev cannot produce, because dev has no NAT gateway."
  value       = module.network.nat_gateway_public_ips
}

output "vpc_id" {
  description = "For the by-hand describe calls that check the applied thing rather than the plan."
  value       = module.network.vpc_id
}
