# --- address plan ------------------------------------------------------

# Subnet addresses are computed from the VPC CIDR rather than passed in, and the
# newbits are a constant rather than a function of az_count. That is the whole
# point of max_azs: deriving the width from az_count would re-derive every
# subnet the day a third zone is added, and Terraform would destroy and recreate
# all of them together with anything holding an address. Four extra bits give
# sixteen blocks, allocated four to a tier, so a tier's address never moves.
locals {
  max_azs = 4

  tiers = {
    public  = 0
    private = 1
    # 2 and 3 are unused. A database tier lands in tier 2 at v8-scale without
    # moving anything above it, which is the reason to leave the room now.
  }

  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  public_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, local.tiers.public * local.max_azs + i)]
  private_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, local.tiers.private * local.max_azs + i)]

  # One shared private route table when there is one gateway or none, and one
  # per zone when there is a gateway in each. A shared table cannot express
  # "route to the gateway in your own zone", which is the only reason prod has
  # more than one.
  private_route_table_count = var.nat_gateway_count > 1 ? var.az_count : 1
}

# Zones the account can actually use. The default already excludes Local Zones
# and Wavelength, and the filter says so rather than relying on it.
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# --- the VPC ------------------------------------------------------------

# Both DNS settings are on because the interface endpoints are on their way. An
# interface endpoint's private DNS overrides the public name of the service
# inside the VPC, and it cannot do that without DNS hostnames and DNS support.
# Turning them on later is free; discovering they are off is a debugging session
# where the SSM agent times out against a public address.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = var.name_prefix })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = var.name_prefix })
}

# --- subnets ------------------------------------------------------------

# Nothing in this project launches an instance into a public subnet, so nothing
# needs an automatic public address. The load balancer's addresses come from the
# load balancer and a NAT gateway's comes from its EIP.
resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-${local.azs[count.index]}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-${local.azs[count.index]}"
    Tier = "private"
  })
}

# --- NAT ----------------------------------------------------------------

# None of this exists in dev, where nat_gateway_count is 0 and every count below
# resolves to zero resources.
resource "aws_eip" "nat" {
  count = var.nat_gateway_count

  domain = "vpc"

  tags = merge(var.tags, { Name = "${var.name_prefix}-nat-${local.azs[count.index]}" })
}

# The depends_on is not decoration. A NAT gateway needs a route to the internet
# at creation time, and the only reference between these two resources is
# through the route table, which Terraform builds in parallel with this.
resource "aws_nat_gateway" "this" {
  count = var.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, { Name = "${var.name_prefix}-${local.azs[count.index]}" })

  depends_on = [aws_internet_gateway.this]
}

# --- routing ------------------------------------------------------------

# One public table for every zone. Public subnets all route to the same internet
# gateway, which is a regional resource, so there is nothing zonal to express.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-public" })
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count = local.private_route_table_count

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = local.private_route_table_count > 1 ? "${var.name_prefix}-private-${local.azs[count.index]}" : "${var.name_prefix}-private"
  })
}

# In dev this is zero routes, and that is the design rather than an omission:
# the private subnets have no path off the VPC at all. Whatever reaches AWS from
# them reaches it through an endpoint, and anything that is not an endpoint is
# unreachable. A NAT gateway would hide that distinction behind a default route.
resource "aws_route" "private_default" {
  count = var.nat_gateway_count

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

# Every private subnet takes its own zone's table when there is one, and the
# single shared table otherwise.
resource "aws_route_table_association" "private" {
  count = var.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[local.private_route_table_count > 1 ? count.index : 0].id
}
