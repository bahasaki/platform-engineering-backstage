# Incident 001: Scaffolder `publish:github` step fails with schema validation error

## Symptoms

Running the `fastapi-service-eks` template through to completion failed on
the second step ("Publish to GitHub") with:

```
Error: Invalid input passed to action publish:github, instance is not
allowed to have the additional property "allowedHosts"
```

The first step ("Fetch skeleton") completed successfully in ~2 seconds; the
publish step failed immediately (0 seconds), before any GitHub API call was
made.

## Investigation

- The `Fetch skeleton` step succeeding first confirmed the Nunjucks template
  rendering and the `fetch:template` action itself were fine — the problem
  was isolated to the `publish:github` step's input.
- Compared the `template.yaml`'s `publish:github` step input against the
  action's current JSON schema. The step was passing an `allowedHosts` key
  directly into the action input:

  ```yaml
  - id: publish
    name: Publish to GitHub
    action: publish:github
    input:
      allowedHosts: ['github.com']   # not a valid input for this action
      description: ${{ parameters.description }}
      repoUrl: ${{ parameters.repoUrl }}
      defaultBranch: main
  ```

- `allowedHosts` is a valid option for the `RepoUrlPicker` UI field (under
  `ui:options.allowedHosts` in the `parameters` section, which restricts
  which git hosts the user can pick from in the form) — but it is not a
  recognized input property for the `publish:github` action itself in the
  installed `@backstage/plugin-scaffolder-backend` version. The two
  `allowedHosts` settings serve different layers (UI restriction vs. action
  input) and are easy to conflate.

## Root Cause

Copy/adaptation error when writing the template: `allowedHosts` belongs on
the `RepoUrlPicker` field's `ui:options`, not on the `publish:github`
action's `input`. The scaffolder backend's strict schema validation
(`additionalProperties` disallowed) rejected the unexpected key before
attempting any GitHub API call.

## Fix

Removed `allowedHosts` from the `publish:github` step's `input` block,
leaving only the properties the action actually accepts:

```yaml
- id: publish
  name: Publish to GitHub
  action: publish:github
  input:
    description: ${{ parameters.description }}
    repoUrl: ${{ parameters.repoUrl }}
    defaultBranch: main
```

The correct `allowedHosts` restriction remains in place on the
`RepoUrlPicker` field under `parameters`, where it belongs.

## Verification

Re-ran the template after restarting `yarn start` (see Prevention below) —
the "Publish to GitHub" step's schema validation error was gone; the task
proceeded to a different, unrelated error (credential issue, see
Incident 002).

## Prevention

- When adapting Backstage template examples, treat action `input` schemas
  as authoritative and distinct from `ui:options` on `parameters` — an
  option name matching on both layers does not mean it applies to both.
- Backend template files (`template.yaml`) are not always hot-reloaded by a
  running `yarn start` process. After editing a template, a full restart
  (`Ctrl+C`, then `yarn start` again) is the reliable way to confirm the
  change took effect, rather than trusting that the next task run will pick
  up an on-disk edit.

## Lessons Learned

Backstage's scaffolder actions validate input strictly against their JSON
schema and fail fast with a clear "additional property" error — this made
diagnosis fast once the log was read carefully. The bigger time cost in
this incident was not the fix itself but confirming *whether* the fix had
actually been applied, since a stale backend process re-produced the exact
same error message after an on-disk edit. Verifying a template.yaml change
requires restarting the backend, not just re-submitting the form.
