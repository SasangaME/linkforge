# Arguments only. See live/root.hcl for everything that is derived rather than
# written here.
#
# Never applied, and unreachable from CI for the same reason as stage.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  # A local rather than a literal, because prod is the only environment where a
  # second argument derives from this one. Written as a bare 2 twice, a third
  # zone would mean editing two numbers — and editing one of them silently
  # demotes prod to a shared NAT gateway, a change that applies cleanly, halves
  # the bill, and removes the property that makes this environment prod.
  az_count = 2
}

inputs = {
  vpc_cidr = "10.2.0.0/16"
  az_count = local.az_count

  # One NAT gateway per zone. This is the only argument in the project that
  # changes the shape of the route tables rather than the count of something:
  # above 1, modules/network builds a private route table per zone, because a
  # shared table cannot express "route to the gateway in your own zone".
  #
  # It is also the most expensive line in the repository — about $66 a month in
  # gateways alone, before a byte is processed.
  nat_gateway_count           = local.az_count
  interface_endpoint_az_count = 0

  allowed_cidrs = ["0.0.0.0/0"]
}
