---
# Feature Flag IDP — Master Handover Document
> Last updated: 2026-09-26 (Session 5)
> Purpose: Self-contained context for any AI/agent to continue this project from any point.
> Nothing should need to be re-verified or re-asked if this document is read first.

---

## 1. Account & Environment Facts (Verified, Not Assumed)

| Key | Value |
|---|---|
| AWS Account ID | `693906847772` |
| AWS Account Name | D S S V Raju |
| IAM User | `ff-idp-admin` |
| IAM User ARN | `arn:aws:iam::693906847772:user/ff-idp-admin` |
| AWS CLI Profile | `ff-idp` |
| AWS CLI Version | `aws-cli/2.36.49` |
| Default Region | `ap-south-1` (Mumbai) |
| Credit Balance | ~$200 USD |
| Credit Expiry | March 21, 2027 (181 days from 2026-09-21) |
| Free Tier Type | Credit-based (account created after July 15, 2025) |
| Free Tier Reality | NO traditional 750hr/month free tier. ALL costs come from $200 credits. |
| OS | Fedora Linux (Fedora 44) |
| GitHub User | `DSurya11` |
| Local projects path | `/home/surya/projects/` |
| Terraform | v1.16.3 (installed via HashiCorp dnf repo) |

**Verify identity before any session:**
```bash
aws sts get-caller-identity --profile ff-idp
# Must show: Account: 693906847772, Arn: arn:aws:iam::693906847772:user/ff-idp-admin
# NEVER operate as root
```

---

## 2. Verified Prices — ap-south-1 (Mumbai)
> Verified 2026-09-21 via `aws pricing get-products` API.

| Service | Rate | Unit | Notes |
|---|---|---|---|
| EKS control plane | $0.10 | /hr | Always charged when cluster exists |
| EC2 t4g.small On-Demand | $0.0168 | /hr | **Chosen** — ARM Graviton, free-tier eligible |
| EC2 t3.medium SPOT | $0.0147–$0.0197 | /hr | **Blocked** by account-level free-tier restrictions |
| NAT Gateway | $0.056 | /hr | + $0.056/GB processed |
| ALB | $0.0239 | /hr | + $0.008/LCU-hr |
| RDS db.t3.micro PostgreSQL | $0.017 | /hr | **Chosen** — On-demand, t4g had no capacity |
| RDS gp2 storage | $0.114 | /GB-month | **Chosen** — gp3 had no capacity for micro DBs |
| RDS final snapshot | $0.131 | /GB-month | ACCUMULATES with each destroy — use skip_final_snapshot=true |
| ElastiCache cache.t4g.micro Valkey | $0.016 | /hr | Use Valkey not Redis — same API, 20% cheaper |
| Secrets Manager | $0.40 | /secret/month | + $0.05/10k API calls |
| ECR | $0.10 | /GB-month | Storage only |
| S3 Standard | $0.025 | /GB-month | Verified: tfstate is ~34KB = $0.00000078/mo |
| DynamoDB | ~$0 | | First 25GB free. tf-locks is PAY_PER_REQUEST ($0 idle) |
| EBS gp3 | $0.0912 | /GB-month | Node root volumes |
| Public IPv4 | $0.005 | /hr | Per IP, in-use OR idle |
| CloudWatch Logs ingestion | $0.50–$0.67 | /GB | EXPENSIVE — minimize aggressively |
| CloudWatch Logs storage | $0.03 | /GB-month | |

---

## 3. Cost Model

### CHOSEN: Option B — Full Destroy Every Session ($0.00 Idle)

User chose Option B on 2026-09-22 after full explanation of tradeoffs:
- Option A: $4.22/month idle (RDS stopped storage + Secrets Manager)
- Option B: $0.00/month idle (full destroy — nothing runs between sessions)

Option B was chosen because ElastiCache has NO stop API (discovered in Step 21), and the
only way to stop paying for it is to destroy it. Once destruction is required anyway, full
destroy of all layers costs nothing extra and is simpler to reason about.

**CRITICAL: skip_final_snapshot = true on RDS**
With Option B (full destroy each session), false = 12 × 20GB × $0.131 = $31.44/month in
orphaned snapshots. Must be true. Set and verified in 20-data/main.tf.

### Per 3-Hour Session (cluster up)
| Component | Calculation | Cost |
|---|---|---|
| EKS control plane | 3hr × $0.10 | $0.30 |
| EC2 t4g.small ×2 | 2 × 3hr × $0.0168 | $0.10 |
| NAT Gateway | 3hr × $0.056 | $0.17 |
| ALB | 3hr × $0.0239 | $0.07 |
| Public IPv4 (~3 IPs) | 3 × 3hr × $0.005 | $0.05 |
| EBS (negligible) | | ~$0.01 |
| RDS (~1hr creation) | 1hr × $0.017 | $0.02 |
| Secrets Manager (4 secrets, proration) | | ~$0.01 |
| **Session total** | | **~$0.73** |

### Monthly (12 sessions/month, 3hr each)
| Component | Monthly |
|---|---|
| Sessions (12 × $0.73) | $8.76 |
| Between sessions | $0.00 (Option B — everything destroyed) |
| ECR (~1GB, kept between sessions) | $0.10 |
| S3 + DynamoDB (state) | ~$0.01 |
| **Monthly total** | **~$8.87** |

### Project Total
- 6 months × $8.87 = ~$53 total
- Credits remaining after project: ~$147
- Verdict: Very comfortable. No need to cut scope.

---

## 4. Cost Rules (Non-Negotiable)

1. **`make down` before closing the laptop. VERIFY with `make verify-empty`.** Must show OK: $0.00.

2. **CloudWatch log retention = 1 day.** Set everywhere. Default 90-day at $0.50/GB is a silent credit drain.

3. **Option B lifecycle: DESTROY all layers (20-data, 30-cluster, 40-platform) in make down.**
   ElastiCache has NO stop API — the only way to not pay for it is to destroy it.
   RDS also destroyed (not stopped) — simpler, cheaper under Option B.

4. **Tag EVERY resource with `Project=ff-idp`.** Via Terraform `default_tags`. Untagged orphans = surprise bills.

5. **Budget alerts confirmed in place:**
   - `My Zero-Spend Budget`: $1/month alert
   - `Total-180-of-200-Alert`: $180 cumulative over project lifetime

6. **Valkey, not Redis.** `engine = "valkey"` in ElastiCache Terraform. Same API, 20% cheaper.

7. **No paid domain.** Use ALB DNS name directly. Document as "production would use ACM + Route53; deferred."

8. **skip_final_snapshot = true on ALL RDS instances.** With Option B, false = $31/month snapshots.

---

## 5. Repository State (as of 2026-09-24)

### All Repos
| Repo | Local Path | URL | Status |
|---|---|---|---|
| `Feature-Flag-Service` | `/home/surya/projects/feature flag service/` | https://github.com/DSurya11/Feature-Flag-Service | ✅ Steps 1–22 complete |
| `feature-flag-service-env-config` | `/home/surya/projects/feature-flag-service-env-config/` | https://github.com/DSurya11/feature-flag-service-env-config | ⚠️ Flat — restructure in Step 27 |
| `idp-portal` | `/home/surya/projects/idp-portal/` | Local only | ⚠️ Scaffold only, SQLite, no CI |
| `ff-idp-infra` | `/home/surya/projects/ff-idp-infra/` | https://github.com/DSurya11/ff-idp-infra | 🚧 Step 25 in progress (ALB ingress verification) |

Note: `/home/surya/projects/feature flag service/` — path has a SPACE. Always quote it.

### env-config Current State (Flat — Restructure in Step 27)
```
feature-flag-service-env-config/
  api-deployment.yaml          ← image SHA auto-updated by CI
  api-service.yaml
  kyverno-policy-disallow-root.yaml
  namespace.yaml
  redis-deployment.yaml
  redis-service.yaml
  secret-template.yaml.example ← safe (renamed, not parsed by Argo CD)
  servicemonitor.yaml
```

### idp-portal Current State (Unchanged from original)
- Scaffolded: `npx @backstage/create-app@latest`
- Auth: `guest: {}` (no real provider)
- DB: SQLite in-memory (dev config)
- GitHub integration: PAT via `GITHUB_TOKEN` env var
- Catalog: points at Feature-Flag-Service catalog-info.yaml
- Templates: none written. TechDocs: local builder + local publisher
- Not containerized. Not pushed to cluster. No CI.

### ff-idp-infra Local Changes (2026-09-24 - uncommitted)
- `20-data/main.tf`: Switched RDS from `db.t4g.micro` + `gp3` to `db.t3.micro` + `gp2` due to AWS capacity limits.
- `30-cluster/main.tf`: Created cluster layout. Switched EKS node group from SPOT `t3.medium` to ON_DEMAND `t4g.small` (AL2023_ARM_64_STANDARD) due to strict Free-Tier Spot limitations. Updated ALB IAM policy URL to v2.11.0.
- `00-bootstrap/main.tf`: Added well-known AWS thumbprints to GitHub OIDC provider to prevent STS rejection.
- `scripts/verify-empty.py`: Enhanced logic to filter out false positives (NAT gateways in "deleted" state, KMS keys in "PendingDeletion") and explicitly print free resources as INFO.
- `test_latency.py`: Added script to verify latency A/B test (unauthenticated /health and authenticated /api/v1/flags via ALB).

### Feature-Flag-Service Commits (CI-related, 2026-09-22)
| Commit | Message |
|---|---|
| 907c464 | feat(ci): rewrite CI for ECR/OIDC + GitHub App + Trivy (Step 22) |
| c26d7d4 | ci: fix EKS exec format error by building arm64 images | feat(ci): rewrite CI for ECR/OIDC + GitHub App + Trivy (Step 22) |

---

## 6. What Is Done — Steps 1–23

### Application Layer (Steps 1–9) ✅ All Complete
| Step | What | Key files |
|---|---|---|
| 1 | DB schema: `flags`, `targeting_rules`, `audit_log` (CASCADE/SET NULL) | `alembic/` |
| 2 | `/health` (503 on DB down) + fail-fast startup check | `app/main.py`, `app/routers/health.py` |
| 3 | JWT auth + bcrypt, admin role | `app/auth.py`, `app/dependencies.py` |
| 4 | Flag CRUD + audit logging | `app/routers/flags.py` |
| 5 | `/evaluate`: fail-safe, percentage hash, targeting rules | `app/evaluation.py`, `app/routers/evaluate.py` |
| 6 | Redis caching (shared across replicas, ~0.6ms) | `app/cache.py` |
| 7 | `docker-compose.yml` (local full-stack) | `docker-compose.yml` |
| 8 | Multi-stage Dockerfile (non-root appuser UID 999, HEALTHCHECK) | `Dockerfile` |
| 9 | GitHub Actions CI: test → build → push to GHCR (SHA + latest) | `.github/workflows/ci.yml` (rewritten in Step 22) |

### Platform Layer (Steps 10–16) ✅ All Complete
| Step | What | Key files |
|---|---|---|
| 10 | kind cluster, 2-replica deployment, liveness/readiness probes | `feature-flag-service-env-config/api-deployment.yaml` |
| 11 | Terraform manages Neon (local state, `kislerdm/neon` v0.18.0) | `terraform/main.tf` |
| 12 | App/env-config split; CI auto-updates image SHA via sed + PAT | `ci.yml` lines 261–272 |
| 13 | Argo CD (automated sync, selfHeal, prune); secret-template trap found+fixed | `argocd/application.yaml` |
| 14 | Backstage catalog: Component + 2 Resources | `catalog-info.yaml` |
| 15 | Kyverno `disallow-root-containers` (Enforce) | `kyverno-policy-disallow-root.yaml` |
| 16 | Prometheus + Grafana, ServiceMonitor, 4 custom metrics, latency investigation | `app/metrics.py` |

### Key Findings From Steps 1-16 (Already in README)
1. p95 latency ~0.97s. Redis ~0.6ms. Postgres fetch ~780ms every request.
2. CrashLoopBackOff vs readiness failure — fail-fast startup bypasses probes.
3. Secret-template GitOps trap — Argo CD picks up any `kind: Secret` in watched path.
4. Kyverno optional-match `=(field)` bug — policy looked fine but enforced nothing.
5. CRD size limit → `kubectl apply --server-side`.
6. Argo CD selfHeal fighting manual `kubectl apply`.
7. conntrack stickiness on sequential in-cluster requests (not yet in README — add in Section 14).

### Infrastructure Phase (Steps 17–23) 🚧 IN PROGRESS

#### Step 17 — AWS Account Hygiene ✅
- IAM user ff-idp-admin confirmed (NEVER root)
- Budget alerts confirmed:
  - `My Zero-Spend Budget`: $1/month threshold
  - `Total-180-of-200-Alert`: $180 cumulative
- AWS CLI profile ff-idp working
- Verified: `aws sts get-caller-identity --profile ff-idp` → Account 693906847772

#### Step 18 — Terraform Bootstrap (00-bootstrap) ✅
Applied 2026-09-22. Resources: 9 created. State: LOCAL (intentional).

Resources created:
- **S3 bucket** `ff-idp-tfstate-693906847772`: versioning=Enabled, SSE=AES256, all public access blocked
- **DynamoDB table** `ff-idp-tf-locks`: PAY_PER_REQUEST, hash key LockID
- **GitHub OIDC Provider**: thumbprint fetched dynamically via `tls_certificate` data source (NOT hardcoded — survives GitHub cert rotation)
- **IAM Role** `ff-idp-github-ci`:
  - Trust: StringEquals `token.actions.githubusercontent.com:sub` = `repo:DSurya11/Feature-Flag-Service:ref:refs/heads/main`
  - Trust: StringEquals `token.actions.githubusercontent.com:aud` = `sts.amazonaws.com`
  - No wildcards anywhere
  - Inline policy: `GetAuthorizationToken` on `*` (AWS requirement — account-level), all other ECR actions scoped to `arn:aws:ecr:ap-south-1:693906847772:repository/feature-flag-service`

#### Step 19 — Neon State Migration (90-legacy-neon) ✅
Applied 2026-09-22. State migrated from local to S3. Neon project untouched.

#### Step 20 — Network Layer (10-network) ✅
Applied 2026-09-22. Resources: 17 created. Cost: $0/month permanently.
- VPC, 4 subnets (ap-south-1a/b), IGW, route tables, and SGs created permanently ($0/month).

#### Step 21 — Data Layer (20-data) ✅ (Revised Session 3)
Applied and destroyed 2026-09-22. Option B lifecycle: full destroy each session.
- ElastiCache moved to `30-cluster` to allow nightly destruction.
- **Session 3 Fix:** Switched to `db.t3.micro` and `gp2` storage type due to an active AWS capacity shortage for Graviton (`t4g`) databases with `gp3` in Mumbai (`ap-south-1`).

#### Step 22 — CI Rewrite ✅
Committed and pushed 2026-09-22. Commit: 907c464 to Feature-Flag-Service repo.
- CI refactored to use GitHub App for env-config updates, ECR registry, and strictly OIDC auth (no static credentials).

#### Step 23 — EKS Cluster Layer (30-cluster) 🚧 IN PROGRESS
- `main.tf` written utilizing `terraform-aws-modules/eks/aws ~> 20.0` (Avoided v21 due to known `var.partition` planning freeze bug).
- **Session 3 Blockers Overcome:**
  - Account strictly blocks non-Free-Tier instance types (like `t3.medium`) from running as SPOT. 
  - Node group configuration altered to `t4g.small` (ARM Graviton) using `ON_DEMAND` capacity.
  - Required specifying `ami_type = "AL2023_ARM_64_STANDARD"` because EKS rejects mismatched architectures.
- Current Status: Terraform state forcefully cleaned of failed spot requests. `make down` successfully wiped AWS to $0.00. Ready for a clean `make up`.

---

## 7. Terraform Layer Architecture (ff-idp-infra) — CURRENT STATE

```
ff-idp-infra/
  00-bootstrap/     S3 state bucket, DynamoDB lock, GitHub OIDC provider,
  │                 IAM role for CI. Uses LOCAL state (chicken-and-egg).
  │                 NEVER DESTROYED.
  │
  10-network/       VPC 10.0.0.0/16, 2 AZs (ap-south-1a + ap-south-1b),
  │                 public + private subnets, IGW, route tables, SGs.
  │                 NAT Gateway NOT here — it is in layer 30 (destroyed each session).
  │                 Backend: S3.  KEEP UP (costs $0).
  │
  20-data/          RDS db.t3.micro PostgreSQL 16, Secrets Manager x4.
  │                 NO ElastiCache here — moved to 30-cluster (no stop API).
  │                 Backend: S3.
  │                 DESTROYED each session (Option B).
  │
  15-registry/      ECR repo + lifecycle policy. PERMANENT (not in make up/down). Apply once by hand:
  │                 terraform -chdir=15-registry init && terraform -chdir=15-registry apply
  │
  30-cluster/       EKS cluster, managed node group (ON_DEMAND t4g.small), NAT Gateway, IRSA roles,
  │                 ECR repos, ElastiCache Valkey.
  │                 Backend: S3.
  │                 DESTROYED each session (most expensive layer).
  │                 WRITTEN (Steps 23/24/25 infra). Prefix delegation + force_delete added Session 5.
  │
  40-platform/      Argo CD + External Secrets Operator Helm releases. Everything else installed BY Argo CD.
  │                 Backend: S3.
  │                 DESTROYED each session (goes with layer 30).
  │                 WRITTEN.
  │
  90-legacy-neon/   Neon Terraform migrated from app repo.
                    NEVER destroy until A/B latency experiment is complete.
                    Backend: S3.
  
  modules/
    vpc/            VPC, subnets, IGW, route tables, 4 SGs
    eks/            NOT YET WRITTEN
    rds/            NOT YET WRITTEN
    irsa-role/      NOT YET WRITTEN
  
  scripts/
    verify-empty.py  Billable resource checker for make verify-empty
  
  Makefile          make up / make down / make verify-empty / make neon-plan
  .gitignore
  README.md
```

### Backend Config (per layer, all except 00-bootstrap)
```hcl
terraform {
  backend "s3" {
    bucket         = "ff-idp-tfstate-693906847772"
    key            = "XX-layername/terraform.tfstate"
    region         = "ap-south-1"
    profile        = "ff-idp"
    dynamodb_table = "ff-idp-tf-locks"
  }
}
```

### Terraform Default Tags (EVERY resource)
```hcl
provider "aws" {
  region  = "ap-south-1"
  profile = "ff-idp"
  default_tags {
    tags = {
      Project     = "ff-idp"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}
```

---

## 8. Session Lifecycle Commands (Option B — Full Destroy)

### make up (session start, ~20-27 minutes total)
```bash
cd /home/surya/projects/ff-idp-infra
make up
```

What it does (in order):
```
[1/4] terraform init -input=false + apply -auto-approve 20-data    (~5-7 min)
      Creates: fresh RDS (empty DB), 4 Secrets Manager secrets with placeholders
      Note: new auto-generated 32-char DB password each session

[2/4] terraform init -input=false + apply -auto-approve 30-cluster  (~12-15 min)
      Creates: EKS cluster, NAT Gateway, ElastiCache Valkey, ECR repos, IRSA roles

[3/4] aws eks update-kubeconfig --name ff-idp-cluster --region ap-south-1 --profile ff-idp

[4/4] terraform init -input=false + apply -auto-approve 40-platform (~3-5 min)
      Creates: Argo CD
      Waits: kubectl wait --for=condition=Healthy application/root -n argocd --timeout=300s
```

**AFTER make up completes — MANUALLY update ff-idp/jwt-secret:**
```bash
# The JWT secret defaults to placeholder "REPLACE_ME_before_first_cluster_up"
# Before the app can auth any user, update it:
aws secretsmanager put-secret-value \
  --secret-id ff-idp/jwt-secret \
  --secret-string '{"secret":"your-real-jwt-secret-here"}' \
  --profile ff-idp
```

### make down (session end — ALWAYS run before closing laptop)
```bash
cd /home/surya/projects/ff-idp-infra
make down
```

What it does (in order):
```
[1/3] terraform destroy -auto-approve 40-platform     (Argo CD, ESO)
[2/3] terraform destroy -auto-approve 30-cluster      (EKS, NAT, Valkey, ECR)
[3/3] terraform destroy -auto-approve 20-data         (RDS ~5 min, Secrets instant)
      Then: make verify-empty → MUST show OK: $0.00
```

What is permanently lost:
- All feature flags, users, JWT secrets, audit logs in RDS
- All 4 Secrets Manager secrets
- All K8s workloads, configs, deployments
- Valkey cache contents

What survives:
- VPC, subnets, SGs, IGW, route tables (free — kept permanently)
- S3 state bucket, DynamoDB lock table (bootstrap — kept permanently)
- IAM role, OIDC provider (bootstrap — kept permanently)
- Neon project (90-legacy-neon — kept permanently)
- All code in Git repos
- Terraform state files in S3
- ECR images (if kept — lifecycle policy retains last 20)

### make verify-empty (safety check — must pass before closing laptop)
```bash
cd /home/surya/projects/ff-idp-infra
make verify-empty
```

Runs `scripts/verify-empty.py` which:
1. Calls `aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=ff-idp`
2. Gets all ARNs with Project=ff-idp tag
3. Filters out free resource types.
4. *Script explicitly logs free/pending resources as an INFO block to ensure complete visibility without triggering a failure.*
5. Exit 0 + "OK: $0.00" if no billable resources remain
6. Exit 1 + list of billable ARNs if any remain

---

## 9. All Permanent AWS Resources (Live Right Now, Never Destroyed)

| Resource | ID / Name | Notes |
|---|---|---|
| S3 state bucket | ff-idp-tfstate-693906847772 | ~$0.00000078/mo |
| DynamoDB lock table | ff-idp-tf-locks | PAY_PER_REQUEST ($0 idle) |
| GitHub OIDC Provider | arn:aws:iam::693906847772:oidc-provider/token... | Free |
| IAM Role | ff-idp-github-ci | Free |
| VPC | vpc-0adcac5ff98908f3b (10.0.0.0/16) | Free |
| Public subnet ap-south-1a | subnet-0acd17491022c527e (10.0.1.0/24) | Free |
| Public subnet ap-south-1b | subnet-01c8679e5fd4bf485 (10.0.2.0/24) | Free |
| Private subnet ap-south-1a | subnet-038e07909e55745b9 (10.0.11.0/24) | Free |
| Private subnet ap-south-1b | subnet-0ffe3fe2c3c0167cd (10.0.12.0/24) | Free |
| Internet Gateway | igw-0497cc66bfde6497a | Free |
| Public Route Table | rtb-06be6c352335c4528 | Free |
| Private Route Table 1a | rtb-05a36c795c8121544 | Free |
| Private Route Table 1b | rtb-0a792e4f26cc2f99e | Free |
| SG: sg-nodes | sg-06abea709f3058525 | Free |
| SG: sg-rds | sg-0ef2f1b70cac77926 | Free |
| SG: sg-elasticache | sg-070a99d09310cf378 | Free |
| SG: sg-alb | sg-04b76d4484453aa8f | Free |
| Neon project | steep-resonance-33416603 | Baseline |

---

## 10. Ephemeral Resources (Destroyed Each Session, Recreated Each make up)

| Resource | Layer | Notes |
|---|---|---|
| RDS ff-idp-postgres | 20-data | db.t3.micro, PostgreSQL 16, 20GB gp2, private subnets |
| Secret ff-idp/db-creds | 20-data | Auto-generated 32-char password |
| Secret ff-idp/jwt-secret | 20-data | Placeholder — UPDATE MANUALLY each session |
| Secret ff-idp/grafana-admin | 20-data | Placeholder |
| Secret ff-idp/backstage-github-app | 20-data | Placeholder — populated Step 29 |
| ElastiCache ff-idp-valkey | 30-cluster | engine=valkey, cache.t4g.micro |
| EKS cluster ff-idp-cluster | 30-cluster | Created/destroyed each session |
| NAT Gateway | 30-cluster | Created/destroyed each session |
| ECR repo: feature-flag-service | 30-cluster | IMMUTABLE tags, scan on push, force_delete=true |
| Argo CD + ESO | 40-platform | Created/destroyed each session |

---

## 11. CI/CD State

### Current CI Workflow Structure (post-Step-22 rewrite)

```yaml
jobs:
  test:
    # Always runs (not just main branch)
    # Sets up Python, installs deps, runs pytest --tb=short -q
    
  build-and-push:
    needs: test
    if: github.ref == 'refs/heads/main'
    permissions:
      id-token: write   # OIDC — required
      contents: read
    steps:
      - aws-actions/configure-aws-credentials@v4
        # role: arn:aws:iam::693906847772:role/ff-idp-github-ci
        # region: ap-south-1
      - aws-actions/amazon-ecr-login@v2
      - docker build -t 693906847772.dkr.ecr.ap-south-1.amazonaws.com/feature-flag-service:${{ github.sha }} .
      - docker push ...:${{ github.sha }}    # SHA ONLY — no :latest
      - aquasecurity/trivy-action@0.28.0
        # exit-code: '1', severity: HIGH,CRITICAL, ignore-unfixed: true
    
  update-env-config:
    needs: build-and-push
    if: github.ref == 'refs/heads/main'
    steps:
      - actions/create-github-app-token@v1
        # app-id: ${{ secrets.FF_IDP_CI_BOT_APP_ID }}
        # private-key: ${{ secrets.FF_IDP_CI_BOT_PRIVATE_KEY }}
      - checkout feature-flag-service-env-config using token
      - # Dual-mode detection:
        if [ -f "apps/feature-flag-service/overlays/dev/kustomization.yaml" ]; then
          # Post-Step-27 Kustomize mode
          cd apps/feature-flag-service/overlays/dev && kustomize edit set image ...
        else
          # Current flat mode
          sed -i "s|image: .*feature-flag-service:.*|image: ...:${{ github.sha }}|" api-deployment.yaml
        fi
      - git commit + push
```

ECR image tag format: `693906847772.dkr.ecr.ap-south-1.amazonaws.com/feature-flag-service:<github-sha>`

### OIDC Trust Policy (must never change)
```json
{
  "StringEquals": {
    "token.actions.githubusercontent.com:sub": "repo:DSurya11/Feature-Flag-Service:ref:refs/heads/main",
    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
  }
}
```
Never use wildcards (`repo:*:*`). Any GitHub repo could assume the role.

### GitHub App (ff-idp-ci-bot)
- App ID: `5034584`
- Private key: `/home/surya/Downloads/ff-idp-ci-bot.2026-09-22.private-key.pem` (local only)
- Installed on: `feature-flag-service-env-config` repo only
- GitHub secrets on Feature-Flag-Service: `FF_IDP_CI_BOT_APP_ID`, `FF_IDP_CI_BOT_PRIVATE_KEY`

---

## 12. Key Terraform Snippets

### RDS (20-data/main.tf) — FIXED (Session 3)
```hcl
resource "random_password" "db" {
  length  = 32
  special = false  # avoid chars that break connection strings
  upper   = true
  lower   = true
  numeric = true
}

resource "aws_db_subnet_group" "postgres" {
  name       = "ff-idp-postgres"
  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
}

resource "aws_db_instance" "postgres" {
  identifier             = "ff-idp-postgres"
  engine                 = "postgres"
  engine_version         = "16"
  # t4g.micro + gp3 had NO CAPACITY in ap-south-1a/b. Switched to t3.micro + gp2.
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_type           = "gp2"
  db_name                = "feature_flags"
  username               = "ffidp"
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [data.terraform_remote_state.network.outputs.sg_rds_id]
  publicly_accessible    = false  # CRITICAL — never true
  skip_final_snapshot    = true   # CRITICAL for Option B — false = $31/month snapshots
  deletion_protection    = false
  backup_retention_period       = 0
  performance_insights_enabled  = false
  tags = { Name = "ff-idp-postgres" }
  lifecycle {
    ignore_changes = [final_snapshot_identifier]  # timestamp() re-evaluates every plan
  }
}
```

### EKS Node Group (30-cluster/main.tf) — FIXED (Session 3)
```hcl
  eks_managed_node_groups = {
    spot = {
      # Account restricts Spot to free-tier-eligible types only (t3.medium rejected).
      # Switched to t4g.small (Graviton, free-tier eligible) and ON_DEMAND.
      instance_types = ["t4g.small"]
      capacity_type  = "ON_DEMAND"
      
      # EKS rejects mismatched AMI architectures (cannot mix x86 and ARM). 
      # Must explicitly define ARM64 for t4g instances.
      ami_type       = "AL2023_ARM_64_STANDARD"

      min_size     = 2
      max_size     = 3
      desired_size = 2
    }
  }
```

### scripts/verify-empty.py — FIXED (Session 3)
```python
        # KMS keys are $0 while PendingDeletion
        if ":key/" in arn:
            free_or_pending.append(f"{arn} (Pending Deletion / Free)")
            continue
            
        # NAT Gateways in "deleted" state cost $0, but AWS Tagging API caches them for ~1 hour.
        # Must check the actual live state dynamically via ec2 describe-nat-gateways.
        if ":natgateway/" in arn:
            gw_id = arn.split("/")[-1]
            state_check = subprocess.run(["aws", "ec2", "describe-nat-gateways"...])
            if state_check.stdout.strip() == "deleted":
                free_or_pending.append(f"{arn} (Deleted state)")
                continue
```

---

## 13. Real-World Findings and Gotchas

### From Steps 1-16 (Already in README)
1. p95 latency ~0.97s — not sub-50ms. Root cause: Postgres fetch ~780ms every request.
2. CrashLoopBackOff vs readiness failure — fail-fast startup bypasses probes.
3. Secret-template GitOps trap — Argo CD picks up any `kind: Secret` in watched path.
4. Kyverno optional-match `=(field)` bug — policy enforced nothing silently.
5. CRD size limit → `kubectl apply --server-side`.
6. Argo CD selfHeal fighting manual `kubectl apply`.
7. conntrack stickiness on sequential in-cluster requests (not yet in README).

### From Steps 17-22 (New Findings 2026-09-22)

**Finding 1: AWS rejects em-dashes in ALL description/GroupDescription fields**
- APIs affected: EC2 `CreateSecurityGroup` (`GroupDescription`), ElastiCache `CreateReplicationGroup` (`description`)
- Error: `InvalidParameterValue: Character sets beyond ASCII are not supported` (EC2) or `non-printable control characters` (ElastiCache)
- Rule: Use ASCII hyphens (-) ONLY in ALL description fields in ALL Terraform resources
- This applies to EVERY future resource with a description field

**Finding 2: ElastiCache has NO stop API**
- `aws elasticache stop-replication-group` — does not exist (invalid choice)
- Unlike RDS which has `stop-db-instance` (pauses compute, keeps storage)
- ElastiCache options: running ($0.016/hr) OR destroyed. Nothing in between.
- Consequence: Must live in 30-cluster (destroyed nightly), cannot live in 20-data
- $0.016/hr × 24 × 30 = $11.52/month if kept in 20-data with no stop

**Finding 3: RDS final snapshots accumulate silently**
- With `skip_final_snapshot = false`, every `terraform destroy` creates a snapshot
- 12 destroys/month × 20GB × $0.131/GB-month = $31.44/month in orphaned snapshots
- Check RDS Snapshots in console and delete manually if any exist from accidents
- Solution: `skip_final_snapshot = true` in ALL lab/portfolio RDS configs

**Finding 4: timestamp() causes permanent Terraform drift**
- `timestamp()` re-evaluates on every `terraform plan` → shows change every time
- Fix: `lifecycle { ignore_changes = [field_that_uses_timestamp] }`

**Finding 5: Python heredoc in Makefile requires tab on EVERY line**
- Multi-line Python inside a Makefile heredoc must have tab (not spaces) on each line
- Nearly impossible to maintain correctly → moved to `scripts/verify-empty.py`

**Finding 6: Dynamic OIDC thumbprint is critical**
- Do NOT hardcode the GitHub Actions OIDC thumbprint
- Use `tls_certificate` data source to fetch at apply time
- GitHub rotates their cert periodically — hardcoded thumbprint will break

**Finding 7: RDS console visibility**
- RDS instances only appear in the AWS console region selector for the region they were created in
- Must be on `ap-south-1` (Asia Pacific Mumbai) in the console to see ff-idp-postgres
- After `terraform destroy 20-data`, the DB disappears — this is correct

### New Findings (Session 3 / Step 23)
**Finding 14: AWS Region Capacity Exhaustion:** `ap-south-1` completely ran out of `db.t4g.micro` and `gp3` combination capacity. Workaround applied: dropped back to x86 `db.t3.micro` and standard `gp2` storage.
**Finding 15: New-style Free Tier Spot Restrictions:** Recent AWS accounts aggressively block EC2 Spot instance requests for non-free-tier instance sizes (e.g., `t3.medium`). The API throws a misleading `InvalidParameterCombination` error. Workaround: Switch to `ON_DEMAND` or strictly use `t4g.small` / `t3.micro`.
**Finding 16: EKS Node Group Architecture Lock:** EKS Managed Node Groups strictly evaluate the underlying AMI architecture. If you request a Graviton (`t4g`) instance, you MUST explicitly override the default `ami_type` to `AL2023_ARM_64_STANDARD`. You cannot provide a fallback array mixing x86 and ARM sizes.
**Finding 17: AWS Tagging API Ghosting:** `aws resourcegroupstaggingapi` will confidently return ARNs for resources that cost $0 or are already destroyed. NAT Gateways linger for 1 hour after hitting the `"deleted"` state. KMS keys linger for the entirety of their mandatory 7-day `"PendingDeletion"` window. Scripts checking for billing leaks must query the active state (e.g., `describe-nat-gateways`), not just check for the ARN's existence.


### New Findings (Session 4 / Step 25)
**Finding 18: GitHub OIDC Thumbprint Drift:** The dynamic `tls_certificate` data source fetches the leaf certificate thumbprint, but AWS STS occasionally expects intermediate/root thumbprints, leading to `AssumeRoleWithWebIdentity` failures. Fix: Hardcode well-known AWS thumbprints alongside the dynamic one.
**Finding 19: CI Cross-Compilation Requirement (Exec Format Error):** EKS nodes (`t4g.small`) are ARM64, but GitHub Actions runner (`ubuntu-latest`) builds x86_64 images by default, causing `CrashLoopBackOff (exec format error)`. Fix: Updated CI to use `docker/setup-qemu-action` and `buildx` for `linux/arm64`.
**Finding 20: Missing Python Dependency Crash:** `20-data/main.tf` stored the DB URL as `postgresql+asyncpg://`, but the app uses synchronous SQLAlchemy (`create_engine`) with `psycopg2`. This caused a `ModuleNotFoundError: No module named 'asyncpg'` crash on startup. **FIXED Session 5** (uncommitted): `20-data/main.tf` now emits `postgresql+psycopg2://`.
**Finding 21: EKS t4g.small ENI Pod Limit Exhaustion:** `t4g.small` nodes have a default max-pods limit of 11. ArgoCD, ESO, ALB Controller, and CoreDNS completely filled both nodes, causing API pods to be stuck in `Pending` (`Too many pods`). **FIXED Session 5** (uncommitted, untested on a live cluster): vpc-cni addon `ENABLE_PREFIX_DELEGATION=true` + `before_compute`, and node group `cloudinit_pre_nodeadm` sets kubelet `maxPods: 110`. VERIFY after next `make up`: `kubectl get node -o jsonpath='{.items[*].status.allocatable.pods}'` should show 110.
**Finding 22: Out-of-band ALB blocks VPC Destruction:** ALBs created by the AWS Load Balancer Controller are not managed by Terraform. `make down` fails to destroy the VPC because the ALB is still attached to the subnets. **FIXED Session 5**: `scripts/down.sh` deletes Ingresses, then any leftover ALBs/target groups in the project VPC, before destroying layers.
**Finding 23: Non-empty ECR blocks make down:** `aws_ecr_repository` cannot be destroyed if it contains images. **FIXED Session 5**: `force_delete = true` on the ECR repo.

### New Findings (Session 5 - cost audit)
**Finding 24: Orphaned RDS final snapshot.** `ff-idp-postgres-final-2026-09-22` (20GB, ~$2.62/mo) was left by the first destroy, before `skip_final_snapshot=true`. `make verify-empty` reported OK because the Tagging API does not surface it. Deleted manually 2026-09-26.
**Finding 25: Tag-based verification is not enough.** Snapshots, controller-created ALBs, ENIs and PVC volumes are not reliably visible via `resourcegroupstaggingapi`. `verify-empty.py` now ALSO queries each service directly (EKS, EC2, NAT, EIP, ELB, RDS + snapshots, ElastiCache, EBS + snapshots, Secrets, VPC endpoints, ECR, CloudWatch logs).
**Finding 26: `|| true` hid failed destroys.** `make down` now runs `scripts/down.sh`, which continues through all layers but exits non-zero and lists what failed. Never close the laptop on a non-zero exit.
**Finding 28: GitHub OIDC `sub` claim now embeds immutable IDs.** CI failed with "Not authorized to perform sts:AssumeRoleWithWebIdentity" for days. CloudTrail (ap-south-1, `AssumeRoleWithWebIdentity`) showed the real subject: `repo:DSurya11@162597218/Feature-Flag-Service@1368152185:ref:refs/heads/main`. The old `repo:OWNER/REPO:...` form (and a hand-made wildcard) never matched. Fixed in `00-bootstrap` with the exact new subject, no wildcard. The live role had also drifted from Terraform (console edit) - Terraform now owns it again. Debug tip: read the principal in the failed CloudTrail event.
**Finding 29: ECR must not live in a destroyed layer.** It was in 30-cluster, so each `make down` either failed (non-empty repo) or, with force_delete, wiped all images. Moved to permanent layer `15-registry` (NOT part of make up/down; apply once). CI pushes there.
**Finding 30: ALB controller was never installed by any code.** Session 4 must have installed it by hand. Now a `helm_release` in 40-platform (chart 3.5.0, IAM policy v3.5.0). ESO must depend on it: the controller's mutating webhook covers ALL Services, so installing anything in parallel fails with "no endpoints available".
**Finding 31: Prefix delegation works.** `vpc-cni` addon with `ENABLE_PREFIX_DELEGATION` + `before_compute`, plus kubelet `maxPods: 110` via `cloudinit_pre_nodeadm`: both nodes report 110 allocatable pods (was 11).
**Finding 32: Trivy could not scan the pushed image.** buildx pushes without loading into the local daemon, and the image is arm64 on an amd64 runner. Fix: `TRIVY_USERNAME/PASSWORD` from `aws ecr get-login-password`, `TRIVY_PLATFORM=linux/arm64`, and `--provenance=false` on the build.
**Finding 33: The CI bot could not update env-config - FIXED 2026-09-26.** The `ff-idp-ci-bot` GitHub App existed but had 0 installations (`GET /app` showed `installations_count: 0`; token minting returned 404). Installed on `feature-flag-service-env-config` only; verified by an empty-commit CI run: all 3 jobs green and `ff-idp-ci-bot[bot]` committed the new SHA. Diagnostic that works: sign an app JWT with the private key and call `GET /app/installations` (never print the key).
**Finding 34: Fresh RDS has no schema; the app does not migrate itself.** AUTOMATED and VERIFIED LIVE 2026-09-26: `eks-db-migrate-job.yaml` in env-config is an Argo CD Sync-hook Job (`alembic upgrade head`) on sync-wave 1; the Deployment is wave 2; ExternalSecret/namespace wave 0. Evidence: job ran `initial_schema` and completed 13:12:39Z, API pods created 13:12:39-40Z (after), `/health` 200 and flag create/evaluate work with no manual alembic. A second sync re-ran the Job as a no-op (already at head) and did not restart the API pods. CI bumps the image in both `eks-api-deployment.yaml` and `eks-db-migrate-job.yaml`. Fallback by hand: `kubectl exec -n feature-flag-dev deploy/feature-flag-api -- sh -c "cd /app; alembic upgrade head"`.
**Finding 36: Tag API ghosts purged NAT gateways.** ~1h after deletion AWS purges a NAT gateway, but `resourcegroupstaggingapi` still lists its ARN and `describe-nat-gateways --nat-gateway-ids` fails with `NatGatewayNotFound`. `verify-empty.py` treated that as billable (false alarm, make down exited non-zero). Fixed: NotFound = free. The direct service checks were empty the whole time.
**Finding 37: An interrupted `make down` leaves billable resources.** A teardown that was cut off (session/process ended) left the NAT gateway, its EIP and RDS running (~$0.09/hr) while EKS and Valkey were already gone. `make down` is idempotent: just re-run it. After ANY interruption, run `make verify-empty` (or query EKS/NAT/RDS directly) before closing the laptop. Do not start `make down` and walk away from the session.
**Finding 35: Argo root app YAML bug.** `syncOptions` must be under `spec.syncPolicy`, not `spec`. Root app is manual-sync and scoped by `directory.include` to the EKS manifests until Step 27.
**Finding 38: Argo CD v2.13 vs Kubernetes 1.35 schema skew.** With `ServerSideApply=true`, Argo's structured-merge diff fails on the live Deployment: `.status.terminatingReplicas: field not declared in schema` (field added in k8s 1.33). Sync status goes `Unknown` and auto-sync silently stops; the FIRST sync works (nothing live to diff), so it only shows on the second deploy. Workaround: no ServerSideApply on `feature-flag-dev`. Real fix (TODO): upgrade the Argo CD chart (7.7.3 = v2.13, tested only to k8s ~1.31) to a release that supports 1.35.
**Finding 39: selfHeal vs teardown.** With automated sync + selfHeal, deleting the Ingress in `make down` would just be recreated. `down.sh` now deletes the `root` Application first; finalizers cascade root -> children -> resources, so the Ingress (and the ALB, via the still-running controller) is gone before Terraform runs. Verified: ALB list empty before 40-platform destroy.
**Finding 40: App-of-apps needs an Application health check.** Argo CD 1.8+ reports no health for Application resources, so child sync waves are not waited on. 40-platform adds the upstream `resource.customizations.health.argoproj.io_Application` Lua. Verified: platform-cluster (wave 0) synced 14:45:57, feature-flag-dev (wave 1) created 14:45:59.
**Finding 41: HPA in an early sync wave deadlocks Argo CD v3.** Argo CD v3 health-checks HPAs; one whose target Deployment does not exist yet is Degraded. In wave 0 (default) it blocked the wave-2 Deployment forever ("unable to get the target's current scale ... not found", sync retrying). Fix: HPA and PDB on wave 3, after the Deployment.
**Finding 42: EKS metrics-server add-on needs port 10251 open.** The terraform-aws-modules/eks node SG allows cluster->node only on 443/4443/6443/8443/9443/10250; the add-on serves on 10251. Symptom: pods Running but `kubectl top` says "Metrics API not available", APIService "failing or missing response ... :10251 context deadline exceeded", HPA shows `<unknown>`. Fix: `node_security_group_additional_rules` for 10251 from the cluster SG.
**Finding 43: Argo CD upgraded 7.7.3 (v2.13) -> chart 10.9.2 (v3.5.3).** Fresh install each session, so no in-place migration. Dropped `application.namespaces` from argocd-cm (it belongs in cmd-params, and was unused). ServerSideApply stays off on feature-flag-dev (not needed; SSA was not re-tested on v3).
**Finding 44: Preemption ignores PodDisruptionBudgets (Step 28).** First drain test under load: 105/14258 requests failed (502/503/504 in a ~10s window). Isolated by re-running each event alone with per-failure logging: rolling restart alone = 0 failures; steady state = 0; drain with no API pod on the node = 0; drain of the node holding an API pod = 82 failures. Events showed `Preempted by pod ...` on BOTH API replicas: after the drain, everything had to fit on one t4g.small (memory requests 82%), a system-cluster-critical pod (ebs-csi-controller) could not schedule, and the scheduler preempted the lowest-priority pods - the API, at priority 0. PDBs only govern evictions, not preemption. Fixes: (1) `business-critical` PriorityClass (1e6) for the API, (2) zone topology spread, (3) realistic node replacement = surge a node first (what EKS managed node group updates do), not drain with zero headroom. Root cause is capacity: 2x 2GiB nodes cannot absorb a whole node. Also: ebs-csi-controller runs 2 replicas x 6 containers and nothing uses EBS yet - a candidate to remove to free memory.
**Finding 45: Step 28 proof (final run).** Under 20 rps constant k6 load through the ALB: GitOps rollout (push -> Argo) + node group surge 2->3 + drain of a node holding an API pod: **28,800 requests, 0 failed, p95 43.8 ms**. The drain logged "Cannot evict pod as it would violate the pod's disruption budget" x5 - the PDB held the second replica until its replacement was Ready. HPA burst (150 iterations/s = 300 req/s): CPU 26% -> 329% of request, scaled 3 -> 4 (max) in ~30 s, **53,602 requests, 0 failed, p95 73 ms**. Mechanisms: maxUnavailable 0 / maxSurge 1, ALB pod readiness gate (namespace label), preStop sleep 20s > ALB deregistration delay 10s, PDB minAvailable 1, HPA owns replicas (none in Git). Reproduce: `tests/rollout-load.js` (logs every failure with timestamp + status).
**Finding 27: Spend audit.** As of 2026-09-26, ~$1 of credits used over 3 sessions, consistent with the ~$0.73/session model. Cost Explorer lags ~24h and shows ~$0; use Billing > Credits for the real balance. All regions checked empty.

---

## 14. Target env-config Structure (Step 27)

```
feature-flag-service-env-config/
  platform/
    argocd-apps/
    eso/
    kyverno/
    monitoring/
    backstage/
  
  apps/
    feature-flag-service/
      base/
        deployment.yaml
        service.yaml
        ingress.yaml
        servicemonitor.yaml
        externalsecret.yaml    ← ExternalSecret only — NO kind:Secret in git
        hpa.yaml
        kustomization.yaml
      overlays/
        dev/
          kustomization.yaml   ← CI updates image SHA here
          patch-replicas.yaml  ← replicas: 2
        staging/
          kustomization.yaml
          patch-replicas.yaml  ← replicas: 2
        prod/
          kustomization.yaml
          patch-replicas.yaml  ← replicas: 3
          pdb.yaml             ← PodDisruptionBudget minAvailable: 2
  
  applicationsets/
    feature-flag-appset.yaml
```

### Sync Policy by Environment
| Environment | Sync | Gate |
|---|---|---|
| dev | Automated | None — any merged PR deploys |
| staging | Automated | Promotion PR required |
| prod | Manual sync | Deliberate human action required |

---

## 15. Secrets Strategy (Steps 21 + 24)

### Secrets Manager Entries
| Secret Name | Contents | Who reads it |
|---|---|---|
| `ff-idp/db-creds` | password, url | ESO → K8s Secret → app |
| `ff-idp/jwt-secret` | JWT_SECRET_KEY | ESO → K8s Secret → app |
| `ff-idp/grafana-admin` | admin-password | ESO → K8s Secret → Grafana |
| `ff-idp/backstage-github-app` | GitHub App private key, app ID | ESO → K8s Secret → Backstage |

### ESO Pattern
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: feature-flag-secrets
  namespace: feature-flag-dev
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: feature-flag-secrets
  data:
    - secretKey: DATABASE_URL
      remoteRef:
        key: ff-idp/db-creds
        property: url
    - secretKey: JWT_SECRET_KEY
      remoteRef:
        key: ff-idp/jwt-secret
        property: JWT_SECRET_KEY
```

Why ESO matters: No `kind: Secret` exists in Git at all. Structurally eliminates the secret-template GitOps trap from Step 13.

### Verification (NEVER echo plaintext)
```bash
kubectl get secret feature-flag-secrets -n feature-flag-dev \
  -o jsonpath='{.data.JWT_SECRET_KEY}' | base64 -d | sha256sum
# Compare hashes before/after rotation — never compare plaintext values
```

---

## 16. The Latency Story (A/B Experiment — Step 21)

### Current Finding (Step 16, Neon)
- p95: ~0.97s
- Redis: ~0.6ms (fast)
- Postgres fetch: ~780ms (slow — every request)
- Neon pooled endpoint used
- Root cause NOT isolated

### A/B Experiment Plan (do after Step 23 cluster is up)
- One variable changed: Neon over WAN → RDS in same VPC as pods
- Same code, same timing instrumentation (`time.perf_counter()` in `app/evaluation.py`)
- Same test: burst of /evaluate requests, check p95 from Prometheus histogram
- Keep Neon alive until this test is done

### Possible Outcomes
| Result | Conclusion |
|---|---|
| p95 collapses to <10ms | Root cause was WAN RTT / TLS / Neon pooler hop |
| p95 stays high | Root cause is SQLAlchemy session/pool handling → add OpenTelemetry (Step 34) |

---

## 16a. Step 21 A/B RESULT (measured 2026-09-26, RDS in VPC, same code)
| Path | Neon over WAN (Step 16) | RDS in VPC, server-side (in-pod) | Via ALB from laptop |
|---|---|---|---|
| `/evaluate` p95 | ~970 ms | 20 ms (DB miss) / 30 ms (Redis hit) | ~58 ms |
DB miss p50 8.3 ms vs Redis hit p50 3.9 ms => Postgres fetch ~4 ms. ~48 ms floor via ALB = laptop-to-ALB RTT (`/health` identical). Conclusion: WAN RTT/TLS/pooler was the root cause, NOT SQLAlchemy session handling. Caveat: cluster also changed (kind -> EKS); the DB location is the dominant change. Reproduce: `test_latency.py` (header explains in-pod vs ALB modes). Neon (90-legacy-neon) is no longer needed for the experiment.

---

## 16c. Measured timings (2026-09-26, clean runs, ap-south-1)
| Operation | Time |
|---|---|
| `make up` (20-data + 30-cluster + 40-platform), first-try clean run | **26.6 min** (1596 s): RDS ~10 min, cluster ~10 min, platform ~6 min |
| Sync -> API serving through ALB (incl. migration) | ~1 min after ALB provisioning |
| `make down`, clean run | **16.4 min** (981 s); slowest steps: EKS node group drain, then control plane |
Build+teardown overhead is ~43 min of billing (~$0.20) even for a 5-minute test.

---

## 16b. Next Session Checklist
Steps 23-27 are VERIFIED. A session is now: `make up` -> everything deploys itself -> work -> `make down`.
1. `aws sts get-caller-identity --profile ff-idp`, check `curl -s https://checkip.amazonaws.com` matches `allowed_cidr` in 30-cluster/variables.tf, then `make up` (~21-27 min). It waits for the root app to be Healthy.
2. Check: `kubectl get applications -n argocd` all Synced/Healthy; ALB: `kubectl get ingress -n feature-flag-dev`.
3. No manual secret or migration steps any more (JWT generated, alembic Job automatic).
4. NEXT WORK: Phase D - Step 29 (Backstage in cluster). Watch memory: 2x t4g.small is already at ~60-85% of requests; Backstage needs ~512Mi+. Options: drop the unused EBS CSI add-on, or 3 nodes (~+$0.017/hr).
5. `make down` must exit 0 and you must SEE it finish (Finding 37). Re-run it if interrupted.

---

## 17. Remaining Steps — Full Specification

> Convention: every step must be verified with real command output before moving to next.

---

### PHASE B — Cluster (Cost Starts)

#### Step 23 — EKS Cluster (30-cluster) — IN PROGRESS

File to create: `/home/surya/projects/ff-idp-infra/30-cluster/main.tf`

**BEFORE STARTING:** Verify EKS version support:
- https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
- Standard support = $0.10/hr. Extended support = $0.60/hr. DO NOT use extended.
- As of 2026-09-22, versions 1.28-1.32 are in standard support (verify before creating)

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"  # verify latest at creation time

  cluster_name    = "ff-idp-cluster"
  cluster_version = "1.31"  # CHECK support calendar — wrong = $0.60/hr not $0.10/hr

  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["<your-current-ip>/32"]
  cluster_endpoint_private_access      = true

  cluster_enabled_log_types = ["audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 1  # 1 day ONLY — CloudWatch is $0.50/GB

  eks_managed_node_groups = {
    spot = {
      instance_types = ["t4g.small"]  # Free-tier eligible ON_DEMAND to bypass Spot restrictions
      capacity_type  = "ON_DEMAND"
      ami_type       = "AL2023_ARM_64_STANDARD"
      min_size       = 2
      max_size       = 3
      desired_size   = 2
    }
  }

  cluster_addons = {
    vpc-cni                = { most_recent = true }
    coredns                = { most_recent = true }
    kube-proxy             = { most_recent = true }
    aws-ebs-csi-driver     = { most_recent = true }
    eks-pod-identity-agent = { most_recent = true }
  }
}

# NAT Gateway (lives here — destroyed nightly)
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = data.terraform_remote_state.network.outputs.public_subnet_ids[0]
  tags = { Name = "ff-idp-nat" }
}
# Add 0.0.0.0/0 → NAT to BOTH private route tables:
# rtb-05a36c795c8121544 (ap-south-1a) and rtb-0a792e4f26cc2f99e (ap-south-1b)

# ECR repo (here — immutable tags, scan on push)
resource "aws_ecr_repository" "feature_flag_service" {
  name                 = "feature-flag-service"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

# ElastiCache Valkey (here — destroyed nightly, no stop API)
resource "aws_elasticache_replication_group" "valkey" {
  replication_group_id = "ff-idp-valkey"
  description          = "Feature Flag IDP - Valkey cache"  # ASCII hyphens ONLY
  engine               = "valkey"
  engine_version       = "7.2"
  node_type            = "cache.t4g.micro"
  num_cache_clusters   = 1
  parameter_group_name = "default.valkey7"
  subnet_group_name    = aws_elasticache_subnet_group.valkey.name
  security_group_ids   = [data.terraform_remote_state.network.outputs.sg_elasticache_id]
}
```

Measure build time: `time terraform apply -auto-approve` from start to `kubectl get nodes Ready`
This is your "mean time to environment" metric for the README.

**Verify:**
```bash
kubectl get nodes -o wide
# Must show 2 nodes in DIFFERENT AZs with PRIVATE IPs

aws eks describe-cluster --name ff-idp-cluster --profile ff-idp --query 'cluster.version'
# Must match standard-support version

# After Step 23, full green CI run will work — ECR repo now exists
```

---

#### Step 24 — External Secrets Operator + IRSA

```hcl
data "aws_iam_policy_document" "eso" {
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [
      # Specific secret ARNs — NOT "*"
      "arn:aws:secretsmanager:ap-south-1:693906847772:secret:ff-idp/*"
    ]
  }
}
```

**ClusterSecretStore:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-south-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

**Verify:**
```bash
kubectl delete secret feature-flag-secrets -n feature-flag-dev
sleep 60
kubectl get secret feature-flag-secrets -n feature-flag-dev
# Must exist again (ESO recreated it)

# Secret rotation test (never echo plaintext — compare hashes)
kubectl get secret feature-flag-secrets -n feature-flag-dev \
  -o jsonpath='{.data.JWT_SECRET_KEY}' | base64 -d | sha256sum
# Rotate in Secrets Manager console, wait refreshInterval
kubectl get secret feature-flag-secrets -n feature-flag-dev \
  -o jsonpath='{.data.JWT_SECRET_KEY}' | base64 -d | sha256sum
# Hashes must differ
```

---

#### Step 25 — Ingress: ALB Controller + No-Domain Setup

**ONE shared ALB via IngressGroup (not three separate ALBs):**
```yaml
metadata:
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/group.name: ff-idp
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
```

**Verify:**
```bash
curl -sI http://<alb-dns>/health
# HTTP/1.1 200

aws elbv2 describe-load-balancers --profile ff-idp \
  --query 'LoadBalancers[?contains(LoadBalancerName, `ff-idp`)].LoadBalancerArn'
# Must show EXACTLY ONE ALB for all environments
```

---

### PHASE C — GitOps Properly

#### Steps 26 + 27 - DONE and VERIFIED 2026-09-26
- Root Application (40-platform, automated) -> `platform/argocd-apps/` -> `platform-cluster` (wave 0, ClusterSecretStore) + `feature-flag-dev` (wave 1, `apps/feature-flag-service/overlays/dev`, automated prune+selfHeal).
- env-config is Kustomize: `apps/feature-flag-service/base` + `overlays/{dev,staging,prod}`. staging/prod are defined but NOT deployed (need own DB, distinct ingress rule, more nodes - see their kustomization.yaml). Kind-era manifests deleted (in git history). Kyverno policy parked in `platform/kyverno/` (not synced until Kyverno is installed).
- JWT key is generated by 20-data each session (no manual step).
- Verified: `make up` alone -> app live, migration ran, ALB 200, zero manual syncs. Full GitOps chain: empty commit -> CI green -> bot bumps `overlays/dev` newTag -> Argo auto-rolls out the new SHA (~9 min push-to-running incl. CI; Argo polls every 3 min).
- Deviations from the original plan: Argo CD installs ESO and the ALB controller via Terraform, not Argo (bootstrap order; revisit later). No ApplicationSet yet (one env live - an ApplicationSet is worth it when staging goes live).

#### Step 26 — Argo CD via Terraform + App-of-Apps (original plan)
Terraform installs Argo CD ONLY. Argo CD installs everything else.
Sync wave order: 0=ESO, 1=ALB Controller, 2=Kyverno, 3=Prometheus+metrics-server, 4=Apps.

#### Step 27 — Multi-Environment env-config Restructure
See Section 14 for target structure. Pause Argo CD auto-sync during restructure.
Promotion: dev auto-deploys → staging PR → prod manual sync.

#### Step 28 - DONE and VERIFIED 2026-09-26 (see Findings 41, 42, 44, 45)
Zero failed requests across GitOps rollout + node surge + drain; HPA scale-out verified.

#### Step 28 — HPA + PDB + Rolling Update Proof (original plan)
k6 load during rolling update. Zero failed requests required.

---

### PHASE D — The Actual IDP

#### Step 29 — Backstage in Cluster
- Containerize idp-portal (multi-stage, non-root)
- Second DATABASE on same RDS instance (`CREATE DATABASE backstage_db`)
- Replace GitHub PAT with GitHub App, store in ff-idp/backstage-github-app secret

#### Step 30 — Software Templates (The Whole Point)
**Template 1:** `create-python-service` — new repo + CI + env-config PR + catalog register
**Template 2:** `add-feature-flag` — domain-specific golden path

**⭐ Headline demo:** Fill form → repo created → CI green → PR in env-config → merge → service deployed via ALB → appears in catalog. Time it. Put duration in README.

#### Step 31 — Backstage Plugins
Argo CD, Kubernetes, GitHub Actions, Grafana, TechDocs (S3 backed)

---

### PHASE E — Hardening

#### Step 33 — Extended Kyverno Policy Suite
5 new policies: require-resource-limits, restrict-image-registries (ECR only), require-labels, disallow-latest-tag, require-probes

#### Step 34 — Observability
Alerting: PrometheusRule → Alertmanager → Slack/Discord webhook (induce each alert, paste received notification)
Logs: Loki + promtail (cheaper than CloudWatch Container Insights)
Traces: OpenTelemetry → Tempo (resolves the Step 16 latency mystery)

#### Step 35 — DR Drill
```bash
time make nuke    # full destroy with final snapshot
time make up      # full rebuild
./tests/test_e2e.sh  # N/N checks pass
```
Mean time to full environment from zero → in README.

#### Step 36 — Rewrite test_e2e.sh for AWS/EKS
EKS context check, ALB DNS + HTTP 200, RDS from pod, ESO ExternalSecret=Ready, all 3 envs, Argo CD sync status, ECR scan (no HIGH/CRITICAL), 5 Kyverno policies, Prometheus target UP.

---

## 18. README Additions Still Needed

Add to Section 3 "Real Engineering Decisions":
8. conntrack stickiness on sequential in-cluster requests
9. NAT Gateway vs NAT instance vs VPC endpoints — arithmetic, chosen approach
10. SPOT node groups with multi-instance-type fallback — fewer interruptions
11. Terraform bootstraps Argo CD; Argo CD owns everything else — two reconcilers fighting is a real failure mode
12. ESO structurally eliminates the secret-template GitOps trap — design vs. symptom fix
13. Prod on manual sync; dev/staging auto-sync — deliberate
14. One shared ALB via IngressGroup — three ALBs = three times the hourly charge
15. The latency resolution — Neon-over-internet vs RDS-in-VPC, same code, one variable changed
16. ElastiCache has no stop API — why Valkey lives in 30-cluster not 20-data (new finding)
17. Option B lifecycle — full destroy every session, $0.00 idle, why it's better than stopping (new)
18. skip_final_snapshot = true — why it's non-negotiable for destroy-based lifecycle (new)
19. AWS em-dash rejection — non-ASCII in resource descriptions causes API errors (new)
20. Dynamic OIDC thumbprint — hardcoded thumbprints break when GitHub rotates cert (new)
21. **Region Capacity Engineering:** How we gracefully degraded from ARM/gp3 to x86/gp2 when AWS Mumbai ran out of hardware dynamically during `make up`.
22. **Spot Restrictions & AMI Types:** Understanding that cost-saving with Spot instances on new AWS accounts is tightly coupled to Free Tier guardrails, and how EKS forces architectural lock-in (ARM vs x86) at the Node Group AMI layer.
23. **API Ghosting in Verification Scripts:** The complexity of writing a "zero-cost verification" script that must navigate the AWS Tagging API's aggressive caching of deleted NAT Gateways and pending-deletion KMS keys.
24. **OIDC Thumbprint Instability:** Why relying purely on dynamic TLS certificate thumbprints for GitHub Actions OIDC fails, and why well-known static thumbprints are required as fallbacks.
25. **The ENI Pod Limit Trap:** Why `t4g.small` EKS nodes cap out at 11 pods by default, how system pods (ArgoCD, ESO, ALB Controller) easily consume this limit, and the necessity of VPC CNI Prefix Delegation.

Add "Cost Engineering" section:
- Per-hour table from verified AWS Pricing API data
- Option B vs Option A comparison
- Mean time to environment (measure in Step 23)

Add "Self-Service" section:
- Backstage template demo with measured developer-to-running-service time

Update "Known Simplifications":
- REMOVE: Secrets applied imperatively (fixed by ESO)
- REMOVE: No Ingress (fixed by ALB Controller)
- ADD: Single-AZ RDS (no Multi-AZ)
- ADD: No service mesh
- ADD: SPOT-only nodes (no on-demand fallback)
- ADD: No paid domain — HTTP only via ALB DNS
- ADD: Option B lifecycle — data not persistent between sessions

---

## 19. Interview Stories (Per Step)

Strongest stories in order:
1. **Step 30** — "developer to running service in X minutes, zero platform-team involvement"
2. **Step 21** — latency A/B: one variable changed, real data
3. **Step 24** — ESO structurally eliminates the GitOps trap class
4. **Step 35** — destroy and rebuild the entire platform every session; mean time: X minutes
5. **Step 15** — Kyverno optional-match bug (testing policy works ≠ testing policy enforces)
6. **Step 13** — secret-template GitOps trap (real, non-obvious failure mode)
7. **Step 16** — p95 0.97s discovery (data overturning untested assumption)
8. **Step 21+** — ElastiCache no-stop-API discovery; architecture decision explained by arithmetic
9. **Step 22** — Zero long-lived credentials in CI (OIDC + GitHub App = no static secrets)

---

## 20. Things That Must Never Happen

- Never operate as AWS root
- Never echo plaintext secret values — use SHA256 checksums
- Never leave EKS running unattended — make down before closing laptop, make verify-empty must pass
- Never use `Resource: "*"` in IAM policies for ESO or any scoped role
- Never use wildcards in OIDC trust policy
- Never use engine="redis" — use engine="valkey"
- Never hardcode OIDC thumbprint — use tls_certificate data source
- Never use em-dashes in AWS resource description fields — use ASCII hyphens
- Never set skip_final_snapshot=false on RDS with Option B lifecycle — $31/month snapshots
- Never drop the `terraform plan` → "No changes" check after state migrations
- Never claim a step is done without real command output as evidence
- Never assume ElastiCache can be stopped — it cannot, it must be destroyed
- Never mix ARM (t4g) and x86 (t3) instance types in the same EKS Managed Node Group.
- Never forget `force_delete = true` on ECR repositories intended for ephemeral lab teardown.
- Never rely solely on dynamic OIDC thumbprints without static fallbacks for GitHub Actions.
- Never deploy heavy system components (ArgoCD, ESO) to `t4g.small` nodes without VPC CNI Prefix Delegation enabled.

---

*End of master handover document. Any agent reading this from the top has everything needed to continue from any step without asking setup questions.*
