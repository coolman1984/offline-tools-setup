---
name: second-brain-project-memory
description: Use when a project needs durable local knowledge: extract entities, facts, events, decisions and sources into an auditable Markdown second brain with dates, confidence, contradiction handling, version history and reusable project-specific knowledge.
compatibility: Local Markdown/JSON project vault; optional Obsidian-compatible browsing without requiring Obsidian-specific features.
metadata:
  category: Knowledge & Second Brain
  version: 1.1.0
---

# Second Brain Project Memory

## Mission

Turn project work into durable knowledge instead of forcing every agent session to rediscover the same facts.

## Separate knowledge from instructions

- Skills describe repeatable methods.
- Project Brain stores project-specific facts, entities, events, decisions, sources, assumptions, unknowns and history.
- Never bury durable project facts only inside a generic skill.

## Recommended vault

```text
PROJECT-BRAIN.md
brain-index.json
facts/
entities/
decisions/
sources/
timeline/
reports/
skills/
```

## Fact record

A material fact should record when available:

- stable fact ID
- statement
- entity/entities
- effective/event date
- observed/recorded date
- source ID and source location
- confidence
- status: active / superseded / disputed / unknown
- structured value/unit where useful
- relationship links
- notes/inference clearly separated from observation

## Entity record

Maintain canonical name, aliases, type, relationships and pointers to supporting facts/events. Do not duplicate the same entity because spelling/case changed.

## Decisions

Record:

- decision
- date
- owner/participants when known
- problem/context
- alternatives considered
- rationale
- constraints
- evidence
- consequences
- supersedes/superseded-by links

## Contradictions

Never silently overwrite a previous fact. When sources disagree:

1. preserve both claims,
2. mark conflict,
3. compare source authority/date/scope,
4. choose an active interpretation only when justified,
5. retain the reasoning and the superseded/disputed record.

## Time

Distinguish:

- when an event happened,
- when a source reported it,
- when the agent learned/imported it.

This prevents old documents from overwriting newer reality.

## Sources

Every source entry should preserve enough identity to relocate it: filename/document ID/path, page/sheet/range/URL when appropriate, date, hash or version if available, and ingestion timestamp.

## Memory admission gate

Before storing something permanently ask:

- Is it project-specific rather than generic method?
- Is it likely to matter later?
- Is there evidence/source?
- Is it already represented?
- Is it sensitive and, if so, is the vault appropriate?

Avoid filling memory with transient chat, guesses or duplicated report prose.

## Reporting

Reports should reference fact/source IDs. New analysis can become a report without automatically becoming a fact; only validated durable findings should pass the admission gate.

## Exports

When useful, provide machine-readable exports such as JSON/CSV and relationship-friendly JSON-LD, while Markdown remains the readable canonical project notebook.

## Execution pack

Use the bundled memory contracts and validator:

- `assets/fact.schema.json`
- `assets/decision.schema.json`
- `templates/PROJECT-BRAIN.template.md`
- `scripts/validate_brain.py`
- `scenarios/README.md`

A project brain is not complete merely because Markdown exists. Validate structured facts/decisions, preserve unique IDs and keep the readable project summary synchronized with the active records.
