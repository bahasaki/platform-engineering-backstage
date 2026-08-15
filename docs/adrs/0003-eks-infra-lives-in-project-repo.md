# ADR 0003: Demo EKS infrastructure lives inside platform-engineering-backstage, not as a separate repo

## Context

The final leg of the Scaffolder-generated pipeline (K8s manifest -> ArgoCD
-> EKS -> Grafana) needs a real, live EKS cluster to deploy into. No
existing cluster from prior portfolio projects (e.g. `eks-fintech-platform`)
was available — it had already been destroyed following this portfolio's
standard cost-discipline practice of `terraform destroy` after each demo.

A new EKS cluster's supporting Terraform therefore needed to be written,
and a location for it decided: either inside this repository
(`platform-engineering-backstage/infra/eks/`) or as its own standalone
repository.

## Decision

The Terraform for the demo EKS cluster lives at `infra/eks/` inside
`platform-engineering-backstage`, not in a separate repository.

## Alternatives considered

1. **Separate repository (e.g. a new `eks-fintech-platform`-style repo).**
   Rejected — this cluster's only purpose is to give the Backstage
   Scaffolder pipeline somewhere real to deploy to, so its own catalog
   entry, ADRs, and incidents can validate the "developer can self-service
   provision a service end-to-end" claim this project exists to
   demonstrate. Splitting it into an unrelated repository would create an
   implicit, unexplained dependency between two repos with no clear
   narrative link, adding cognitive overhead for a reviewer (or an
   interviewer) without adding any real separation of concerns.
2. **Reuse the existing `eks-fintech-platform` cluster, if it were still
   live.** This would have been the preferred option had the cluster still
   existed — it's a more realistic simulation of "deploying to a shared
   platform team's cluster." Not available here since the cluster had
   already been destroyed as part of normal cost-discipline practice.

## Consequences

- `infra/eks/` is explicitly scoped as *demo infrastructure supporting this
  project's validation*, not a standalone portfolio deliverable in its own
  right — it does not aim to demonstrate the same breadth of EKS-specific
  patterns (HPA, Pod Anti-Affinity, full observability stack) that
  `eks-fintech-platform` already covers elsewhere in the portfolio. See
  ADR 0002 for the specific tradeoff (no NAT Gateway) that follows from
  this cluster's short, single-session lifecycle.
- This mirrors an existing pattern in the portfolio: `aws-rds-fintech-ledger`
  keeps its VPC/networking Terraform inside its own repository rather than
  in a shared infrastructure repo, because that Terraform exists to serve
  that project's specific demonstration, not as reusable infrastructure in
  its own right.
