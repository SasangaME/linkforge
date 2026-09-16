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
  # Empty in an environment with a NAT gateway, where interface_endpoint_az_count
  # is 0. An interface endpoint with no subnets is an API error, not an endpoint
  # that does nothing, so the count has to switch the resource off rather than
  # narrow the slice.
  #
  # Six services, and the last three arrived with v2-fargate rather than being
  # overlooked at v1. A Fargate task pulls its image over the task ENI, so
  # ecr.api authorises the pull, ecr.dkr serves the manifest, the S3 gateway
  # endpoint below carries the layers, and logs takes the awslogs driver's
  # output. Miss any one and the service applies cleanly while every task dies
  # in PENDING.
  #
  # What it costs, stated because README.md has been wrong about this number
  # once already. An interface endpoint is billed per zone, so dev goes from
  # about $22 a month standing to about $44 — more than the $33 NAT gateway
  # the endpoints exist to avoid. The standing figure is not what decides it.
  # dev is destroyed nightly, so the bill follows hours: at three hours a day
  # six endpoints is $5.40 a month against a gateway's $4.05. A dollar is what
  # a private tier with no route to the internet costs here.
  interface_endpoints = var.interface_endpoint_az_count > 0 ? toset([
    "ssm",
    "ssmmessages",
    "ec2messages",
    "ecr.api",
    "ecr.dkr",
    "logs",
  ]) : toset([])
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