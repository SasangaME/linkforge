output "instance_id" {
  description = "What `aws ssm start-session --target` names. The proof of this milestone is that this is the only handle the host has."
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "The host's only address. There is no public one."
  value       = aws_instance.this.private_ip
}

output "availability_zone" {
  description = "Zone the host landed in. Compare it to the zones the interface endpoints are in — if they differ, SSM still works and the traffic crosses a zone boundary."
  value       = aws_instance.this.availability_zone
}

# Step 5 needs both: the target group registers the instance ID on this port,
# and the ALB's security group allows egress to the group below while the same
# group gains an ingress rule from the ALB's.
output "security_group_id" {
  description = "The host's security group. Step 5 adds the first ingress rule it has ever had."
  value       = aws_security_group.host.id
}

output "health_port" {
  description = "Port the target group in step 5 health checks."
  value       = var.health_port
}