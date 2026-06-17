terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Default provider (us-east-1) for Route 53 + SNS
provider "aws" {
  region = "us-east-1"
}

# DR region provider alias — needed by S3 replication module
provider "aws" {
  alias  = "dr"
  region = "us-west-2"
}
