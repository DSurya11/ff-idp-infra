# idp-infra — Internal Developer Platform infrastructure

All AWS infrastructure for the IDP (EKS, data, networking, Argo CD bootstrap), managed with Terraform.
Everything that runs on the cluster is deployed by Argo CD from [idp-gitops](https://github.com/surya-idp/idp-gitops).

## Layer Architecture

| Layer | Directory | State | Lifecycle |
|---|---|---|---|
| Bootstrap | `00-bootstrap/` | **LOCAL** | Permanent: state bucket, GitHub OIDC, CI roles |
| Network | `10-network/` | S3 | Permanent (\$0): VPC, subnets, security groups |
| Registry | `15-registry/` | S3 | Permanent: ECR repositories |
| Data | `20-data/` | S3 | Created by `make up`, destroyed by `make down`: RDS, Secrets Manager |
| Cluster | `30-cluster/` | S3 | Created/destroyed each session: EKS, NAT, Valkey, IRSA |
| Platform | `40-platform/` | S3 | Created/destroyed each session: ALB controller, ESO, Argo CD |

All S3 backends use state locking (`use_lockfile = true`).

## Prerequisites

```bash
# Terraform (Fedora)
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
sudo dnf install -y terraform
terraform version

# AWS CLI profile
aws sts get-caller-identity --profile idp
# Must show: arn:aws:iam::693906847772:user/idp-admin
```

## Session Lifecycle

```bash
make up            # ~21-27 min: 20-data -> 30-cluster -> 40-platform; Argo CD deploys the rest
make down          # ~16 min: removes the ALB, destroys 40 -> 30 -> 20, then verifies; must exit 0
make verify-empty  # confirm nothing billable is running
```

## Cost Model

- **Between sessions:** \$0.00 (everything billable is destroyed; ECR storage ~\$0.10/GB-month)
- **While up:** ~\$0.26/hr, ~\$0.80 per 3-hour session (EKS, 2x t4g.small, NAT, ALB, RDS, Valkey)

See HANDOVER_DOC.md for the full price breakdown (verified via the AWS Pricing API).
