# Incident 006: EKS managed node group stuck `Creating` for 30+ minutes, fails with Free Tier instance type restriction

## Symptoms

`terraform apply` for the demo EKS cluster succeeded in creating the VPC,
IAM roles, and the EKS control plane (`aws_eks_cluster.this` reached
`Active` quickly), but `aws_eks_node_group.default` stayed in a
`Still creating...` state for over 30 minutes with the EKS console showing
0 nodes and the node group status stuck on `Creating`. Terraform eventually
timed out with:

```
Error: waiting for EKS Node Group (backstage-demo-eks:backstage-demo-eks-default)
create: unexpected state 'CREATE_FAILED', wanted target 'ACTIVE'. last error:
AsgInstanceLaunchFailures: Could not launch On-Demand Instances.
InvalidParameterCombination - The specified instance type is not eligible
for Free Tier. For a list of Free Tier instance types, run
'describe-instance-types' with the filter 'free-tier-eligible=true'.
Launching EC2 instance failed.
```

## Investigation

- The EKS cluster itself being `Active` while the node group stayed at 0
  nodes ruled out networking/VPC/IAM trust policy issues — those would have
  blocked the cluster from reaching `Active` in the first place, not just
  the node group's underlying EC2 instances.
- Checked the underlying Auto Scaling Group's Activity History directly in
  the EC2 console (Auto Scaling Groups -> the ASG backing the node group ->
  Activity tab), rather than waiting on Terraform's polling loop, and found
  12 consecutive `Failed` launch attempts, all with the identical
  `InvalidParameterCombination` / Free Tier error.
- Confirmed via the EC2 console's instance-type picker (which labels each
  type "Free tier eligible" or not) that the account's free-tier-eligible
  instance list included `t3.micro`, `t3.small`, `c7i-flex.large`, and
  `m7i-flex.large` — but not `t3.medium`, which the node group's
  `instance_types` variable had defaulted to.

## Root Cause

The AWS account is restricted to launching only Free Tier-eligible EC2
instance types. `t3.medium` — a reasonable, common choice for a small
Kubernetes node group and the value used as this module's default — is not
Free Tier eligible on this account. Every launch attempt by the underlying
Auto Scaling Group was rejected at the EC2 API level before an instance
could even start booting, so there was nothing for `kubectl` or the EKS
control plane to report — the failure was invisible from the Kubernetes
side entirely and only visible in the ASG's own activity history.

## Fix

Changed `node_instance_type` in `variables.tf` from `t3.medium` to
`t3.small` (2 vCPU, 2 GiB memory, confirmed Free Tier eligible on this
account) and re-ran `terraform apply`. The node group created successfully
in under 2 minutes — a striking contrast to the 30+ minute stall on the
disallowed instance type, since a valid instance type launches and joins
the cluster almost immediately once the underlying EC2 capacity request
succeeds.

## Verification

`terraform apply` completed with `1 added, 0 changed, 1 destroyed` (the
failed node group was replaced). `aws eks update-kubeconfig` followed by
`kubectl get nodes` showed both nodes in `Ready` status within ~3 minutes
of the node group's creation.

## Prevention

- Don't assume a "reasonable default" instance type (e.g. `t3.medium`,
  commonly used in tutorials and other portfolio projects) is available on
  every account — Free Tier restrictions are account-specific and can
  silently reject an otherwise valid Terraform configuration at the AWS API
  level, not the Terraform/HCL level, so `terraform validate` and
  `terraform plan` give no warning.
- When a managed resource (EKS node group, ASG, etc.) stalls in a
  "creating" state with no forward progress and no error surfaced through
  the primary tool being used (Terraform, kubectl), check the underlying
  cloud-native resource's own activity/event log directly — the ASG
  Activity History surfaced this error immediately and clearly, well before
  Terraform's own polling timeout would have.
- Before writing infrastructure code that provisions EC2 capacity on an
  account with unknown Free Tier status, check
  `aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true`
  (or the EC2 console's instance-type picker, which labels eligibility
  directly) rather than assuming a commonly-used instance type will work.

## Lessons Learned

This is a good example of a failure that is invisible from the layer you're
actively debugging: Terraform kept reporting a generic "still creating"
with no error for 30 minutes, and `kubectl` had nothing to show since no
node ever registered. The actual, specific error only existed one layer
down, in the Auto Scaling Group's own activity history — a reminder that
when a managed AWS resource wraps another AWS resource (here, an EKS node
group wraps an ASG wraps EC2 instances), the most useful error message is
often not surfaced by the top-level tool at all, and it's worth going
directly to the underlying resource's console/logs rather than waiting out
a timeout on the wrapper.
