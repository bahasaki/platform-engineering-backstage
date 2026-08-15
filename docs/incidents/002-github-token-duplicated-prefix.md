# Incident 002: `publish:github` fails with "Bad credentials" despite a configured token

## Symptoms

After fixing Incident 001, re-running the template got further (the schema
validation error was gone) but failed on the same "Publish to GitHub" step
with:

```
HttpError: Bad credentials - https://docs.github.com/rest
```

The task logs showed the failure came from an authenticated GitHub API call
via Octokit, not from a missing configuration key.

## Investigation

- Confirmed `app-config.local.yaml` existed in the project root (not
  misplaced under `packages/`) and contained a `token:` value under
  `integrations.github`.
- Since the same GitHub account had a working PAT used minutes earlier for
  a manual `git push` via `gh`, the token itself was known to be capable of
  authenticating — the question was whether the *exact string* stored in
  `app-config.local.yaml` was correct.
- Inspected the file directly with `cat app-config.local.yaml` (rather than
  trusting "the token is in there") and found the value was:

  ```
  token: github_pat_github_pat_<rest of token>
  ```

  The `github_pat_` prefix was duplicated at the start of the token string.

## Root Cause

When the token was pasted into `app-config.local.yaml`, the `github_pat_`
prefix was entered twice — likely from copying the token value on top of a
placeholder string that already included the prefix
(`github_pat_ВСТАВЬ_СВОЙ_ТОКЕН_СЮДА`), rather than replacing the full
placeholder. GitHub does not recognize a token string with a duplicated
prefix, and the API correctly rejects it as invalid credentials rather than
a malformed request.

## Fix

Edited `app-config.local.yaml` to remove the duplicate `github_pat_` prefix,
leaving a single, correctly-formatted token string.

## Verification

Since `app-config*.yaml` files are read once at backend startup (unlike
`template.yaml`, which is re-read per catalog refresh), restarted
`yarn start` fully rather than relying on hot-reload. After the restart,
re-ran the template from scratch: "Publish to GitHub" completed in 5
seconds, followed by a successful "Register in the catalog" step. The new
repository `bahasaki/hello-fastapi` was confirmed to exist on GitHub with
the scaffolded files, and the component appeared in the Backstage catalog
with the correct owner, system, and `dependsOn` relation to
`eks-fintech-cluster`.

## Prevention

- When pasting a secret into a config file that started from a placeholder
  value, select and delete the entire placeholder first rather than pasting
  over part of it — partial overwrites that preserve a shared prefix/suffix
  are easy to miss on visual inspection, especially with long token strings
  that are usually not read character-by-character.
- When a credential-looking error appears, verify the *literal* stored
  value directly (`cat` the config file) before assuming the credential is
  simply missing, expired, or scoped incorrectly. "The token is configured"
  and "the token is configured correctly" are different claims.
- `app-config.local.yaml` changes require a full backend restart to take
  effect — this is a different reload behavior than `template.yaml` changes
  (Incident 001) and is easy to conflate when debugging back-to-back
  failures on the same task.

## Lessons Learned

Two back-to-back failures on the same scaffolder step, from unrelated root
causes, is a good reminder not to assume a fix "didn't work" just because
the same step failed again — the *error message* changing (schema error to
credential error) was the actual signal that the first fix succeeded. Also
reinforces a general debugging habit: for anything credential-related,
inspect the literal stored value rather than only checking presence/absence.
