terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# No `backend` block and no `provider` block, and their absence is the point of
# step 8 rather than an omission.
#
# Terragrunt generates both into this directory's copy inside
# `.terragrunt-cache`: the backend key is derived from the calling unit's path
# and the Environment tag from that path's first segment, so neither can be
# typed wrong and neither can drift between environments. See live/root.hcl.
#
# The consequence is that this directory is not runnable with bare `terraform`
# beyond `init -backend=false` and `validate`, which is exactly what CI does
# with it. Anything that touches state goes through Terragrunt.
