---
name: automation-governance
description: Use for enterprise automation design and review when calculations, data lineage, approvals, evidence, idempotency, error handling, security and human trust must be engineered explicitly rather than delegated to an AI model.
compatibility: Enterprise automation projects using the Offline Automation & Development Suite.
metadata:
  category: Agent Governance
  version: 1.0.0
---

# Automation Governance

## Mission

Make AI-assisted automation dependable enough for business use by assigning each type of work to the right mechanism and preserving evidence for every material output.

## Golden rule

Use language models for interpretation, mapping, explanation, prioritization and ambiguity. Use deterministic code/SQL for arithmetic, joins, aggregation, dates, thresholds, validation and repeatable transformation.

## Required controls

Every production workflow should define:

- source identity and hash/version
- schema/field mapping version
- deterministic calculation version
- run/job ID
- input validation
- data-quality gates
- idempotency key
- status state machine
- logs/evidence
- output hashes/locations
- approval points for consequential changes
- recovery/retry behavior

## State model

Prefer explicit states such as:

`received -> validating -> prepared -> calculating -> building -> publishing -> completed`

and terminal/controlled alternatives:

`waiting_for_user`, `waiting_for_approval`, `paused`, `cancelled`, `failed`.

Do not infer completion merely because a process stopped.

## Human approval

Require explicit approval before:

- changing source mappings with low confidence,
- replacing historical business data,
- overwriting a user-authored document,
- applying a correction that changes published KPIs,
- destructive cleanup,
- sending/publishing externally when impact is material.

## Mapping and drift

For recurring reports, store approved mappings. On future runs reuse them deterministically and invoke AI judgment only when schema/semantic drift is detected.

Drift signals include missing columns, new columns, type change, unexpected category/value domain, header movement, table/range shift and substantial row-count anomalies.

## Evidence

A finding should reference the metric/query/source evidence that supports it. Separate:

- source fact,
- deterministic result,
- model interpretation,
- recommendation.

## Data quality gates

Examples:

- required keys not null
- no impossible dates
- no non-positive standard price where business rules forbid it
- totals reconcile within defined tolerance
- duplicate business keys detected
- expected period coverage present
- row count within reasoned bounds

## Security

Never place secrets in skills, logs, result JSON or source control. Respect enterprise protection and application-control policy. Treat uploaded files as untrusted input. Use least privilege and parameterized SQL.

## Failure design

A retry must be safe. A partial run must not masquerade as success. Publication should be atomic. Preserve last known-good output until the new run passes validation.

## Agent behavior

When uncertain, the agent should explain the uncertainty and ask for/route to evidence rather than inventing a mapping or business rule. Persistent decisions should be captured in the project brain so future sessions do not repeat the same ambiguity.
