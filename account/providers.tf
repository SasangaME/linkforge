provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "linkforge"
      Environment = "shared"
      ManagedBy   = "terraform"
      Milestone   = "v0-bootstrap"
    }
  }
}