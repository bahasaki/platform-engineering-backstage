# platform-engineering-backstage

Self-service developer platform. Core outcome, **fully verified end-to-end**:
**a developer fills out a form in Backstage, and two minutes later has a
running service on EKS — no manual Kubernetes, Docker, or AWS console work
required.**

```
Backstage
    v
Create Service (Scaffolder form)
    v
Git repository (published via publish:github)
    v
GitHub Actions (build-and-push.yaml)
    v
Docker build -> ECR push
    v
Kubernetes manifest (k8s/deployment.yaml, image tag auto-updated + committed)
    v
ArgoCD (auto-sync via k8s/argocd-application.yaml)
    v
EKS
    v
curl /healthz -> {"status":"ok","service":"hello-fastapi"}   VERIFIED LIVE
```

Every step above was independently confirmed against a real, running test
service (`hello-fastapi`) — not just "the pipeline looks correct on paper."
See `docs/incidents/` for the seven real issues hit and fixed along the way.

See `docs/adrs/0001-scaffolder-gitops-over-techdocs-first.md` for why this
ordering was chosen over a Catalog/TechDocs-first approach.

## What's in this repo

- `packages/app`, `packages/backend` — the Backstage app skeleton
  (from `@backstage/create-app@0.9.0`).
- `catalog/entities/*.yaml` — Component/System entries for all 7 existing
  portfolio projects (Terraform-Scripts, aws-ecs-url-shortener,
  wordpress-javari, eks-fintech-platform, aws-event-driven-orders,
  aws-rds-fintech-ledger, aws-stepfunctions-fintech-transfer), plus the
  `fintech-portfolio` System tying them together.
- `templates/fastapi-service/` — the Scaffolder template. `template.yaml`
  defines the form (service name, AWS region, ECR URI, k8s namespace, repo
  target) and three steps: fetch the skeleton, publish to GitHub, register
  in the catalog. `content/` is the skeleton itself: FastAPI app, Dockerfile,
  GitHub Actions workflow, k8s Deployment/Service, ArgoCD Application.
- `infra/eks/` — Terraform for a demo EKS cluster (public subnets, no NAT —
  see ADR 0002), used to validate the ArgoCD/EKS leg of the pipeline. This
  cluster is **not left running** — see "Reproducing this end-to-end" below.
- `app-config.yaml` — wired to load the catalog entities and the template.
- `docs/adrs/` — three ADRs documenting key decisions (Scaffolder+GitOps
  priority, no NAT Gateway for the demo cluster, why the EKS Terraform lives
  in this repo rather than standalone).
- `docs/incidents/` — seven real incidents hit while building this,
  documented Symptoms -> Investigation -> Root Cause -> Fix -> Verification
  -> Prevention -> Lessons Learned.

## One-time setup (already done once, documented here for reproducing)

1. `yarn install`, then `yarn start` — app on `localhost:3000`, backend on
   `localhost:7007`.
2. GitHub integration: a fine-grained PAT with `Contents`, `Administration`,
   and `Workflows` write access, set under `integrations.github` in
   `app-config.local.yaml` (gitignored, never committed).
3. AWS OIDC: an IAM Identity Provider trusting
   `token.actions.githubusercontent.com`, plus an IAM role
   (`github-actions-ecr-push-role`) with a trust policy matching **both**
   the classic and immutable GitHub OIDC subject claim formats (see
   Incident 005) and a least-privilege ECR push/pull permissions policy.
   The role's ARN is stored as the `AWS_ROLE_ARN` secret in each
   Scaffolder-generated repo.
4. An ECR repository matching each generated service's name.

## Reproducing this end-to-end (validating the ArgoCD/EKS leg)

The EKS cluster in `infra/eks/` is a one-off validation resource, not a
permanently running environment — consistent with this portfolio's cost
discipline of destroying infrastructure after each demo (see ADR 0003).

```bash
cd infra/eks
terraform init
terraform apply     # ~2 min once instance type is Free Tier eligible (see Incident 006)
aws eks update-kubeconfig --region us-east-1 --name backstage-demo-eks

helm repo add argo https://argoproj.github.io/argo-helm
kubectl create namespace argocd
helm install argocd argo/argo-cd --namespace argocd

# Register the Scaffolder-generated service's Application with ArgoCD
kubectl apply -f k8s/argocd-application.yaml   # from the generated service's repo

# Private repos need explicit credentials for ArgoCD (see Incident 007)
kubectl create secret generic <service>-repo \
  --namespace argocd \
  --from-literal=type=git \
  --from-literal=url=<repo-url> \
  --from-literal=username=<github-username> \
  --from-literal=password=<github-pat> \
  --dry-run=client -o yaml \
  | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
  | kubectl apply -f -

kubectl get applications -n argocd     # expect SYNC STATUS: Synced
kubectl get pods -n default            # expect service pods 1/1 Running

# Verify actual behavior, not just pod status
kubectl port-forward svc/<service> 8080:80 -n default
curl http://localhost:8080/healthz

# Cost discipline: destroy once verified
cd infra/eks
terraform destroy
```

## Known limitations / deliberately out of scope

- **TechDocs is not wired up.** Deliberately deprioritized — see ADR 0001.
  The Scaffolder + GitOps self-service loop was the core deliverable; a
  documentation portal adds no evidence toward that claim.
- **Grafana / observability was not reconnected for this demo.** The
  Scaffolder-generated pipeline was validated for correctness (a real
  service builds, deploys, and serves traffic), not for observability —
  that's already covered in depth by `eks-fintech-platform`
  (kube-prometheus-stack, custom dashboards, PrometheusRules,
  Alertmanager). Duplicating it here would add cost and time without
  adding new evidence to this project's specific claim.
- **The OIDC trust policy uses a broad repo wildcard** (`repo:bahasaki/*:*`
  and `repo:bahasaki@*:*`), not a per-repository scope. This is a
  deliberate self-service tradeoff — every future Scaffolder-generated
  service can authenticate without manual IAM changes — documented as a
  known tradeoff rather than an oversight.
