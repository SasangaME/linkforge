output "vpc_id" {
  description = "Consumed by every security group, endpoint and load balancer built on this network."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "Source range for the endpoint security group in step 3. Read from the resource rather than echoed from the variable, so it stays correct if AWS ever normalises it."
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "Zones the subnets were placed in, in the order the subnet lists use."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Where the load balancer goes in step 5."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Where the host goes in step 4, and the interface endpoints in step 3."
  value       = aws_subnet.private[*].id
}

# The S3 gateway endpoint in step 3 attaches to route tables and not to subnets,
# which is the one place a route table ID leaves this module.
output "private_route_table_ids" {
  description = "Private route tables, one per zone when NAT is per zone and one in total otherwise."
  value       = aws_route_table.private[*].id
}

output "public_route_table_id" {
  description = "The single public route table, for the same reason as the private ones."
  value       = aws_route_table.public.id
}

output "nat_gateway_public_ips" {
  description = "Empty in dev. The addresses an egress allowlist would name, if anything ever needs one."
  value       = aws_eip.nat[*].public_ip
}
