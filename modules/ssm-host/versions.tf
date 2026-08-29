terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# No `provider` and no `backend`, same as modules/network. The region, the
# credentials and the default tags belong to the stack in live/.