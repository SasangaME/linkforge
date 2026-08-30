terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # The key is the path relative to live/, which live/README.md fixes as
  # <environment>/<stack>/terraform.tfstate. None of this can be a variable:
  # a backend block is read before variables are evaluated, so these nine lines
  # are copied verbatim into three directories with one word different. That
  # duplication is the entire case for step 8, and it is worth typing out three
  # times first rather than reaching for Terragrunt before the problem exists.
  backend "s3" {
    bucket       = "linkforge-tfstate-749000381089"
    key          = "dev/network/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}