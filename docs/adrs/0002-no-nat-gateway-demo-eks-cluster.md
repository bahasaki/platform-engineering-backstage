# ADR 0002: No NAT Gateway for the demo EKS cluster

## Context

The EKS cluster in `infra/eks/` exists solely to validate the final leg of
the Scaffolder-generated GitOps pipeline (K8s manifest -> ArgoCD -> EKS ->
Grafana). It is stood up, verified, documented, and destroyed within a
single working session — it is not a long-lived environment.

A production-grade VPC for EKS nodes typically places worker nodes in
private subnets behind a NAT Gateway, so nodes have no public IP and
inbound access is fully blocked while still allowing outbound internet
access (package updates, pulling images, calling AWS APIs). This is the
pattern already used in `aws-rds-fintech-ledger`'s three-tier VPC
(`terraform/vpc.tf`, confirmed to include `aws_nat_gateway`).

## Decision

The demo EKS cluster's VPC uses **public subnets only, with no NAT
Gateway**. Nodes receive public IPs and reach the internet directly via the
Internet Gateway.

## Alternatives considered

1. **Private subnets + NAT Gateway (the `aws-rds-fintech-ledger` pattern).**
   Rejected for this specific cluster — a NAT Gateway costs roughly
   $0.045/hr plus data processing charges, on top of the EKS control plane
   ($0.10/hr) and node group cost. For a cluster whose entire lifecycle is
   a few hours, spent purely on validating a self-service pipeline, this
   adds cost without adding anything to what's being demonstrated (the
   GitOps flow, not network isolation).
2. **Private subnets + NAT instance (cheaper than a NAT Gateway).**
   Rejected as unnecessary complexity for a resource that will be
   `terraform destroy`'d the same session it's created.

## Consequences

- This is *not* the pattern to use for a production cluster with genuinely
  sensitive workloads — the tradeoff only makes sense because of this
  cluster's deliberately short, single-session lifecycle.
- `aws-rds-fintech-ledger` remains the portfolio reference for the
  production-appropriate three-tier VPC / NAT Gateway pattern; this
  decision is explicitly scoped to the demo EKS cluster only, not a
  reversal of that earlier design choice.
