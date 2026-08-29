data "aws_region" "current" {}

resource "aws_security_group" "endpoints" {
  name        = "${var.name_prefix}-endpoints"
  description = "Interface endpoint ENIs. HTTPS in from the VPC, nothing out."
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from anything in the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-endpoints" })
}

locals {
  # Empty in dev, where interface_endpoint_az_count is 0. An interface endpoint
  # with no subnets is an API error, not an endpoint that does nothing, so the
  # count has to switch the resource off rather than just narrow the slice.
  interface_endpoints = var.interface_endpoint_az_count > 0 ? toset(["ssm", "ssmmessages", "ec2messages"]) : toset([])
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = slice(aws_subnet.private[*].id, 0, var.interface_endpoint_az_count)
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}" })
}

# Free, so it is created in every environment whatever the counts say. It is a
# route table entry rather than an ENI, which is why it takes no subnets and no
# security group and cannot be reached from a zone that has no route table
# carrying it.
#
# Private tables only, and that is a choice rather than an omission: nothing in
# a public subnet reaches S3 today. The module exports the public table's ID for
# the day something does.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = merge(var.tags, { Name = "${var.name_prefix}-s3" })
}