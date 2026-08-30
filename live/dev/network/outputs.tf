# Every output here exists to be fed to a command, not to be read. A clean
# apply says nothing about whether any of this works.

output "alb_dns_name" {
  description = "curl http://<this>/health. One of the two things that actually prove this milestone."
  value       = module.alb.dns_name
}

output "target_group_arn" {
  description = "The other one. `aws elbv2 describe-target-health --target-group-arn <this>` — every resource in this stack can be created successfully with the health check failing on every attempt, and the plan looks identical either way."
  value       = module.alb.target_group_arn
}

output "host_instance_id" {
  description = "`aws ssm start-session --target <this>`. The only handle the host has: no address, no key pair, no inbound rule."
  value       = module.host.instance_id
}

output "host_availability_zone" {
  description = "Compare to the zone the interface endpoints landed in. If they differ SSM still works and every agent packet crosses a zone boundary."
  value       = module.host.availability_zone
}

output "interface_endpoint_dns_names" {
  description = "What the endpoints answer to. If the host resolves ssm.us-east-1.amazonaws.com to anything outside 10.0.0.0/16, private DNS never took effect and the traffic is trying to leave a subnet with no route out."
  value       = module.network.interface_endpoint_dns_names
}

output "vpc_id" {
  description = "For the by-hand describe calls that check the applied thing rather than the plan."
  value       = module.network.vpc_id
}