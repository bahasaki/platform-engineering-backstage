# ${{ values.name }}

${{ values.description }}

Scaffolded via the `fastapi-service-eks` Backstage template.

## Pipeline

```
git push main
  -> GitHub Actions (.github/workflows/build-and-push.yaml)
  -> docker build + push to ECR (${{ values.ecrRepositoryUri }})
  -> commit updated image tag to k8s/deployment.yaml
  -> ArgoCD (k8s/argocd-application.yaml) detects the change, auto-syncs
  -> EKS namespace: ${{ values.namespace }}
```

## Local development

```bash
cd app
pip install -r requirements.txt
uvicorn main:app --reload
```

## First-time setup after generation

These steps assume the one-time platform setup (GitHub OIDC provider, IAM
role, ArgoCD installed on the target cluster) already exists. If this is
the *first* service ever generated from this template, that setup needs to
happen once, platform-wide — ask whoever owns the Backstage instance.

1. **Create an ECR repository** named `${{ values.name }}` if one doesn't
   already exist — the GitHub Actions workflow pushes to it but does not
   create it.
2. **Set the `AWS_ROLE_ARN` repository secret** to the ARN of the shared
   GitHub OIDC role. Note: if this repo was just created, GitHub may issue
   OIDC tokens using the newer immutable subject claim format
   (`repo:org@id/repo@id:...`) rather than the classic format
   (`repo:org/repo:...`). If the workflow fails with
   `Not authorized to perform sts:AssumeRoleWithWebIdentity` even though
   the secret and role look correct, check whether the IAM role's trust
   policy matches both formats.
3. **Register this service with ArgoCD.** If this repository is private
   (the default for `publish:github`), ArgoCD needs explicit credentials
   for it — applying `k8s/argocd-application.yaml` alone is not enough:

   ```bash
   kubectl apply -f k8s/argocd-application.yaml

   kubectl create secret generic ${{ values.name }}-repo \
     --namespace argocd \
     --from-literal=type=git \
     --from-literal=url=<this-repo-url> \
     --from-literal=username=<github-username> \
     --from-literal=password=<github-pat> \
     --dry-run=client -o yaml \
     | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
     | kubectl apply -f -
   ```

   Without this, `kubectl get applications -n argocd` will show
   `SYNC STATUS: Unknown` rather than `Synced`.
4. Push to `main` to trigger the first build.

## Verifying it actually worked

A green GitHub Actions run and `SYNC STATUS: Synced` confirm the pipeline
ran, not that the service is functioning correctly. Confirm the deployed
pod is actually serving traffic before considering this done:

```bash
kubectl get pods -n ${{ values.namespace }}          # expect 1/1 Running
kubectl port-forward svc/${{ values.name }} 8080:80 -n ${{ values.namespace }}
curl http://localhost:8080/healthz
```

