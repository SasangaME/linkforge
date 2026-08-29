terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# No `provider` block and no `backend` block. A module inherits the provider its
# caller configured, so the region, the credentials and the default tags are all
# decisions of the stack in live/ and none of them are decisions of this module.
