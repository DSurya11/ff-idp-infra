# =============================================================================
# 10-network/main.tf
#
# Network layer — VPC, subnets, security groups.
# Uses the local modules/vpc module.
#
# COST: $0 — VPC, subnets, route tables, IGW, and security groups are free.
# LIFECYCLE: Keep up permanently. Destroying costs nothing and requires
#   rebuilding 20-data, 30-cluster, and 40-platform as well.
#
# NAT GATEWAY: NOT in this layer. NAT lives in 30-cluster so it is destroyed
# nightly with the cluster. This is the key cost decision:
#   NAT Gateway = $0.056/hr = $1.34/day = $40/month if left running.
#   By putting it in 30-cluster, NAT is only alive during active sessions.
# =============================================================================

terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket  = "ff-idp-tfstate-693906847772"
    key     = "10-network/terraform.tfstate"
    region  = "ap-south-1"
    profile = "ff-idp"
  }
}

provider "aws" {
  region  = "ap-south-1"
  profile = "ff-idp"

  default_tags {
    tags = {
      Project     = "ff-idp"
      ManagedBy   = "terraform"
      Environment = var.environment
      Layer       = "10-network"
    }
  }
}

module "vpc" {
  source = "../modules/vpc"

  name         = "ff-idp"
  cluster_name = "ff-idp-cluster"

  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["ap-south-1a", "ap-south-1b"]

  # Public subnets — ALB, NAT Gateway EIP attachment
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]

  # Private subnets — EKS nodes, RDS, ElastiCache
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
}
