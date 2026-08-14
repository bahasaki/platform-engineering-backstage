# platform-engineering-backstage

Self-service developer platform demo. Core outcome:
**a developer can provision a new FastAPI service through Backstage, and it
reaches EKS via GitOps without any manual steps.**

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
Grafana (existing kube-prometheus-stack from eks-fintech-platform)
```

See `docs/adrs/0001-scaffolder-gitops-over-techdocs-first.md` for why this
ordering was chosen over a Catalog/TechDocs-first approach.

## What's already generated

- `packages/app`, `packages/backend` — the Backstage app skeleton
  (from `@backstage/create-app@0.9.0`), dependencies **not yet installed**.
- `catalog/entities/*.yaml` — Component/System entries for all 7 existing
  portfolio projects (Terraform-Scripts, aws-ecs-url-shortener,
  wordpress-javari, eks-fintech-platform, aws-event-driven-orders,
  aws-rds-fintech-ledger, aws-stepfunctions-fintech-transfer).
- `templates/fastapi-service/` — the Scaffolder template. `template.yaml`
  defines the form (service name, AWS region, ECR URI, k8s namespace, repo
  target) and three steps: fetch the skeleton, publish to GitHub, register
  in the catalog. `content/` is the skeleton itself: FastAPI app, Dockerfile,
  GitHub Actions workflow, k8s Deployment/Service, ArgoCD Application.
- `app-config.yaml` — wired to load the catalog entities and the template
  instead of the stock example data.

## What you need to do in WSL2 / VS Code

1. Move this folder to `/mnt/c/aws-projects/platform-engineering-backstage`.
2. `cd` into it and run `yarn install` (this was skipped here to avoid a
   long build in a throwaway container).
3. Fix the `github.com/project-slug` annotations in `catalog/entities/*.yaml`
   if any repo names differ from what's there.
4. Set up GitHub auth for the Scaffolder's `publish:github` action — you'll
   need a GitHub App or PAT with repo-creation scope, configured under
   `integrations.github` in `app-config.yaml` (not yet present — needs your
   token, so intentionally left out of this generated config).
5. `yarn start` — app on `localhost:3000`, backend on `localhost:7007`.
6. Verify the catalog loads all 7 entities, then click "Create" and confirm
   the FastAPI template form renders.

## Known gaps / next incidents to expect

- No GitHub integration token is configured yet — `publish:github` will fail
  until you add one. This is expected to be the first real debugging step,
  not a mistake in the generated files.
- The GitHub Actions workflow assumes a GitHub OIDC role (`AWS_ROLE_ARN`
  secret) already exists per repo — none has been created yet. Federated
  OIDC auth for GitHub Actions is new territory versus your prior projects'
  SSM/CLI-profile credential patterns; budget time to set up the IAM
  identity provider and trust policy once, then reuse per generated repo.
- ArgoCD must already be running on the target EKS cluster (reuse the one
  from `eks-fintech-platform`) — the generated `argocd-application.yaml`
  assumes an existing ArgoCD install, it does not install ArgoCD itself.
- TechDocs is intentionally not wired up yet — see ADR 0001.
