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

1. Apply `k8s/argocd-application.yaml` once to register this service with the
   shared ArgoCD instance: `kubectl apply -f k8s/argocd-application.yaml`
2. Set the `AWS_ROLE_ARN` repository secret (GitHub OIDC role permitted to
   push to `${{ values.ecrRepositoryUri }}`).
3. Push to `main` to trigger the first build.
