# Arguments only. The backend key, the provider, the Environment tag and the
# stack source all come from live/root.hcl, derived from this directory's path.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

inputs = {
  # 10.0, non-overlapping with stage and prod so that peering later is a
  # decision rather than a re-address. A VPC CIDR cannot be changed.
  vpc_cidr = "10.0.0.0/16"

  # The whole cost position of this environment, in two numbers. No NAT
  # gateway; three interface endpoints in a single zone, about $22 a month
  # against a gateway's $33. A fault in that zone costs dev its SSM access
  # entirely, which is the right trade in an environment rebuilt daily and the
  # wrong one anywhere else.
  #
  # The non-zero endpoint count is also what wires the host's egress to the
  # endpoint security group instead of to the internet. That used to be a
  # separate argument each stack stated for itself, and stating it wrongly was
  # silent. It is now derived in stacks/network from this number.
  nat_gateway_count           = 0
  interface_endpoint_az_count = 1

  # Open, and stated rather than defaulted, because the module refuses to guess
  # on a stack's behalf. What is behind it this milestone is a responder that
  # returns two characters.
  allowed_cidrs = ["0.0.0.0/0"]
}
