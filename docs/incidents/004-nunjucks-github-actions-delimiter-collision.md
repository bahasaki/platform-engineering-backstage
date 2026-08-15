# Incident 004: Generated GitHub Actions workflow is rejected as invalid YAML due to incorrect Nunjucks escaping

## Symptoms

After Incidents 001-003 were resolved, the scaffolder template ran fully
successfully (Fetch skeleton -> Publish to GitHub -> Register in the
catalog, all green), and a real repository (`bahasaki/hello-fastapi`) was
created with the generated files pushed to `main`. However, the repository's
GitHub Actions tab showed the auto-triggered workflow run had failed
immediately, before any job executed:

```
Invalid workflow file: .github/workflows/build-and-push.yaml#L1
(Line: 8, Col: 15): Unexpected symbol: '{{'. Located at position 18 within
expression: values.awsRegion {{ "
(Line: 9, Col: 23): Unexpected symbol: '{{'. Located at position 22 within
expression: values.ecrRepositoryUri {{ "
```

GitHub's workflow parser was rejecting the file outright — this happens
before any AWS/credentials-related logic runs, so it ruled out an AWS-side
problem.

## Investigation

- Root issue: `template.yaml`'s skeleton content
  (`.github/workflows/build-and-push.yaml`) needs to produce a file that
  contains **two different kinds** of `${{ ... }}` expressions in its final,
  rendered form:
  1. Values Backstage's Scaffolder should substitute *now*, at generation
     time (e.g. `values.awsRegion`, coming from the form the developer
     filled in).
  2. Literal GitHub Actions runtime expressions that must survive
     generation untouched, to be evaluated *later* by GitHub Actions itself
     (e.g. `secrets.AWS_ROLE_ARN`, `steps.ecr-login.outputs.registry`,
     `github.sha`).
- Both use identical `${{ }}` delimiter syntax, and Backstage's Nunjucks
  templater (`SecureTemplater.ts`) is configured to use exactly those same
  delimiters (`variableStart: '${{'`, `variableEnd: '}}'`) rather than
  Nunjucks' standard `{{ }}` — confirmed via Backstage's GitHub issue
  tracker, which documents this custom delimiter configuration.
- First fix attempt (documented as part of getting past this point) used
  `${{ "${{" }} X {{ "}}" }}` as an escaping technique for the GitHub
  Actions-native expressions, on the theory that wrapping the literal
  braces in Nunjucks string literals would emit them as plain text. This
  produced a file that passed the *first* validation error (the unescaped
  `values.awsRegion` lines, once those were corrected to plain
  `${{ values.awsRegion }}` unescaped substitutions) but failed on a new
  set of "Unexpected symbol '{{'" errors, this time on the lines that used
  the `"${{"`-based escaping technique itself. Inspecting the escaped lines
  showed the technique was not reliably producing a clean, standalone
  `${{ ... }}` pair in the rendered output.

## Root Cause

Two distinct mistakes, found and corrected in sequence:

1. Lines that needed Scaffolder-time substitution (`values.awsRegion`,
   `values.ecrRepositoryUri`) were incorrectly wrapped in the same
   escape-string technique meant for GitHub Actions-native expressions,
   producing literal, unresolved `{{` / `}}` fragments in the output
   instead of the intended substituted value.
2. The `${{ "${{" }} X {{ "}}" }}` escaping technique used for genuinely
   GitHub Actions-native expressions (`secrets.*`, `steps.*`, `github.sha`)
   does not reliably reproduce a valid `${{ X }}` pair in Backstage's
   Nunjucks configuration — the string-literal-based escape is not the
   supported mechanism for this templating engine.

## Fix

- Corrected the Scaffolder-time substitutions to be plain, unescaped
  Nunjucks expressions, since these values should be resolved during
  generation:

  ```yaml
  env:
    AWS_REGION: ${{ values.awsRegion }}
    ECR_REPOSITORY_URI: ${{ values.ecrRepositoryUri }}
  ```

- Replaced the `"${{"`-based escaping technique with Nunjucks' built-in
  `{% raw %}` / `{% endraw %}` block tag, which disables template parsing
  entirely for its contents, guaranteeing the enclosed GitHub Actions
  expressions pass through byte-for-byte:

  ```yaml
  - name: Configure AWS credentials
    uses: aws-actions/configure-aws-credentials@v4
    with:
  {% raw %}
      role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
      aws-region: ${{ env.AWS_REGION }}
  {% endraw %}
  ```

  Applied the same `{% raw %}` wrapping to every other GitHub
  Actions-native expression in the file (`steps.ecr-login.outputs.registry`,
  `github.sha`, `steps.build-image.outputs.image`).

## Verification

Deleted the previous test repository, restarted `yarn start`, and re-ran the
template from scratch. The generated repository's Actions tab showed the
workflow file was now accepted as valid YAML — the job (`build-and-push`)
actually started and ran for several seconds before failing, with a
completely different, expected error:

```
Credentials could not be loaded, please check your action inputs:
Could not load credentials from any providers
```

This confirmed the YAML/templating layer was now correct: the workflow
reached the point of attempting AWS authentication, which is expected to
fail until an AWS OIDC role and the corresponding `AWS_ROLE_ARN` repository
secret are configured (tracked separately, not yet done as of this
incident).

## Prevention

- When a Backstage template's skeleton content needs to contain literal
  target-platform template syntax that collides with Nunjucks'
  `${{ }}` delimiters (GitHub Actions being the clearest example, since it
  uses the identical syntax), default to `{% raw %}` / `{% endraw %}`
  blocks rather than ad hoc string-literal escaping tricks — it is the
  documented, supported mechanism for this exact situation.
- Keep Scaffolder-time substitutions and target-platform-native expressions
  visually and structurally separate in the template source (here: grouped
  under distinct `{% raw %}` blocks) so it's obvious at a glance which
  `${{ }}` expressions are meant to resolve now vs. later.
- A file that fails GitHub's workflow parser entirely (`Invalid workflow
  file`) is a strong signal to check templating-layer correctness before
  looking at anything downstream (credentials, AWS config, etc.) — the
  error location and "Unexpected symbol" phrasing pointed directly at the
  templating mechanism, not at application logic.

## Lessons Learned

This incident is a good illustration of iterating toward a fix without
fully understanding the underlying mechanism first: the initial "fix" (the
`"${{"` string-literal escape) resolved the reported symptom on some lines
while introducing the identical failure mode on others, because it treated
the escaping problem as line-specific rather than understanding *why* the
delimiter collision was occurring in the first place. A short check of
Backstage's own Nunjucks configuration (confirming it re-uses GitHub
Actions' exact `${{ }}` delimiters) would have pointed directly at
`{% raw %}` as the correct, supported answer before attempting an ad hoc
workaround. When a fix only partially resolves a symptom, that is itself a
signal that the mental model of the root cause is still incomplete, not
just that more of the same fix needs to be applied elsewhere.
