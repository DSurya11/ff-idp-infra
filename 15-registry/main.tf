# =============================================================================
# 15-registry/main.tf
#
# Container registry - kept up PERMANENTLY (never part of make down).
#
# WHY A SEPARATE LAYER: ECR used to live in 30-cluster, which is destroyed every
# session. That either blocked destroy (repo not empty) or, with force_delete,
# wiped every image so each make up needed a fresh CI run before pods could pull.
# The registry is nearly free (empty = $0, ~1GB = ~$0.10/month), so it stays.
#
# IMMUTABLE tags prevent overwriting a pushed image SHA - critical for GitOps.
# scan_on_push: vulnerability scan runs automatically on every push.
# Lifecycle: keep last 20 images (~4GB worst case = ~$0.40/month).
#
# CI role (00-bootstrap) is scoped by repository ARN, so it needs no change.
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
    key     = "15-registry/terraform.tfstate"
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
      Environment = "shared"
      Layer       = "15-registry"
    }
  }
}

resource "aws_ecr_repository" "feature_flag_service" {
  name                 = "feature-flag-service"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "feature-flag-service"
  }
}

resource "aws_ecr_lifecycle_policy" "feature_flag_service" {
  repository = aws_ecr_repository.feature_flag_service.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 20 images - expire older ones"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 20
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

output "ecr_repository_url" {
  description = "Full ECR URL for the feature-flag-service image (without tag)"
  value       = aws_ecr_repository.feature_flag_service.repository_url
}
