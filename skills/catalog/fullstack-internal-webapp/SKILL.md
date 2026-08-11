---
name: fullstack-internal-webapp
description: Use when building a corporate internal full-stack web application that must run reliably on controlled infrastructure, work without public CDNs/package downloads on target servers, expose clear APIs/status, and integrate enterprise reporting, SQL and file automation safely.
compatibility: Internal corporate web server; pre-bundled Node/Python/.NET and approved SQL infrastructure.
metadata:
  category: Internal Web Apps
  version: 1.0.0
---

# Full-Stack Internal Web App

## Mission

Build maintainable internal applications that feel modern to employees while remaining deployable in restricted enterprise infrastructure.

## Architecture principles

- Separate UI, API, domain logic and persistence.
- Keep business calculations in tested server-side services/SQL.
- Treat long-running file/report work as jobs, not blocking web requests.
- Do not depend on public CDN assets at runtime.
- Pin and pre-bundle dependencies on the connected builder.
- Make server state durable so browser refresh does not lose job progress.

## Recommended layers

```text
frontend/
api/
domain/
workers/
data/
contracts/
tests/
ops/
```

Choose React/Vite/Next.js or simpler HTML/JS according to product complexity, not fashion. Choose Python/.NET/Node backend according to installed capabilities and enterprise ownership.

## API contract

Use versioned request/response schemas. For jobs expose:

- create/upload
- current state
- progress/stage
- warnings/questions if applicable
- result metadata
- output/evidence links
- retry/cancel when supported

Use server-sent events or another approved internal real-time mechanism for progress when it improves UX, with polling fallback if needed.

## Upload design

- stream rather than loading large files fully in request memory,
- enforce server-side limits,
- write outside public static directories,
- randomize server filenames,
- hash uploaded content,
- validate actual format,
- quarantine/stage before processing,
- clean temporary files according to retention policy.

## Frontend quality

- clear navigation and state
- modern enterprise spacing/typography
- responsive layouts
- keyboard support
- visible focus
- empty/loading/error states
- top progress/status strip for long jobs
- no fake progress
- no hidden network dependencies
- no business secrets in client JavaScript

## Database

For SQL Server use parameterized queries, explicit transaction boundaries and migrations. Separate raw/staging/analytical/presentation data when complexity warrants it.

DuckDB may be used inside workers for high-speed analytical transformation without turning it into the concurrent system of record.

## Deployment

Document:

- required ports/services
- service identity and filesystem permissions
- database connection configuration
- reverse proxy/TLS ownership
- log/state directories
- backup/restore
- health checks
- upgrade/rollback procedure

## Edge cases

Handle concurrent users, stale sessions, duplicate uploads, worker crash, server restart, DB outage, disk full, partial publish, schema migration mismatch, proxy timeouts, large result sets, old browser cache, expired authentication and version skew between frontend/backend.
