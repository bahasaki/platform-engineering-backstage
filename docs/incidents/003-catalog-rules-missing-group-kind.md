# Incident 003: `fintech-portfolio` System shows "Entity not found" despite valid catalog file

## Symptoms

After successfully registering `hello-fastapi` in the catalog (see
Incident 002's resolution), its detail page showed a warning banner:

```
This entity has relations to other entities, which can't be found in the
catalog. Entities not found are: group:default/bahasaki,
system:default/fintech-portfolio
```

Navigating directly to `/catalog/default/system/fintech-portfolio` returned:

```
Entity not found
There is no system with the requested kind, namespace, and name.
```

This was despite `catalog/entities/system.yaml` being present on disk with
valid YAML defining both the `fintech-portfolio` System and the `bahasaki`
Group, and despite that file being listed under `catalog.locations` in
`app-config.yaml`.

## Investigation

- Verified the file's literal content with `cat catalog/entities/system.yaml`
  — confirmed it was syntactically valid YAML with both entities correctly
  defined (no corruption, no empty file).
- Verified `app-config.yaml`'s `catalog.locations` list included the correct
  relative path to `system.yaml` and that the path pattern matched the
  other 6 entity files, which *were* loading successfully.
- Compared `system.yaml` against the other entity files: `system.yaml` is
  the only file in the catalog that defines a `Group` entity (all others
  define only `Component` or `System`/`Resource`).
- Checked `app-config.yaml`'s `catalog.rules` (a global filter applied to
  all locations that don't define their own override):

  ```yaml
  catalog:
    rules:
      - allow: [Component, System, API, Resource, Location]
  ```

  `Group` was not in the allowed kinds list.

## Root Cause

The global `catalog.rules` allow-list did not include `Group` (or `User`).
Since `system.yaml` is a multi-document YAML file containing both a
`System` and a `Group` entity under one `type: file` location entry (no
location-specific `rules` override), the disallowed `Group` document caused
the entire location's processing to fail rather than silently loading only
the `System` half. The `System` entity being valid YAML was not sufficient
— it was rejected as a side effect of being co-located with a disallowed
kind under the same catalog location.

## Fix

Added `Group` and `User` to the global `catalog.rules` allow-list in
`app-config.yaml`:

```yaml
catalog:
  rules:
    - allow: [Component, System, API, Resource, Location, Group, User]
```

`User` was added preemptively — `examples/org.yaml` (left in place from the
`create-app` scaffold) defines `User` entities under a separate location
with its own `rules: - allow: [User, Group]` override, but the global rule
still applies as a baseline and the same failure mode was anticipated there.

## Verification

Restarted `yarn start` (required for `app-config.yaml` changes) and
navigated to `/catalog/default/system/fintech-portfolio` — the page now
renders fully: description, owner (`bahasaki`, now a working link instead
of a broken reference), tags, "Has components" listing all 6 pre-existing
components, and a Relations graph showing `bahasaki --ownerOf/ownedBy-->
fintech-portfolio --hasPart/partOf--> [each component]`. The warning banner
on `hello-fastapi`'s page was also gone.

## Prevention

- When a catalog location defines multiple entity kinds in one multi-document
  YAML file, remember that `catalog.rules` filtering applies per-location,
  not per-document — a disallowed kind anywhere in the file can affect
  processing of the whole location, not just silently skip that one entity.
- When introducing a new entity `kind` to the catalog for the first time
  (here: `Group`, which hadn't been used in any of the other 6 project
  files), explicitly check `catalog.rules` before assuming the entity will
  load just because the YAML is valid and the location path is correct.
- `Location not found` and `Entity not found` errors that reference a
  target that "should" exist are worth checking against `catalog.rules`
  early — the file being syntactically fine can rule out YAML corruption
  quickly, redirecting investigation toward configuration-level filtering
  instead of the file's contents.

## Lessons Learned

This is a good example of a class of Backstage failure mode noted
elsewhere in this portfolio: Kubernetes/Prometheus-style *silent
non-matching* rather than an explicit error pointing at the exact problem.
The `Entity not found` message pointed at the symptom (the System doesn't
exist) without hinting at the mechanism (a sibling document in the same
file was filtered out by a global rule). Confirming the file's literal
on-disk content first, then working outward to the configuration that
governs how that file is processed, was the effective order of
investigation here — checking "is the input correct" before "is the
processing configured correctly" avoided chasing a YAML-corruption theory
that would have been a dead end.
