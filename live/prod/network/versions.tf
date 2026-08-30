terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Copy three of three, and the one that settles step 8. Twenty-seven lines
  # across three directories differing in a single word, with no expression
  # that could derive it — a backend block is read before variables exist, so
  # bucket, key and region cannot be interpolated from anything. This is the
  # duplication Terragrunt removes, and it is now large enough to weigh rather
  # than imagine.
  backend "s3" {
    bucket       = "linkforge-tfstate-749000381089"
    key          = "prod/network/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
