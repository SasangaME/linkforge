# The root Terragrunt configuration. Every unit under live/ includes this file
# and adds nothing but its own arguments.
#
# WHAT THIS REMOVES, AND WHY IT IS NOT MERELY TIDINESS
#
# A `backend` block is read before variables are evaluated, so `bucket`, `key`
# and `region` are literals or they are nothing. Three stacks meant three
# copies differing in one word, and the word was the state key — the single
# value in this repository where a typo is silent and destructive, because a
# stack pointed at another environment's key adopts that environment's state
# and plans to destroy the difference.
#
# The alternative considered was Terraform's own partial configuration:
# `init -backend-config="key=..."`. It removes the same lines and converts a
# literal that is right by construction into a flag every human and every
# workflow has to get right. Here the key is DERIVED from the unit's directory
# path, so it cannot disagree with where the file lives. That is the whole
# argument for this file.

locals {
  # path_relative_to_include() is evaluated in the including unit's context, so
  # for live/dev/network/terragrunt.hcl it is "dev/network". replace() is not
  # decoration: Terragrunt 1.0 returns native OS paths, so this is a backslash
  # on Windows and the state key would silently change shape.
  unit_path = replace(path_relative_to_include(), "\\", "/")

  environment = split("/", local.unit_path)[0]
  stack       = split("/", local.unit_path)[1]

  account_id = "749000381089"
  region     = "us-east-1"
  milestone  = "v1-network"
}

# The source is derived from the directory too: live/<env>/network runs
# stacks/network. The convention is the contract, and a unit whose directory
# name has no matching stack fails loudly at the first command.
#
# The `//` is load-bearing and not a path separator. Terragrunt copies
# everything BEFORE it — here the whole repository — into .terragrunt-cache and
# then runs in the part after. Without it only stacks/network would be copied
# and its `../../modules/network` references would resolve to nothing. As of
# Terragrunt 1.0 this happens on every run, `source` or not, so there is no
# "runs in place" mode left to fall back on.
terraform {
  source = "${get_repo_root()}//stacks/${local.stack}"

  # Terragrunt excludes hidden files from the copy, and .terraform.lock.hcl is
  # hidden. Without this the provider version is re-resolved on every run and
  # the lock file in the repository is decorative.
  include_in_copy = [".terraform.lock.hcl", "**/.terraform.lock.hcl"]
}

# `generate` and not Terragrunt's `remote_state` block, deliberately.
# `remote_state` manages the bucket — it will create one that does not exist
# and enforce settings on one that does. This bucket is owned by bootstrap/,
# which gave it versioning, encryption, a public access block and a policy.
# Two things managing one bucket is drift with no owner. Terragrunt is a code
# generator here and nothing more.
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-HCL
    terraform {
      backend "s3" {
        bucket       = "linkforge-tfstate-${local.account_id}"
        key          = "${local.unit_path}/terraform.tfstate"
        region       = "${local.region}"
        encrypt      = true
        use_lockfile = true
      }
    }
  HCL
}

# The Environment tag is derived from the same path segment as the state key,
# so a stack cannot write dev's state while tagging its resources prod. Before
# this, those were two literals in two files that happened to agree.
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-HCL
    provider "aws" {
      region = "${local.region}"

      default_tags {
        tags = {
          Project     = "linkforge"
          Environment = "${local.environment}"
          ManagedBy   = "terraform"
          Milestone   = "${local.milestone}"
        }
      }
    }
  HCL
}

# Supplied here rather than by each unit, for the same reason as the two above:
# derived from the directory, it cannot disagree with the state key or the tag.
# A unit that set its own would be free to be wrong.
inputs = {
  environment = local.environment
}
