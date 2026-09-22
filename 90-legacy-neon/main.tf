# =============================================================================
# 90-legacy-neon/main.tf
#
# Manages the existing Neon PostgreSQL project.
# Migrated from /home/surya/projects/feature flag service/terraform/
# during Step 19 of the IDP project.
#
# PURPOSE: Kept alive for the Neon vs. RDS latency A/B experiment (Step 21).
# DO NOT DESTROY until the experiment is complete and results are documented.
#
# MIGRATION NOTE: State was migrated from local (app repo) to S3 using:
#   terraform init -migrate-state
# After migration, `terraform plan` must show "No changes."
# =============================================================================

terraform {
  required_version = ">= 1.9"

  required_providers {
    neon = {
      source  = "kislerdm/neon"
      version = "0.18.0"
    }
  }

  backend "s3" {
    bucket  = "ff-idp-tfstate-693906847772"
    key     = "90-legacy-neon/terraform.tfstate"
    region  = "ap-south-1"
    profile = "ff-idp"
  }
}

provider "neon" {
  api_key = var.neon_api_key
}

resource "neon_project" "this" {
  name                      = "Feature flag service-tf-managed"
  history_retention_seconds = 21600
}
