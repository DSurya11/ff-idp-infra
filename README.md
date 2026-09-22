# ff-idp-infra — Feature Flag IDP Infrastructure

All AWS infrastructure for the Feature Flag IDP project, managed with Terraform.

## Layer Architecture

| Layer | Directory | State | Destroy between sessions? |
|---|---|---|---|
| Bootstrap | `00-bootstrap/` | **LOCAL** | NEVER |
| Network | `10-network/` | S3 | No (\$0 cost) |
| Data | `20-data/` | S3 | No (stop instances, keep storage) |
| Cluster | `30-cluster/` | S3 | **YES** (EKS = \$0.10/hr) |
| Platform | `40-platform/` | S3 | **YES** (goes with cluster) |
| Legacy Neon | `90-legacy-neon/` | S3 | NEVER (needed for A/B test) |

## Prerequisites

```bash
# Terraform (Fedora)
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
sudo dnf install -y terraform
terraform version

# AWS CLI profile
aws sts get-caller-identity --profile ff-idp
# Must show: arn:aws:iam::693906847772:user/ff-idp-admin
```

## Session Lifecycle

```bash
make up    # Start data instances + apply cluster + platform layers
make down  # Destroy cluster + platform, stop (not destroy) data instances
make verify-empty  # Confirm no billable resources running
```

## Cost Model

- **Between sessions:** ~\$3.62/month (RDS + ElastiCache storage only)
- **Per 3-hr session:** ~\$0.69 (EKS + SPOT nodes + NAT + ALB)
- **Monthly (12 sessions):** ~\$15

See handover document for full price breakdown verified via AWS Pricing API.
