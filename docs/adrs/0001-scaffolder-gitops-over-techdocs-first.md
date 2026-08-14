# ADR 0001: Scaffolder + GitOps is the core deliverable, not TechDocs

## Context

The initial plan for this project treated Backstage's three pillars
(Software Catalog, TechDocs, Software Templates) as roughly equal-weight
phases, to be built in that order. That plan optimizes for "I stood up
Backstage" — a tool-familiarity demo.

The actual goal of a Platform Engineering project is different: a developer
should be able to provision a new, fully wired service through self-service,
without a platform engineer doing it by hand. That means the interesting
work is the pipeline:

```
Backstage -> Create Service -> Git repository -> GitHub Actions -> Docker
-> ECR -> Kubernetes manifest -> ArgoCD -> EKS -> Grafana
```

## Decision

Reprioritize the project:

- **High priority:** Software Catalog (minimum needed to register services),
  Scaffolder template (`fastapi-service-eks`), and the GitOps chain
  (GitHub Actions -> ECR -> k8s manifest -> ArgoCD -> EKS).
- **Low priority / done last:** TechDocs. It adds documentation
  browsing but does not touch the "developer can self-service provision a
  service" outcome. It is deferred to the end and cut entirely if time runs
  short.

## Alternatives considered

1. **Build all three pillars in parallel, evenly.** Rejected — spreads
   effort thin and the catalog/TechDocs work is largely mechanical
   (register existing repos, point at existing `docs/` folders), while the
   Scaffolder + GitOps chain is where the actual platform engineering
   thinking (and likely incidents worth documenting) will happen.
2. **Skip the Catalog entirely and go straight to Scaffolder.** Rejected —
   the Scaffolder's `catalog:register` step needs a working catalog to
   register into, and the portfolio narrative benefits from having all 7
   existing projects visible as one system.

## Consequences

- The demo narrative for interviews becomes: "a developer fills out a form
  in Backstage, and two minutes later has a running service on EKS with a
  Grafana dashboard" — not "I have a documentation portal."
- TechDocs setup (MkDocs config, `docs/` wiring) is deferred; if cut, the
  existing `docs/` folders in each project repo remain the source of truth,
  just not rendered inside Backstage.
- The GitHub Actions workflow needs an AWS OIDC role
  (`AWS_ROLE_ARN` secret) configured per generated repo — this is a new
  piece of AWS IAM work not present in earlier portfolio projects
  (previous projects used long-lived credentials via SSM Parameter Store
  or local AWS CLI profiles, not GitHub OIDC federation).
