PROFILE   := ff-idp
ACCOUNT   := 693906847772
REGION    := ap-south-1

.PHONY: up down verify-empty neon-plan

# ─── Session start ──────────────────────────────────────────────────────────
up:
	@echo "==> Starting data layer instances..."
	aws rds start-db-instance \
	  --db-instance-identifier ff-idp-postgres \
	  --profile $(PROFILE) || true
	aws elasticache start-replication-group \
	  --replication-group-id ff-idp-valkey \
	  --profile $(PROFILE) || true
	@echo "==> Waiting for RDS to be available (up to 5 min)..."
	aws rds wait db-instance-available \
	  --db-instance-identifier ff-idp-postgres \
	  --profile $(PROFILE)
	@echo "==> Applying cluster layer..."
	terraform -chdir=30-cluster apply -auto-approve
	@echo "==> Applying platform layer..."
	terraform -chdir=40-platform apply -auto-approve
	@echo "==> Updating kubeconfig..."
	aws eks update-kubeconfig \
	  --name ff-idp-cluster \
	  --region $(REGION) \
	  --profile $(PROFILE)
	@echo "==> Waiting for Argo CD root app to be Healthy..."
	kubectl wait --for=condition=Healthy application/root \
	  -n argocd --timeout=300s
	@echo "==> Environment ready."

# ─── Session end ────────────────────────────────────────────────────────────
down:
	@echo "==> Destroying platform layer..."
	terraform -chdir=40-platform destroy -auto-approve || true
	@echo "==> Destroying cluster layer..."
	terraform -chdir=30-cluster destroy -auto-approve || true
	@echo "==> Stopping data layer instances (storage preserved)..."
	aws rds stop-db-instance \
	  --db-instance-identifier ff-idp-postgres \
	  --profile $(PROFILE) || true
	aws elasticache stop-replication-group \
	  --replication-group-id ff-idp-valkey \
	  --profile $(PROFILE) || true
	@echo "==> Verifying no billable resources remain..."
	$(MAKE) verify-empty

# ─── Cost safety check (must return []) ─────────────────────────────────────
verify-empty:
	@echo "==> Checking for running ff-idp resources..."
	@RESULT=$$(aws resourcegroupstaggingapi get-resources \
	  --tag-filters Key=Project,Values=ff-idp \
	  --query 'ResourceTagMappingList[].ResourceARN' \
	  --output json \
	  --profile $(PROFILE)); \
	echo "$$RESULT"; \
	if [ "$$RESULT" != "[]" ]; then \
	  echo "WARNING: Non-empty resource list. Check before closing laptop."; \
	  exit 1; \
	else \
	  echo "OK: No tagged resources running."; \
	fi

# ─── Neon (90-legacy-neon) — never destroyed until A/B test is complete ─────
neon-plan:
	terraform -chdir=90-legacy-neon plan
