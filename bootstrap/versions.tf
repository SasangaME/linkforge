terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "linkforge-tfstate-749000381089"
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    profile      = "dev"
    use_lockfile = true
    encrypt      = true
  }

}
