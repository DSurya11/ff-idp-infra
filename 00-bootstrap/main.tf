# =============================================================================
# 00-bootstrap/main.tf
#
# Creates the foundation for all other Terraform layers:
#   1. S3 bucket for remote state (all layers 10-90 use this)
#   2. DynamoDB table for state locking (optional but good portfolio practice)
#   3. GitHub OIDC Identity Provider (enables keyless CI auth)
#   4. IAM role ff-idp-github-ci (assumed by GitHub Actions via OIDC)
#
# STATE: LOCAL — intentional chicken-and-egg.
#   This layer creates the S3 bucket that all other layers use as their backend.
#   It cannot itself use that bucket as a backend because the bucket doesn't
#   exist yet. Local state is the correct approach here.
#
#   DO NOT run `terraform destroy` on this layer.
#   DO NOT migrate this layer's state to S3 — it would create a circular
#   dependency where destroying the bucket destroys the state that tracked it.
#
# COST: $0 — IAM, OIDC provider, and S3 bucket (no objects yet) are free.
# =============================================================================

terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # LOCAL STATE — do not add a backend block here.
  # See comment above explaining why this is intentional.
}

provider "aws" {
  region  = "ap-south-1"
  profile = "ff-idp"

  default_tags {
    tags = {
      Project     = "ff-idp"
      ManagedBy   = "terraform"
      Environment = "bootstrap"
      Layer       = "00-bootstrap"
    }
  }
}

# ─── Data sources ────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

# Fetch the current TLS certificate for the GitHub Actions OIDC endpoint.
# This derives the thumbprint dynamically rather than hardcoding it.
# Hardcoded thumbprints go stale when GitHub rotates their certificate.
data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

# ─── S3 state bucket ─────────────────────────────────────────────────────────

resource "aws_s3_bucket" "tfstate" {
  bucket = "ff-idp-tfstate-${data.aws_caller_identity.current.account_id}"

  # Prevent accidental destruction of the state bucket.
  # If you genuinely need to destroy it, remove this block first,
  # then run `terraform apply` to update, then `terraform destroy`.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Block all object ownership changes — no ACLs
resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ─── DynamoDB state lock table ───────────────────────────────────────────────
# Note: Terraform >= 1.10 supports native S3 locking (use_lockfile = true),
# making DynamoDB optional. We create it anyway for compatibility with older
# Terraform versions and as an explicit portfolio demonstration.

resource "aws_dynamodb_table" "tfstate_locks" {
  name         = "ff-idp-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# ─── GitHub Actions OIDC Identity Provider ───────────────────────────────────
# This tells AWS to trust JWTs issued by GitHub Actions.
# The thumbprint is fetched dynamically from GitHub's current TLS cert.

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # AWS occasionally updates required thumbprints. These are the current ones + the dynamic one.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
    data.tls_certificate.github_actions.certificates[0].sha1_fingerprint
  ]
}

# ─── IAM role: ff-idp-github-ci ──────────────────────────────────────────────
# Assumed by GitHub Actions workflows in the Feature-Flag-Service repo,
# main branch only. The condition is intentionally strict — no wildcards.
#
# SECURITY: The sub condition pins to a specific repo AND branch.
#   repo:DSurya11@162597218/Feature-Flag-Service@1368152185:ref:refs/heads/main
#   Any other repo or branch cannot assume this role.
#   Never use repo:*:* — that would allow any GitHub Action in any repo
#   belonging to the GitHub OIDC provider to assume this role.

data "aws_iam_policy_document" "github_ci_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      # Exact repo + exact branch. No wildcards.
      # GitHub's OIDC sub claim now embeds immutable owner and repo IDs
      # (repo:OWNER@OWNER_ID/REPO@REPO_ID:...). The old "repo:OWNER/REPO:..." form no longer
      # matches, which shows up as "Not authorized to perform sts:AssumeRoleWithWebIdentity".
      # IDs: DSurya11 = 162597218, Feature-Flag-Service = 1368152185.
      values = ["repo:DSurya11@162597218/Feature-Flag-Service@1368152185:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_ci" {
  name               = "ff-idp-github-ci"
  assume_role_policy = data.aws_iam_policy_document.github_ci_trust.json
  description        = "Assumed by GitHub Actions CI for Feature-Flag-Service (main branch only)"
}

# ECR permissions — scoped to the specific repository.
# The ECR repo doesn't exist yet (created in 30-cluster); we use a predictable
# ARN pattern. GetAuthorizationToken is account-level, not repo-scoped.
data "aws_iam_policy_document" "github_ci_ecr" {
  # GetAuthorizationToken is account-level — cannot be scoped to a specific repo
  statement {
    sid     = "ECRAuth"
    effect  = "Allow"
    actions = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # All other ECR actions can be scoped to the specific repository
  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [
      "arn:aws:ecr:ap-south-1:${data.aws_caller_identity.current.account_id}:repository/feature-flag-service",
    ]
  }
}

resource "aws_iam_role_policy" "github_ci_ecr" {
  name   = "ecr-push"
  role   = aws_iam_role.github_ci.id
  policy = data.aws_iam_policy_document.github_ci_ecr.json
}
