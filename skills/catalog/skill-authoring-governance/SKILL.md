---
name: skill-authoring-governance
description: Use when creating, reviewing or evolving agent skills for the developer suite so one concise Agent Skills-compatible source can work across Codex, Claude Code, Cline, Kilo and OpenCode with progressive disclosure, safe offline dependencies and testable workflows.
compatibility: Agent Skills-compatible AI coding tools managed by Developer Skills Hub.
metadata:
  category: Developer Productivity
  version: 1.0.0
---

# Skill Authoring Governance

## Mission

Create focused skills that agents actually use correctly, instead of giant instruction dumps that consume context and contradict themselves.

## Canonical format

Each skill is a directory containing `SKILL.md`. Keep portable frontmatter conservative:

```yaml
---
name: lowercase-hyphen-name
description: Describe what the skill does and when it should trigger.
compatibility: Optional environment constraint.
metadata:
  category: Example
  version: 1.0.0
---
```

The directory name and `name` should match.

## Description quality

The description is discovery metadata. It should make triggering obvious while staying compact. Include the task/use case, not marketing prose.

Bad: “A powerful comprehensive skill.”

Better: “Use when a recurring Excel report must be ingested, normalized, calculated deterministically and converted into a validated management dashboard.”

## Progressive disclosure

Keep `SKILL.md` focused on workflow, decision rules, outputs and edge cases. Move detailed background into:

```text
references/
assets/
scripts/
```

Only add scripts when deterministic reusable behavior genuinely benefits from code. Instructions are often more portable across agents.

## Portability

Write the canonical skill to the common Agent Skills shape. Put client-specific optional metadata/adapters outside the core instruction where possible. Do not duplicate five slightly different skill bodies unless a client truly requires different behavior.

## Offline policy

Target workstations cannot fetch skill dependencies. A skill may document public references, but executable scripts must not download tools/packages/extensions on the target. Dependencies belong in the main offline bundle.

## Imported skills

Before approving an imported skill:

- identify source and license,
- inspect every executable/support script,
- look for network/download/package-install commands,
- inspect destructive filesystem/registry/system commands,
- inspect secret/token handling,
- check paths for Windows assumptions,
- check whether instructions conflict with corporate policy,
- run it in a controlled test project before broad deployment.

Stars and popularity are discovery signals, not security review.

## Tests

For material skills maintain representative scenarios:

- expected happy path,
- missing dependency,
- malformed input,
- large input,
- ambiguous business rule,
- restricted network,
- retry after partial failure,
- unauthorized/protected input.

A skill is not “good” because its prose sounds intelligent. It is good when agents repeatedly produce correct, auditable outcomes across these cases.

## Evolution

Version skills. Preserve changelog/decision notes for major behavior changes. Update the canonical library first, validate it, then deploy through Skills Hub so clients stay synchronized.
