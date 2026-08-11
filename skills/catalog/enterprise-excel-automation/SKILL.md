---
name: enterprise-excel-automation
description: Use for enterprise Excel automation where workbooks must be read faithfully, normalized for analysis, calculated deterministically, and converted into auditable structured outputs and dashboards, including protected corporate workbooks that require an authorized installed-Excel compatibility path.
compatibility: Windows 10/11 enterprise workstation with the Offline Automation & Development Suite.
metadata:
  category: Enterprise Automation
  version: 1.0.0
---

# Enterprise Excel Automation

## Mission

Turn business workbooks into trustworthy, repeatable automation without losing workbook meaning, layout, evidence, or corporate access controls.

## Core pipeline

1. Preserve the original file unchanged and record path, size, modified time, and SHA-256.
2. Try the safest direct workbook reader first for ordinary files.
3. If the workbook is only readable through the authorized installed Microsoft Excel session, use the compatibility workflow in `references/workbook-access.md` under the current authorized Windows user. Never bypass passwords, DRM, file permissions, or enterprise controls.
4. Extract a structural workbook manifest to JSON before analytical transformation.
5. Normalize analytical tables into DuckDB with explicit source lineage.
6. Perform arithmetic, joins, aggregations, period logic, targets, rankings, and comparisons in SQL/Python, not by language-model guesswork.
7. Produce a versioned result JSON for presentation.
8. Build or refresh the requested dashboard/report from the result JSON.
9. Validate totals, dimensions, row counts, time periods, exceptions, and a sample of source-to-output cells.
10. Save evidence, warnings, schema version, and run receipt.

## Workbook manifest

Capture enough information to reconstruct meaning and presentation, including when available:

- workbook and worksheet names/order
- visible, hidden, very-hidden state
- used ranges and table/range boundaries
- cell values, formulas and cached/calculated values
- data types, errors and blanks
- number formats and date system
- font family, size, weight, style and decoration
- fill/background and font colors
- borders, alignment, wrapping and indentation
- row heights and column widths
- merged ranges
- frozen panes and split panes
- filters, sorts and structured tables
- defined names and named ranges
- conditional formatting definitions
- data validation rules
- comments/notes where accessible
- charts, series, titles, axes and source ranges
- shapes/images metadata and anchors
- hyperlinks
- print area, page setup, headers/footers and orientation
- workbook calculation mode where relevant
- external links/connections and pivot metadata where accessible

Do not pretend unsupported objects were captured. Record `unsupported`, `not_accessible`, or `not_extracted` explicitly.

## Analytical normalization

Prefer long, typed, queryable tables over copying every visual artifact into the analytical database. Keep the visual/structural manifest in JSON and analytical records in DuckDB.

For every analytical table preserve lineage fields when practical:

- source workbook hash
- source sheet
- source range/table
- source row identity
- ingestion timestamp
- schema version
- period/date keys

## Deterministic calculation rules

- Let SQL/Python own arithmetic.
- Reproduce existing verified business formulas before optimizing them.
- Treat totals/subtotals separately from detail rows.
- Detect duplicated rows and duplicated business keys.
- Resolve locale-sensitive decimal/date parsing explicitly.
- Distinguish formula text from calculated value.
- Preserve null versus zero.
- Validate percentage denominators and divide-by-zero behavior.
- Use stable rounding rules and document them.
- Never silently coerce suspicious values.

## Important edge cases

Handle or report:

- 32-bit versus 64-bit Office
- workbook already open or locked
- read-only files
- password prompts or access-denied states
- protected sheets/workbooks
- large worksheets and sparse used ranges
- merged headers and multi-row headers
- hidden rows/columns/sheets
- formulas returning errors
- external links unavailable offline
- macros and macro-enabled formats
- pivot tables/caches
- date systems 1900 versus 1904
- locale-specific dates/numbers
- corrupt or partially repaired workbooks
- duplicated column names
- blank header cells
- totals embedded inside detail ranges
- Excel process left running after automation
- user prompts/dialogs blocking unattended work

## Output contract

Create at minimum:

- `source-receipt.json`
- `workbook-manifest.json`
- DuckDB database or documented database target
- `analysis-result.json`
- validation/evidence report

`analysis-result.json` should be presentation-ready and contain only validated metrics/series/tables/findings needed by downstream reporting.

## Safety

Never alter the original workbook unless the task explicitly requests an edited copy. Never weaken corporate protection. Never automate around an access denial. Use the current authorized Office session only as a compatibility reader/writer when ordinary file APIs cannot represent the authorized user experience.
