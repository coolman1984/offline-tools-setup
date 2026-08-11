---
name: enterprise-dashboard-automation
description: Use when validated business data or analysis JSON must become a polished enterprise dashboard or management report with responsive charts, filters, comparisons, tables, evidence, and safe incremental period refreshes.
compatibility: Offline-capable HTML/CSS/JavaScript or approved internal web application stack.
metadata:
  category: Enterprise Automation
  version: 1.0.0
---

# Enterprise Dashboard Automation

## Mission

Convert validated analytical outputs into a fast, readable, management-grade dashboard without hiding calculation logic inside presentation code.

## Inputs

Prefer a versioned presentation contract such as `analysis-result.json` containing:

- report metadata and schema version
- available periods and active period
- KPI values, targets and deltas
- chart series and categories
- table rows and column definitions
- comparisons and rankings
- findings/insights with evidence IDs
- warnings/data-quality flags
- source/run receipt references

The browser must not recreate business calculations that belong in SQL/Python.

## UX principles

- modern 2026 enterprise visual language, not decorative gimmicks
- strong information hierarchy
- high-density but readable layouts
- responsive desktop/tablet behavior
- keyboard-accessible controls
- clear filter state
- restrained motion for transitions/progress, never animation that delays work
- visible loading, empty, partial-data and error states
- light/dark theme only when both remain legible
- no CDN/runtime dependency when deployment is restricted/offline

## Dashboard anatomy

Use only sections justified by the business question. Common blocks:

- report title, period and data freshness
- KPI cards with target/previous-period comparison
- trend charts
- categorical comparison charts
- variance/waterfall when appropriate
- best/worst rankings
- detailed sortable/filterable tables
- data quality / warning area
- concise management insights
- optional evidence/drilldown links

## Period refresh behavior

When a new week/month is loaded:

1. validate the period key and schema,
2. reject duplicate ingestion unless the run is explicitly a correction/replacement,
3. update period dimension centrally,
4. regenerate affected metrics and series,
5. refresh dropdown choices from data rather than hard-coded labels,
6. preserve previous periods for comparison,
7. verify charts/tables use the same selected period,
8. invalidate stale cached presentation JSON,
9. publish atomically so users never see half-old/half-new data.

## Charts

Choose chart types by analytical purpose, not visual novelty. Every chart should have:

- explicit title/question
- units
- stable category ordering where required
- sensible zero/base behavior
- tooltips that add information
- accessible labels/legend
- empty-data behavior
- large-series strategy

Avoid misleading dual axes unless essential and clearly labeled.

## Insights

Insights must point back to deterministic evidence. A good insight says what moved, magnitude, comparison basis, likely operational meaning, and evidence reference. Do not invent causality when data only shows correlation.

## Edge cases

Handle:

- no rows after filtering
- partial latest period
- missing target
- divide by zero
- negative metrics
- very long labels
- hundreds/thousands of categories
- timezone/date-boundary differences
- corrected historical period
- schema evolution
- stale browser cache
- slow network to internal server
- user changing filters during refresh
- two refreshes racing

## Output

Produce a self-contained static dashboard or internal web app according to the deployment architecture, plus a clear data contract and build/run instructions. All visual claims must be traceable to the validated result JSON.
