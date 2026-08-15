# Incident 007: ArgoCD Application stuck at `Unknown` sync status — private repository requires explicit credentials

## Symptoms

After applying the Scaffolder-generated `k8s/argocd-application.yaml` to
the cluster (`kubectl apply -f k8s/argocd-application.yaml`), the
Application object was created and visible via
`kubectl get applications -n argocd`, but its `SYNC STATUS` stayed at
`Unknown` indefinitely (never transitioning to `Synced` or even
`OutOfSync`), while `HEALTH STATUS` showed `Healthy`.

## Investigation

- `kubectl describe application hello-fastapi -n argocd` surfaced the
  actual condition under `Status -> Conditions`:

  ```
  Message: Failed to load target state: failed to generate manifest for
  source 1 of 1: rpc error: code = Unknown desc = failed to list refs:
  authentication required: Repository not found.
  Type: ComparisonError
  ```

- The Application's `Health: Healthy` status was misleading in isolation —
  it reflects the health of resources ArgoCD has *already* deployed (none,
  in this case, since it never got past comparing state), not whether the
  Application is functioning as a whole. The real signal was in
  `Sync.Status: Unknown` combined with the `ComparisonError` condition.
- `hello-fastapi` is a private GitHub repository (confirmed via the lock
  icon on its GitHub page). ArgoCD, by default, attempts anonymous,
  unauthenticated git access when no repository credentials are registered
  for a given repo URL. GitHub returns "Repository not found" rather than
  a permissions-denied error for unauthenticated requests to private repos
  — a deliberate GitHub behavior to avoid confirming the existence of
  private repositories to unauthorized callers, which made the error
  message initially read as if the repo URL itself might be wrong (it
  wasn't).

## Root Cause

ArgoCD had no stored credentials for `https://github.com/bahasaki/hello-fastapi.git`,
so its attempt to clone/list refs from the repository was rejected by
GitHub as an anonymous request to a private repo.

## Fix

Registered a repository credential secret in the `argocd` namespace,
following ArgoCD's convention for repository secrets (a `kubernetes.io`
generic Secret labeled `argocd.argoproj.io/secret-type=repository`):

```bash
kubectl create secret generic hello-fastapi-repo \
  --namespace argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/bahasaki/hello-fastapi.git \
  --from-literal=username=bahasaki \
  --from-literal=password=<github-pat> \
  --dry-run=client -o yaml \
  | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
  | kubectl apply -f -
```

Used the same fine-grained GitHub PAT already configured for Backstage's
own `publish:github` integration, since it already has the necessary repo
access. Triggered a hard refresh on the Application to force ArgoCD to
re-attempt the comparison immediately rather than waiting for its next
polling interval:

```bash
kubectl patch application hello-fastapi -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

## Verification

`kubectl get applications -n argocd` showed `SYNC STATUS: Synced` within
seconds of the refresh. `kubectl get pods -n default` confirmed two
`hello-fastapi` pods reached `1/1 Running`. Port-forwarding to the service
and curling `/healthz` returned `{"status":"ok","service":"hello-fastapi"}`,
confirming the deployed application was not just running but actually
serving traffic correctly.

## Prevention

- When a Scaffolder template (or any GitOps tooling) generates services
  into private repositories by default, plan for repository credential
  registration as an explicit, expected setup step for ArgoCD — not an
  edge case discovered after the fact. A one-time `AppProject`-level
  credential template (matching a URL pattern like
  `https://github.com/bahasaki/*`) would let every future
  Scaffolder-generated repo authenticate automatically, rather than
  requiring a new secret per generated service.
- When an ArgoCD Application's `Health` status looks fine but `Sync`
  status is stuck, don't read `Health: Healthy` as "this is basically
  working" — check `kubectl describe application` for `Status.Conditions`
  first; that's where the actionable error actually lives.
- A "not found" error from a git host on an operation using no credentials
  is a strong hint to check repository visibility before assuming the URL,
  branch, or path is wrong.

## Lessons Learned

This continues a theme from earlier incidents in this project (002, 005):
authentication-shaped failures that surface as something else entirely —
here, a generic `ComparisonError` and a "repository not found" message that
initially reads like a wrong URL rather than a missing credential. As with
the earlier GitHub token incident, the fix was straightforward once the
actual condition text was read carefully via `kubectl describe`, rather
than inferred from the higher-level `SYNC STATUS: Unknown` summary alone.
