# =============================================================================
# 40-platform/main.tf
#
# Platform layer — Argo CD + External Secrets Operator (ESO).
#
# PHILOSOPHY: Terraform installs ONLY Argo CD and ESO here.
#   Everything else (Kyverno, ALB Controller, Prometheus, Grafana, app namespaces,
#   ExternalSecrets, ClusterSecretStore) is installed BY Argo CD via app-of-apps.
#   Two reconcilers fighting is a real failure mode — Terraform owns the bootstrap,
#   Argo CD owns everything that Argo CD can manage.
#
# LIFECYCLE: DESTROYED every session (make down). Goes with 30-cluster.
#   Argo CD has no meaningful persistent state — all config is in Git.
#
# INSTALL ORDER (sync waves in Argo CD, but also logical dependency):
#   Wave 0: ESO (ExternalSecret CRDs must exist before apps reference them)
#   Wave 1: ALB Controller (Ingress resources need this to provision ALBs)
#   Wave 2: Kyverno (policy enforcement starts after controllers are up)
#   Wave 3: Prometheus + Grafana + metrics-server
#   Wave 4: Feature-flag-service app (depends on all above)
#
# COST: Argo CD runs on the EKS nodes — no extra AWS cost.
#   ESO runs on EKS nodes — no extra AWS cost.
#   ALB Controller provisions an ALB at ~$0.0239/hr — cost starts when app is deployed.
#
# ARGO CD VERSION: 7.x (Helm chart v7.x → Argo CD v2.13.x)
#   Pin to a specific chart version to avoid surprises on make up.
# =============================================================================

terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket  = "ff-idp-tfstate-693906847772"
    key     = "40-platform/terraform.tfstate"
    region  = "ap-south-1"
    profile = "ff-idp"
  }
}

# ─── AWS provider (for reading remote state only) ─────────────────────────────

provider "aws" {
  region  = "ap-south-1"
  profile = "ff-idp"

  default_tags {
    tags = {
      Project     = "ff-idp"
      ManagedBy   = "terraform"
      Environment = "shared"
      Layer       = "40-platform"
    }
  }
}

# ─── Read cluster outputs from 30-cluster state ───────────────────────────────

data "terraform_remote_state" "cluster" {
  backend = "s3"
  config = {
    bucket  = "ff-idp-tfstate-693906847772"
    key     = "30-cluster/terraform.tfstate"
    region  = "ap-south-1"
    profile = "ff-idp"
  }
}

# ─── EKS cluster auth — used by helm and kubernetes providers ─────────────────

data "aws_eks_cluster" "this" {
  name = data.terraform_remote_state.cluster.outputs.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = data.terraform_remote_state.cluster.outputs.cluster_name
}

# ─── Helm provider ────────────────────────────────────────────────────────────

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# ─── Kubernetes provider (for namespaces and post-deploy manifests) ───────────

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

# =============================================================================
# EXTERNAL SECRETS OPERATOR (ESO)
# =============================================================================
# ESO bridges Kubernetes with AWS Secrets Manager.
# Installs CRDs: ExternalSecret, ClusterSecretStore, SecretStore.
# The ESO pod uses IRSA (via ServiceAccount annotation) to call secretsmanager:*.
#
# IRSA wiring:
#   ServiceAccount "external-secrets" in namespace "external-secrets"
#   → annotated with ff-idp-eso IAM role ARN (from 30-cluster)
#   → role trust policy allows sts:AssumeRoleWithWebIdentity from this SA
#
# Chart: external-secrets/external-secrets
# installCRDs: true — CRDs installed with the chart (cleaner than separate apply)
# =============================================================================

resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = "external-secrets"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "eso" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.10.3"
  namespace        = kubernetes_namespace.external_secrets.metadata[0].name
  create_namespace = false
  wait             = true
  timeout          = 300

  set {
    name  = "installCRDs"
    value = "true"
  }

  # Wire the ESO controller ServiceAccount to the IRSA role.
  # The trust policy in 30-cluster is already scoped to this exact SA name + namespace.
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = data.terraform_remote_state.cluster.outputs.eso_irsa_role_arn
  }

  depends_on = [kubernetes_namespace.external_secrets]
}

# =============================================================================
# ARGO CD
# =============================================================================
# Argo CD is installed by Terraform (bootstrap problem: Argo CD cannot install itself).
# After this, Argo CD owns everything — never apply K8s manifests to Argo-managed
# resources via kubectl or Terraform (selfHeal will fight you).
#
# Chart: argo/argo-cd
# Version: 7.7.3 (Argo CD v2.13.x) — pinned for reproducibility
#
# ADMIN PASSWORD: Auto-generated by the chart as a bcrypt hash.
#   Retrieve with:
#     kubectl get secret argocd-initial-admin-secret -n argocd \
#       -o jsonpath='{.data.password}' | base64 -d
#
# ACCESS: Port-forward only (no ALB for Argo CD — not worth the cost for a lab).
#   kubectl port-forward svc/argocd-server -n argocd 8080:443
#   Then: https://localhost:8080
#
# SERVER.INSECURE: true — disables TLS inside the pod (port-forward handles it).
#   This removes the double TLS which causes cert errors in the UI.
#
# REPO SERVER: pulls manifests from GitHub. The env-config repo is public so no
#   credentials needed. Private repos would need a GitHub App credential secret.
#
# NOTIFICATIONS: disabled — no alerting infra yet (Step 34).
# =============================================================================

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.7.3"
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  create_namespace = false
  wait             = true
  timeout          = 600

  values = [<<-EOT
    global:
      domain: localhost

    configs:
      params:
        server.insecure: true

      # Allow Argo CD to manage resources in all namespaces (needed for app-of-apps).
      # Without this, Argo CD can only sync into its own namespace.
      cm:
        application.namespaces: "feature-flag-dev,feature-flag-staging,feature-flag-prod,monitoring,kyverno"

    server:
      # Resource requests sized for t4g.small (2vCPU/2GiB per node, shared with system pods)
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 500m
          memory: 256Mi

    repoServer:
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 500m
          memory: 256Mi

    applicationSet:
      resources:
        requests:
          cpu: 20m
          memory: 64Mi
        limits:
          cpu: 200m
          memory: 128Mi

    notifications:
      enabled: false

    dex:
      enabled: false
  EOT
  ]

  depends_on = [kubernetes_namespace.argocd, helm_release.eso]
}

# =============================================================================
# ARGO CD — APP OF APPS ROOT APPLICATION
# =============================================================================
# The root Application points at the env-config repo.
# Argo CD syncs this and discovers all child Applications defined there.
#
# WHY null_resource + kubectl, NOT kubernetes_manifest:
#   kubernetes_manifest validates the CRD at PLAN time. Argo CD CRDs don't
#   exist until the helm_release.argocd is applied. This creates a
#   chicken-and-egg problem that kubernetes_manifest cannot handle.
#   null_resource runs after the helm release is deployed (at apply time),
#   at which point the CRDs are already installed.
#
# SYNC POLICY: automated with selfHeal + prune.
#   selfHeal: reverts manual kubectl apply changes.
#   prune: removes K8s resources when manifests are removed from Git.
#
# NOTE: The env-config repo currently has a flat structure (Step 27 restructure
# is pending). Path is set to "." (repo root) for now.
# After Step 27: change path to "platform/argocd-apps"
#
# DESTROY: On terraform destroy, the null_resource runs the delete command
#   via the destroy provisioner, removing the root Application from the cluster
#   before Argo CD itself is removed.
# =============================================================================

resource "null_resource" "argocd_root_app" {
  triggers = {
    # Re-apply if cluster endpoint changes (new cluster after make up)
    cluster_endpoint = data.aws_eks_cluster.this.endpoint
    # Re-apply if the manifest content changes
    manifest_hash = sha256(<<-YAML
      apiVersion: argoproj.io/v1alpha1
      kind: Application
      metadata:
        name: root
        namespace: argocd
        finalizers:
          - resources-finalizer.argocd.argoproj.io
      spec:
        project: default
        source:
          repoURL: https://github.com/DSurya11/feature-flag-service-env-config
          targetRevision: HEAD
          path: "."
          directory:
            recurse: false
            exclude: "*.yaml.example"
        destination:
          server: https://kubernetes.default.svc
          namespace: argocd
        syncPolicy:
          automated:
            prune: true
            selfHeal: true
          syncOptions:
            - CreateNamespace=true
            - ServerSideApply=true
    YAML
    )
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -f - <<'YAML'
      apiVersion: argoproj.io/v1alpha1
      kind: Application
      metadata:
        name: root
        namespace: argocd
        finalizers:
          - resources-finalizer.argocd.argoproj.io
      spec:
        project: default
        source:
          repoURL: https://github.com/DSurya11/feature-flag-service-env-config
          targetRevision: HEAD
          path: "."
          directory:
            recurse: false
            exclude: "*.yaml.example"
        destination:
          server: https://kubernetes.default.svc
          namespace: argocd
        # NOTE: syncPolicy is intentionally omitted here (no automated sync).
        # The env-config repo has a flat structure until Step 27 restructure.
        # Enabling auto-sync on the flat repo causes failures because the raw
        # manifests reference CRDs (ServiceMonitor, ClusterPolicy) not yet installed.
        # After Step 27: re-enable automated sync with prune + selfHeal.
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
      YAML
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete application root -n argocd --ignore-not-found=true --timeout=60s || true"
  }

  depends_on = [helm_release.argocd]
}

