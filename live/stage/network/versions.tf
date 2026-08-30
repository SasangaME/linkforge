terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Copy two of three. Identical to live/dev/network/versions.tf with one word
  # changed, and this is the file where the duplication stops being theoretical
  # — a backend block is read before variables are evaluated, so there is no
  # expression that could derive "stage" from the directory name. Step 8 decides
  # what to do about it; typing it out three times first is what makes that
  # decision about something real.
  backend "s3" {
    bucket       = "linkforge-tfstate-749000381089"
    key          = "stage/network/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
