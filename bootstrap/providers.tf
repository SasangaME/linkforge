provider "aws" {
  region  = "us-east-1"
  profile = "dev"

  default_tags {
    tags = {
      Project     = "linkforge"
      Environment = "shared"
      ManagedBy   = "terraform"
      Milestone   = "v0-bootstrap"
    }
  }
}