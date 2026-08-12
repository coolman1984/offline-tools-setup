---
name: office-document-automation
description: Use for enterprise Microsoft Office automation across Excel, Word and PowerPoint when documents must be inspected, transformed, generated, validated or exported while preserving formatting, evidence and corporate access controls.
compatibility: Windows enterprise workstation with Microsoft Office where application automation is required; offline document libraries where direct formats are sufficient.
metadata:
  category: Office & Documents
  version: 1.1.0
---

# Office Document Automation

## Mission

Create reliable enterprise Office workflows that preserve source meaning and visual quality while separating document manipulation from business calculation.

## General rules

- Preserve originals and hash them before transformation.
- Prefer direct document-format libraries for ordinary unattended operations.
- Use the authorized installed Office application only when direct libraries cannot correctly access/render/represent the file or an Office-native feature is required.
- Never bypass passwords, DRM, access controls, Protected View, macro policy or Trust Center policy.
- Never overwrite the source unless explicitly requested.
- Make outputs deterministic where possible and validate by reopening them.

## Excel

Delegate analytical workbook ingestion to `enterprise-excel-automation`.

For generated workbooks validate formulas, styles, widths/heights, filters, freeze panes, print settings and representative calculations.

## Word

Preserve and inspect:

- paragraphs/runs/styles
- headings and outline structure
- tables and merged cells
- sections, page orientation and margins
- headers/footers
- fields, hyperlinks and bookmarks
- images/shapes and captions
- lists/numbering
- comments/revisions when the selected workflow supports them

For executive documents, use a controlled style system rather than manual formatting per paragraph.

## PowerPoint

Preserve and inspect:

- slide order, size and layout
- masters/themes where accessible
- text boxes and typography
- shapes, fills, borders and coordinates
- images/media references
- tables/charts and source data where accessible
- speaker notes when requested
- transitions/animations metadata only when supported

Generated decks must use consistent grid, typography, spacing, chart language and safe overflow handling. Validate slide bounds and text overflow.

## PDF export

When Office-native rendering is required, export through the authorized installed Office application and validate the resulting PDF exists, opens and has expected page/slide count. Do not assume a successful process exit means a valid artifact.

## Automation reliability

- bound open/save/export timeouts,
- detect modal dialogs,
- avoid interfering with user-owned Office processes,
- close only instances/documents owned by the automation,
- handle 32/64-bit Office and architecture-sensitive integrations,
- record Office version when native rendering is material,
- avoid automatic external-link refresh,
- never enable macros solely to complete extraction.

## Evidence

Record source hash, output hash, tool path used, Office version if applicable, warnings, validation checks and output locations.

## Execution pack

Use the bundled job contract and validators:

- `assets/document-job.schema.json`
- `templates/document-job.example.json`
- `scripts/validate_office_output.py`
- `scenarios/README.md`

Generated OOXML artifacts must pass package integrity checks before delivery. Native Office validation may add rendering/visual checks on top of the structural validator when the installed application is available.
