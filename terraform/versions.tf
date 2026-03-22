provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}

terraform {
  required_version = ">= 1.14.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.37"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.8"
    }
  }
}