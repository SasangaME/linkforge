# The provider is configured here and nowhere else. modules/ declares no
# provider block at all, so the region, the credentials and the default tags
# are decisions of this directory — which is what lets one module build three
# environments.
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "linkforge"
      Environment = "stage"
      ManagedBy   = "terraform"
      Milestone   = "v1-network"
    }
  }
}
