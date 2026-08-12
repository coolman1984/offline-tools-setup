# Automation Execution Packs

## Purpose

Canonical skills are executable playbooks, not prose-only instructions. Each material automation skill carries its own contracts, templates, deterministic helpers and scenario catalog so the same skill package remains useful after Developer Skills Hub publishes it to Codex, Claude Code, Cline, Kilo or OpenCode.

## Package shape

A mature skill can contain:

```text
SKILL.md
assets/       machine-readable contracts, schemas, SQL seeds
references/   deep implementation guidance
scripts/      deterministic validation/build helpers
templates/    starter artifacts and project skeletons
scenarios/    happy-path and edge-case acceptance scenarios
```

Only include code when repeatability benefits from code. Keep vendor/client adapters outside the canonical skill body unless a client truly requires different behavior.

## Current execution packs

### enterprise-excel-automation

- source receipt JSON Schema
- workbook manifest JSON Schema
- analysis-result JSON Schema
- deterministic sample analytical SQL
- DuckDB sample database generator
- run-contract validator
- workbook edge-case scenario catalog

### enterprise-dashboard-automation

- dashboard-spec JSON Schema
- self-contained no-CDN HTML/CSS/JS starter dashboard
- dashboard/result contract validator
- refresh/cache/period/accessibility scenarios

### internal-server-reporting

- durable job-status JSON Schema
- FastAPI upload/status pipeline starter
- concurrency/idempotency/recovery scenarios

### office-document-automation

- Office document job contract
- example generation job
- OOXML structural integrity validator
- Office-native/export reliability scenarios

### pdf-document-automation

- PDF job contract and example
- reopen/page-count/render validator using bundled PDF stack
- digital/scanned/mixed/encrypted/RTL scenarios

### fullstack-internal-webapp

- internal application runtime/deployment contract
- reference project layout
- outage/version-skew/concurrency/restricted-network scenarios

### second-brain-project-memory

- fact and decision schemas
- Project Brain template
- vault validator for structure, schema and duplicate IDs
- contradiction/time/admission-gate scenarios

### automation-governance

- production run receipt contract and example
- idempotency/drift/approval/partial-publish/security scenarios

### skill-authoring-governance

- skill package contract
- portable SKILL.md template
- structural/network/package-install static validator
- skill evolution and regression scenarios

## Repository validation

`scripts/Test-SkillExecutionPacks.py` verifies that required execution-pack files exist, JSON artifacts parse and Python helpers compile.

`scripts/Run-SkillScenarioTests.py` performs executable smoke scenarios in a temporary workspace:

- creates a real DuckDB sample database and validates expected summary output,
- validates dashboard contracts against fixture data,
- creates a minimal OOXML workbook package and validates it,
- creates a real PDF and reopens/renders it,
- validates a fixture Project Brain,
- runs the skill-package validator against a canonical skill.

GitHub Actions installs only the small test dependencies required for these execution scenarios on the CI runner. Target workstations still download nothing; their required packages are prepared by the connected offline-bundle builder.

## Release rule

A skill change is not considered complete merely because `SKILL.md` reads well. For material behavior changes:

1. update the canonical skill first,
2. update contracts/templates/helpers as required,
3. add or update a scenario that represents the changed behavior,
4. pass repository validation and executable scenario tests,
5. build the offline bundle,
6. deploy through Skills Hub with backup and deployment receipt.
