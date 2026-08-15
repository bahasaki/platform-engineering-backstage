# Incident 005: `sts:AssumeRoleWithWebIdentity` rejected despite correct OIDC provider, role ARN, and secret

## Symptoms

With the AWS OIDC Identity Provider created, the `github-actions-ecr-push-role`
IAM role created (trust policy scoped to `repo:bahasaki/*:*`, permissions
policy scoped to ECR push/pull), and the `AWS_ROLE_ARN` repository secret set
correctly, re-running the `hello-fastapi` GitHub Actions workflow still
failed at the "Configure AWS credentials" step:

```
Could not assume role with OIDC: Not authorized to perform
sts:AssumeRoleWithWebIdentity
```

At this point every piece that had failed in earlier attempts (missing
credentials, malformed YAML) was confirmed correct: the secret existed and
was non-empty, `permissions: id-token: write` was present in the generated
workflow file, and the role's trust policy referenced the correct OIDC
provider ARN and audience.

## Investigation

- Ruled out the workflow file itself: `permissions.id-token: write` and
  `permissions.contents: write` were both present and correctly indented at
  the job level, confirmed by viewing the rendered file directly on GitHub.
- Ruled out the secret: the `AWS_ROLE_ARN` repository secret had been set
  and the workflow log showed the role-assumption attempt was actually made
  (not skipped or empty), it was just rejected.
- Searched for this exact error message plus "GitHub Actions OIDC" and
  found multiple independent sources describing a GitHub platform change:
  starting **July 15, 2026**, GitHub began issuing OIDC tokens with a new,
  immutable `sub` (subject) claim format for newly created repositories.
  - Classic (mutable) format: `repo:<org>/<repo>:ref:refs/heads/main`
  - New (immutable) format: `repo:<org>@<org_id>/<repo>@<repo_id>:ref:refs/heads/main`
- `hello-fastapi` was created on August 15, 2026 — a full month after this
  change — meaning it almost certainly received tokens in the new format.
  The trust policy's `StringLike` condition
  (`token.actions.githubusercontent.com:sub`: `"repo:bahasaki/*:*"`) matches
  the classic format's prefix but not the new format, since the new format
  inserts `@<org_id>` immediately after the org name, before the `/`.

## Root Cause

The IAM trust policy's `sub` condition was written assuming the classic,
mutable GitHub OIDC subject claim format. GitHub's July 2026 rollout of
immutable subject claims (an OIDC-spec-compliance change to prevent subject
reuse when org/repo names are recycled) changed the actual token contents
for newly created repositories, without changing the error surfaced by AWS
(`Not authorized to perform sts:AssumeRoleWithWebIdentity`) — the failure
looks identical to a simple trust policy misconfiguration, giving no direct
signal that the claim *format itself* had changed platform-side.

## Fix

Extended the trust policy's `StringLike` condition to match both the
classic and immutable subject claim formats:

```json
"StringLike": {
  "token.actions.githubusercontent.com:sub": [
    "repo:bahasaki/*:*",
    "repo:bahasaki@*:*"
  ]
}
```

This keeps the role usable for any existing repositories still on the
classic format while covering all new repositories created under the
immutable-ID scheme, without needing to know or hardcode the specific
numeric org ID.

## Verification

Re-ran the failed workflow via "Re-run failed jobs" (same commit, no new
push needed). The "Configure AWS credentials" step succeeded, followed by
a successful ECR login, `docker build`, and `docker push`. Confirmed
directly in the ECR console that a new image (tagged with the workflow's
commit SHA, ~59 MB) existed in the `hello-fastapi` repository, with a
matching digest and creation timestamp.

## Prevention

- When an IAM OIDC trust policy is written for GitHub Actions, prefer
  matching on both the classic and immutable `sub` claim formats from the
  start, rather than adding the second pattern reactively after a failure —
  the immutable format is the default going forward for all new
  repositories.
- `Not authorized to perform sts:AssumeRoleWithWebIdentity` is a
  deliberately generic AWS error that does not distinguish between "role
  doesn't trust this identity provider," "condition doesn't match," or
  "token format changed upstream." When every locally-controlled piece
  (role ARN, secret, provider, workflow permissions) checks out, the next
  place to look is whether the *shape* of the external token itself has
  changed — not just whether the configured values are individually
  correct.
- For faster diagnosis in a future incident, add a debug step that decodes
  and prints the actual OIDC token's `sub` claim before the credentials
  step, to compare directly against the trust policy rather than
  inferring the claim format from documentation or search results.

## Lessons Learned

This incident is a good example of a failure whose root cause was neither
in the code being written nor in a documented AWS/GitHub misconfiguration
pattern, but in a recent, easy-to-miss platform-level change on GitHub's
side that silently altered the shape of a token this project already
depended on. Every artifact under direct control (trust policy JSON,
workflow YAML, the secret's value) was individually correct by the
standards that existed before July 2026 — the mismatch was purely temporal.
Searching for the exact error message surfaced multiple recent, dated
sources describing the same change, which is what made the fix findable at
all rather than requiring a CloudTrail-based trial-and-error investigation
of the rejected token's actual claims.
