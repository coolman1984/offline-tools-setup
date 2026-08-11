---
name: internal-server-reporting
description: Use when an enterprise reporting workflow must run on an internal server: upload raw business files, validate and process them server-side, persist analytical data in SQL/DuckDB, calculate deterministic metrics, refresh JSON/dashboard outputs, and show safe user-facing progress.
compatibility: Corporate internal Windows/Linux server as approved; Python, SQL Server or approved SQL database, internal web stack.
metadata:
  category: Enterprise Automation
  version: 1.0.0
---

# Internal Server Reporting

## Mission

Turn a weekly/monthly desktop report workflow into a dependable internal web application where the employee uploads the new source file and the server owns processing, calculation, persistence, refresh and evidence.

## User-facing pipeline

The UI should expose simple business-safe stages rather than implementation internals:

1. Upload received
2. Validating file
3. Preparing data
4. Calculating metrics
5. Building report
6. Refreshing dashboard
7. Ready

Use a thin animated progress line/status region at the top, with current stage, meaningful percentage only when measurable, and a durable final success/error receipt.

## Server pipeline

1. stream upload to a staging location with size/type limits,
2. calculate content hash and reject accidental duplicates,
3. create run/job ID and acquire a dataset/report lock,
4. validate filename-independent workbook/document structure,
5. use the document-specific authorized ingestion skill,
6. load staging tables,
7. validate row counts/types/business keys,
8. merge into production analytical tables transactionally,
9. run deterministic SQL/Python calculations,
10. generate versioned `analysis-result.json`,
11. publish dashboard state atomically,
12. record evidence and mark run complete.

## Data stores

Choose by workload:

- DuckDB: excellent for local/server analytical transformations, file-oriented staging and fast columnar queries.
- Microsoft SQL Server: preferred when corporate operations, concurrency, access control, central backup, stored procedures or existing IT standards require it.
- SQLite: configuration/small metadata only, not a substitute for a concurrent enterprise analytical store.

Do not force one database into every workload. Hide database specifics behind a repository/service layer where practical.

## Idempotency

Use file hash + dataset + reporting period + schema version to determine whether an upload is new, duplicate, correction or conflict. A retry must not duplicate a week/month.

Corrections need an explicit replacement policy and audit trail.

## Concurrency

Prevent:

- two uploads mutating the same report simultaneously,
- two workers processing one job,
- stale worker lease blocking forever,
- UI showing success before publish completes.

Use job states, heartbeat/lease timeout and atomic status transitions.

## Security

- internal authentication/authorization according to company infrastructure
- server-side file type and size validation
- never trust client MIME/extension alone
- store uploads outside executable/static web roots
- random/server-generated staging names
- least-privilege database identity
- parameterized SQL
- no secrets in source control or result JSON
- no automatic weakening of document protection
- log actor/run, not confidential workbook contents unnecessarily

## Progress and recovery

Status should be durable in the server, not only browser memory. Browser refresh/reconnect should restore the current run state.

If processing fails:

- production data remains on last known-good version,
- staging data can be retained for diagnosis according to retention policy,
- job shows failed stage and evidence reference,
- retry starts from a safe checkpoint or clean staging state.

## Incremental periods

Adding a week/month updates period dimensions, queries, charts, tables and dropdowns from data. Never hard-code the newest period into frontend source.

## Edge cases

Account for interrupted upload, duplicate upload, partial file, wrong report family, schema drift, corrupted document, locked document, server restart, worker crash, DB timeout/deadlock, disk full, temp volume full, stale lock, JSON publish failure, browser disconnect, corrected historical period, missing target/master data and unexpectedly huge row counts.
