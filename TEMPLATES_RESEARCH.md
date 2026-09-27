# Golden Path Templates: Research and Target Design

> Written 2026-09-27, after the first live run of `python-service` (`hello-svc`, form to running in 5m31s).
> Purpose: define what a production-grade golden path means for this IDP, measure the current
> template against it, and fix the order of work. HANDOVER_DOC.md is still the master context;
> this file owns everything about templates.

---

## 1. Where we are, and what the first live run showed

What one template run touches today:

```
Backstage form (signed in with GitHub)
 ├─ 1. publish:github (user token)   -> NEW repo DSurya11/<name>        (created directly, no PR)
 │        └─ its CI: docker build (arm64) -> Trivy -> push ECR svc/<name>:<sha>
 ├─ 2. publish:github:pull-request   -> PR in idp-gitops                (NOT idp-infra)
 │        adds apps/<name>/{base,overlays/dev} + platform/argocd-apps/<name>.yaml
 ├─ 3. catalog:register              -> Component <name> in Backstage
 └─ human merges the idp-gitops PR   -> Argo CD root app creates Application <name> -> ALB route
```

- **idp-infra is never touched.** It holds Terraform only. A template changes idp-infra only if a
  service needs new AWS resources (a bucket, a queue or an IAM role).
- **The PR is into idp-gitops**, the repo Argo CD deploys from. The service's own repo is created
  directly. The deploy config lives in a separate repo on purpose: Argo CD's own best-practice
  guide recommends a separate config repo (a clean audit log, access separation, no CI loops when
  bots commit tags) [1].

What the run exposed (measured, not assumed):

| # | Problem | Consequence |
|---|---|---|
| G1 | A human has to merge the idp-gitops PR after watching CI | dev is not zero-touch. This contradicts HANDOVER section 14 ("dev: automated, any merged PR deploys") |
| G2 | **The generated CI never updates idp-gitops after the first deploy** | the service stays pinned to its first commit forever. A developer's second push builds an image that nothing deploys. **This is the most serious gap.** |
| G3 | CI runs no tests, lint or type checks, and there are no tests in the skeleton | "green CI" only means the image built and has no fixable HIGH CVEs |
| G4 | The whole CI pipeline is copied into every repo (70 lines) | a platform fix (a new scan, a new runner) never reaches existing services |
| G5 | Kubernetes manifests are copied into `apps/<name>/base` per service | same drift problem for deploy settings (Step 28 lessons stay frozen at copy time) |
| G6 | No observability (metrics, traces, structured logs), no docs (TechDocs), no API entity | the service is not operable or discoverable beyond "it exists" |
| G7 | Supply chain: no SBOM, no signature, no provenance; actions pinned by tag, not SHA | cannot prove what runs in the cluster came from CI |
| G8 | Owner is a free-text user, no System, lifecycle hardcoded `experimental` | the catalog cannot answer "who owns this, what is it part of" |
| G9 | Day-2 is missing: no way to add a DB, add a flag, promote or decommission | templates are one-shot scaffolding, not a platform |

The rest of this document explains what the industry does about each of these, then gives the target design.

---

## 2. What "golden path" means in industry (sources in section 10)

- **Spotify (originated the term, built Backstage):** "the opinionated and supported way to build
  something". It pairs a step-by-step tutorial (TechDocs) with a template, and golden path docs are
  Spotify's most-read internal documentation [2]. The template wires the new service into CI/CD,
  monitoring and logging from the first commit, so a new service starts compliant [3].
- **CNCF Platforms white paper and maturity model:** a platform is "an internal product providing a
  curated experience for developers, reducing cognitive load while retaining autonomy". Golden
  paths, self-service provisioning, a catalog and scorecards are core capabilities. The maturity
  model rates how consistently these are provided and measured [4][5].
- **What separates a golden path from a template:** it carries strong opinions on language, test
  framework, CI, observability and secret handling, "all of it provided in the form the
  organization has committed to" [6]. And it is *supported*: the platform team maintains it after
  day 1.
- **Red Hat's "10 tips" for Backstage templates:** one central template repo with a root Location
  (done, Finding 53), OwnerPicker/EntityPicker instead of free text, TechDocs in every template,
  test templates through the scaffolder API, and maintain them continuously [7].
- **Central, versioned CI:** the platform repo owns the delivery logic as reusable workflows
  (`workflow_call`), and each app repo holds one thin caller pinned to a version. Treat workflows as
  an API: inputs are the contract, breaking changes bump the major version [8].
- **Promotion is a separate layer from GitOps:** Argo CD syncs whatever Git says; something has to
  change Git per environment. Industry answers: CI bots (what we do), Argo CD Image Updater (watches
  the registry and writes the new tag back to Git) [9], or Kargo (Warehouse -> Freight -> Stages
  dev/staging/prod, each with its own promotion rules) [10].
- **App onboarding without editing platform files:** an Argo CD ApplicationSet with a Git directory
  generator creates one Application per matching directory automatically ("whenever a new
  subdirectory is added ... automatically deploy ... within new Application resources") [11].
- **Supply chain:** keyless cosign signing with the GitHub Actions OIDC identity (no keys), SLSA
  provenance via `actions/attest-build-provenance`, and admission control (Kyverno `verifyImages`)
  that rejects unsigned images [12][13].
- **Keeping services on the path after day 1:** scorecards (Backstage Tech Insights, Spotify
  Soundcheck) turn standards into checks per catalog entity (for example: has TechDocs, CI green,
  template version current) [14].

### How industry handles dev vs staging vs prod

| Environment | Industry norm | Human involvement |
|---|---|---|
| dev | every green build on main deploys automatically (CD) | none |
| staging | automatic or one-click promotion of a build that passed dev | optional |
| prod | promotion of the exact artifact that passed staging, with approval | yes (approval and audit trail) |

A PR is used where review adds information (a human decision, a diff someone should read). For dev,
the "review" we had was a person waiting for CI to go green. A machine does that better. **So G1 is
a real defect, not a safety feature.**

---

## 3. Gap matrix: industry standard vs `python-service` today

Legend: Have / Partial / Missing. "Fit" = worth doing in this project given its constraints (section 7).

| Area | Industry standard | Today | Fit |
|---|---|---|---|
| **Delivery** | zero-touch dev deploy on every green main build | Missing (G1, G2) | **P0** |
| | onboarding creates no hand-written platform files (ApplicationSet) | Missing: one Application file per service | P0 |
| | promotion to staging/prod with a gate | Missing (overlays only) | P2 |
| **CI** | central reusable workflow, thin caller, pinned version | Missing (G4) | **P0** |
| | lint (ruff), types (mypy), tests (pytest + coverage gate) | Missing (G3) | **P0** |
| | native arm64 build, immutable SHA tags, OIDC to AWS | Have | - |
| | vuln gate (Trivy image + filesystem/deps) | Partial (image only) | P1 |
| | SBOM, cosign keyless signature, SLSA provenance | Missing (G7) | P1 |
| | actions pinned by SHA, least-privilege `permissions:` | Partial | P1 |
| | Dependabot/Renovate for deps + base image | Missing | P1 |
| **Code skeleton** | dependency lock (uv + `uv.lock`), `pyproject.toml` | Missing (plain requirements.txt) | P0 |
| | settings from env (pydantic-settings), structured JSON logs with request id | Missing | P0 |
| | liveness vs readiness (readiness checks dependencies), graceful shutdown | Partial (one /health) | P0 |
| | `/metrics` (Prometheus), OpenTelemetry tracing hooks | Missing | P1 (needs Step 34 stack) |
| | feature flag client helper (our own flag service) | Missing | P1 (planned) |
| | example tests, pre-commit, Makefile/justfile, `.editorconfig` | Missing | P0 |
| **Container** | multi-stage build, base pinned by digest, non-root, no shell tools needed at runtime | Partial (non-root, single stage, tag not digest) | P0 |
| **Kubernetes** | shared base maintained centrally (Kustomize component / remote base) | Missing (G5, copied) | **P0** |
| | zero-downtime set (maxUnavailable 0, preStop, readiness gate, PDB, HPA, spread, priority) | Have (Step 28) | - |
| | Pod Security "restricted": readOnlyRootFilesystem, drop ALL, seccomp RuntimeDefault, no SA token | Partial (non-root, no privilege escalation) | P0 |
| | own ServiceAccount (IRSA-ready), startupProbe | Missing | P0 |
| | NetworkPolicy default-deny | Missing (VPC CNI needs network policy enabled, costs memory) | P2 |
| | LimitRange/ResourceQuota per namespace | Missing | P1 |
| **Catalog** | owner = Group (OwnerPicker), System, lifecycle chosen, API entity from OpenAPI | Partial (G8) | P0 |
| | TechDocs (mkdocs + docs/), runbook, links to dashboards/logs/Argo | Missing (G6) | P0 (docs), P1 (links) |
| | plugin annotations (Argo CD, Kubernetes, GitHub Actions) | Partial (k8s id only; plugins are Step 31) | P1 |
| **Repo** | branch ruleset on main (required checks), CODEOWNERS, secret scanning + push protection | Missing | P1 |
| **Template itself** | tested in CI (render -> lint/test/build/kubeconform/kyverno) | Missing (tested by hand once) | **P0** |
| | versioned; generated repos record the template version | Missing | P1 |
| | form: pickers, validation, conditional options (DB? cache? public route?) | Partial | P1 |
| **Day 2** | add DB / add flag / promote / decommission templates | Missing (G9) | P1 |
| | scorecards (Tech Insights) | Missing | P2 (Step 31) |

---

## 4. Target design: zero-touch dev delivery

### 4.1 Options for "every green build deploys to dev"

| Option | How | Credentials | Verdict |
|---|---|---|---|
| A. CI bot in every repo (today's feature-flag-service pattern) | service CI mints an App token and commits the new tag to idp-gitops | the bot's **private key copied into every generated repo** (a personal account has no org-level secrets) | Reject: credential sprawl grows with every service |
| B. **Argo CD Image Updater** | in-cluster controller watches ECR `svc/*`, strategy `newest-build` (SHA tags), writes `newTag` back to idp-gitops (git write-back) [9] | **one** GitHub credential in the cluster (via ESO) + IRSA for ECR read | **Recommended for dev.** Small (one pod), CRD-based since v1.0 |
| C. Kargo | Warehouse watches ECR, Stage `dev` auto-promotes; staging/prod gated [10] | one credential, in cluster | Best for multi-stage promotion. Heavier (controller + API + UI) on 2x t4g.small. Revisit when staging is real |
| D. App repo holds its own manifests + ApplicationSet SCM generator | no gitops repo PR at all | none extra | Reject: loses the config-repo separation Argo CD recommends [1], and tag bumps inside the app repo cause CI loops |

Note on B: ECR tokens expire (12h). The updater must use IRSA plus a credentials helper, or a
refreshed pull secret. Verify against the Argo CD 3.5 / Image Updater version matrix at build
time [9].

### 4.2 Onboarding (the first deploy) without a click

The ordering problem: the deploy config pins an image that the new repo's CI has not pushed yet.

Target flow:

```
Form submit
 1. publish:github (user token)                -> repo + first CI run starts
 2. publish:github:pull-request (App)          -> idp-gitops PR: apps/<name>/overlays/dev ONLY
                                                  (no Argo Application file: the ApplicationSet finds it)
 3. idp:github:await-and-merge (custom action) -> waits for (a) the service CI run on the first
                                                  commit and (b) idp-gitops validation checks on the PR;
                                                  both green -> merge (App). Any red -> task fails,
                                                  PR stays open with the reason.
 4. catalog:register
 Argo ApplicationSet (git directory generator over apps/*/overlays/dev) -> Application -> sync -> ALB route
Every later push to main: CI (reusable workflow) -> ECR -> Image Updater writes newTag -> Argo syncs
```

- The PR still exists as the audit record (who asked, which task, which commit), but nobody clicks it.
- idp-gitops gets a validation workflow (`kustomize build` + kubeconform + Kyverno CLI), so a bad
  config cannot merge, whether a human or a bot wrote it.
- The custom action is a small scaffolder backend module in idp-portal (Octokit: poll
  check-runs/workflow runs for the SHA, then `pulls.merge`), with a timeout (for example 10 min).
- Staging/prod (later): a `promote` template opens a PR that a human approves, or Kargo stages.
  That is where the gate belongs.

---

## 5. Target design: making the path maintainable (fixing drift)

A template is copied once. Everything that must keep improving after day 1 moves out of the copy:

| Concern | Lives in (central, versioned) | Generated repo contains |
|---|---|---|
| CI pipeline | reusable workflow in a platform repo, e.g. `DSurya11/idp-platform/.github/workflows/python-service.yml@v1` [8] | a ~15-line caller with inputs |
| K8s deployment settings | Kustomize component in `idp-gitops/components/python-service` (the Step 28 set + pod security + SA) | an overlay with name, image, resources, env |
| Lint/type/test config | template skeleton (`pyproject.toml`), kept current by Dependabot | its own copy (normal for code) |
| Standards compliance | Tech Insights checks (template version, docs present, CI green) [14] | `idp.dev/template-version` annotation in catalog-info |

Platform upgrade path: bump the reusable workflow `v1 -> v1.1` (non-breaking, callers on `@v1`
pick it up) or ship `v2` and let Dependabot/Renovate open PRs in service repos.

---

## 6. Proposed template catalog for this IDP (prioritized)

Strength over count: one golden path done properly beats five toy templates. Order:

### T1. `python-service` v2: the flagship golden path (P0)
- **Form:** name (validated), description, owner (OwnerPicker -> Group), system (EntityPicker),
  lifecycle, options: *needs Postgres*, *needs cache*, *public route on ALB (else internal only)*,
  *include feature flag client*.
- **Repo:** uv + `pyproject.toml` + `uv.lock`, ruff, mypy, pytest with coverage gate, example
  tests, pre-commit, Makefile, Dependabot, CODEOWNERS, `.editorconfig`.
- **App:** FastAPI, pydantic-settings, JSON logs with request id, `/health/live` and
  `/health/ready` (checks the DB/cache when enabled), graceful shutdown, `/metrics`, OpenTelemetry
  hooks (off until Step 34), feature flag helper (fail-safe default, cached), exported OpenAPI.
- **Container:** multi-stage, base pinned by digest, non-root 10001, compatible with a read-only root.
- **CI:** thin caller of the reusable workflow: lint, types, test, build arm64, Trivy (fs +
  image), SBOM, cosign keyless sign, provenance attestation, push. Actions pinned by SHA.
- **Deploy:** overlay on the central component, own ServiceAccount, restricted pod security,
  startupProbe, LimitRange. Zero-touch via section 4.
- **Catalog/docs:** Component + API (OpenAPI) + TechDocs (`mkdocs.yml`, `docs/index.md`,
  `docs/runbook.md`), links to Argo/ALB URL, template version annotation.
- **Tested:** idp-portal CI renders the template with fixed values and runs the generated repo's
  own checks + `kustomize build | kubeconform` + Kyverno CLI. A template change that produces a
  broken service fails before merge.

### T2. `add-feature-flag` (P1, domain-specific, the IDP's differentiator)
Day-2 template on an existing service (EntityPicker restricted to Components): creates the flag in
feature-flag-service through its API (percentage, targeting rules), registers it in the catalog as
a Resource that the component `dependsOn`, and opens a PR in the service repo adding the flag
check through the helper from T1. Needs a service credential for the flag API (ESO-managed, used
by a scaffolder action, never by the browser).

### T3. `add-postgres-database` (P1)
Day-2: a dedicated database + user on the shared RDS, the password in Secrets Manager, an
ExternalSecret in the service overlay, a catalog Resource. Design constraint: RDS is recreated
every session (Option B) and is private (`publicly_accessible=false`), so the laptop's Terraform
cannot run `CREATE DATABASE`. Provisioning must be declarative and in-cluster: a list in idp-gitops
(`platform/databases/<name>.yaml`) reconciled by an idempotent Job (Argo sync hook, master
credentials via ESO) or by a Postgres operator. It then re-creates itself after every `make up`.

### T4. `decommission-service` (P1)
Removes `apps/<name>` from idp-gitops (Argo prunes it, which removes the ALB rule), deletes ECR
`svc/<name>`, archives the repo, unregisters the catalog entities. Lifecycle is part of the path,
and on 2x t4g.small every abandoned service holds 2 pods of capacity.

### T5. `promote` (P2, when staging exists)
PR from dev tag -> staging/prod overlay with a required approval, or Kargo stages (section 4.1 C).

### Not planned (and why)
Other languages (Go, Node): nothing in this IDP needs them yet, and one excellent path is the
point. Library/package template: no internal package registry. Terraform-backed resource
templates (S3, SQS + IRSA): only when a service needs one (HANDOVER section 0a).

---

## 7. Constraints of this project that shape the design

| Constraint | Effect |
|---|---|
| Personal GitHub account (no org) | Apps cannot create repos (Finding 52: user token needed); no org secrets (-> option B, not A); no GitHub Teams (owner Groups exist in the catalog only) |
| 2x t4g.small (2 GiB), HPA min 2 per service | every in-cluster addition (Image Updater, Kyverno, Kargo, observability) is weighed in memory; decommissioning matters |
| Destroy-every-session (Option B) | anything a template provisions must be declarative in Git or Terraform so `make up` recreates it; RDS data does not survive |
| No domain, Backstage via port-forward only | GitHub OAuth redirect is `localhost:7007`; no webhooks into the cluster (Argo polls, 3 min) |
| Credits (~$0.26/hr while up) | build and render-test templates **offline**; bring the cluster up only to verify end to end |

---

## 8. Implementation plan

Each phase ends with evidence (command output), per the HANDOVER convention.

| Phase | Work | Done when |
|---|---|---|
| 1. Delivery (P0) | ApplicationSet over `apps/*/overlays/dev`; Image Updater (IRSA + one GitHub credential via ESO); `idp:github:await-and-merge` action; idp-gitops validation workflow; template stops writing Application files | new service from the form reaches ALB 200 with **zero clicks**; a second push to it deploys automatically; time recorded |
| 2. Central CI + component (P0) | `idp-platform` repo with the reusable workflow (lint/type/test/build/scan/push); Kustomize component in idp-gitops; migrate `hello-svc` onto both | hello-svc repo CI is a thin caller; changing the component changes hello-svc on the next sync |
| 3. Skeleton v2 (P0) | uv/pyproject, tests, settings, logs, live/ready, pod security, SA, TechDocs, API entity, owner/system pickers | rendered skeleton passes its own CI locally and in GitHub; Trivy clean; restricted pod security admitted |
| 4. Template CI (P0) | render-and-test job in idp-portal CI | a deliberately broken skeleton change fails idp-portal CI |
| 5. Supply chain (P1) | SBOM + cosign keyless + provenance in the reusable workflow; Kyverno verifyImages (with Step 33) | an unsigned image is rejected by admission |
| 6. Day-2 (P1) | T2 add-feature-flag, T3 add-postgres-database, T4 decommission | each run end to end from the form |
| 7. Later (P2) | T5 promote / Kargo, NetworkPolicy, scorecards (Step 31), observability hooks live (Step 34) | - |

The feature-flag-service and idp-portal CI bots (option A) can move to Image Updater in phase 1 as
well, removing the CI bot private key from those repos.

---

## 9. Open decisions (for the user)

1. Zero-touch mechanism: Image Updater now, Kargo later (recommended) vs Kargo now.
2. Onboarding merge: PR + automatic merge after checks (recommended, keeps an audit record) vs a
   direct commit to idp-gitops main.
3. The name of the central platform repo (`idp-platform` suggested) for reusable workflows.
4. Whether `hello-svc` is migrated to v2 (recommended: it proves the upgrade path) or decommissioned.

---

## 10. Sources

1. Argo CD, Best Practices (separate config repo): https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/
2. Spotify Engineering, How we use Golden Paths to solve fragmentation (2020): https://engineering.atspotify.com/2020/08/how-we-use-golden-paths-to-solve-fragmentation-in-our-software-ecosystem
3. Spotify for Backstage, Onboarding software / templates: https://backstage.spotify.com/learn/onboarding-software-to-backstage/setting-up-software-templates/11-spotify-templates/ and InfoQ on Spotify paved paths: https://www.infoq.com/news/2021/03/spotify-paved-paths/
4. CNCF TAG App Delivery, Platforms White Paper: https://tag-app-delivery.cncf.io/whitepapers/platforms/
5. CNCF TAG App Delivery, Platform Engineering Maturity Model: https://tag-app-delivery.cncf.io/whitepapers/platform-eng-maturity-model/
6. Scale Wars #6, Spotify golden paths: https://dev.to/turacthethinker/scale-wars-6-spotify-the-squad-model-and-the-power-of-golden-paths-4poa
7. Red Hat Developer, 10 tips for better Backstage Software Templates (2025): https://developers.redhat.com/articles/2025/03/17/10-tips-better-backstage-software-templates
8. Reusable workflows as a platform (versioned `workflow_call`): https://rajivonai.com/blog/2024-08-20-github-actions-for-platform-teams-reusable-workflows-oidc-environments-and-audit/ and https://techcommunity.microsoft.com/blog/azureinfrastructureblog/cicd-as-a-platform-shipping-microservices-and-ai-agents-with-reusable-github-act/4504550
9. Argo CD Image Updater, update methods and v1 migration: https://argocd-image-updater.readthedocs.io/en/stable/basics/update-methods/ and https://argocd-image-updater.readthedocs.io/en/stable/configuration/migration/ ; ECR setup: https://devopscube.com/setup-argocd-image-updater/
10. Akuity, Kargo (promotion layer for GitOps): https://akuity.io/blog/how-kargo-fixes-gitops-with-promotion and https://docs.kargo.io/user-guide/how-to-guides/working-with-stages
11. Argo CD ApplicationSet, Git generator: https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/
12. Kyverno, Verify SLSA provenance (keyless): https://kyverno.io/policies/other/verify-image-slsa/verify-image-slsa/
13. Cosign keyless signing with GitHub Actions OIDC: https://www.qcecuring.com/blog/sigstore-cosign-keyless-github-actions
14. Roadie, Tech Insights scorecards: https://roadie.io/backstage/plugins/tech-insights/ ; Spotify Soundcheck: https://backstage.spotify.com/partners/spotify/plugin/soundcheck
