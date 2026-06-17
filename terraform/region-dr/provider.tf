terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment after creating S3 bucket for state
  # backend "s3" {
  #   bucket = "chaos-dr-tfstate"
  #   key    = "dr/terraform.tfstate"
  #   region = "us-east-1"   # state bucket always in primary
  # }
}

provider "aws" {
  region = var.aws_region
}
