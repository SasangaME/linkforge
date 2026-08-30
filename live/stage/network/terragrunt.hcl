# Arguments only. See live/root.hcl for everything that is derived rather than
# written here.
#
# This environment has never been applied and cannot be from CI: its GitHub
# Environment does not exist, so no token naming it can be minted and
# linkforge-gha-apply-stage cannot be assumed by anyone.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

inputs = {
  vpc_cidr = "10.1.0.0/16"

  # Prod's topology at the smallest size that still has the topology. One NAT
  # gateway is a single point of failure, which is acceptable in an environment
  # whose job is to prove the resource graph is correct and not acceptable in
  # the one that serves people.
  #
  # Note that this costs more than dev, not less: a gateway is about $33 a
  # month against dev's ~$22 of single-zone endpoints. It is dearer for the
  # reason that makes it stage, which is that it routes the way prod routes.
  nat_gateway_count           = 1
  interface_endpoint_az_count = 0

  allowed_cidrs = ["0.0.0.0/0"]
}
