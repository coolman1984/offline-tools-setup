# Internal App Project Layout

```text
app/
  frontend/        # UI only; no business arithmetic
  api/             # versioned HTTP contracts
  domain/          # business rules and deterministic services
  workers/         # long-running jobs
  data/            # repositories/migrations
  contracts/       # JSON schemas and DTOs
  tests/           # unit/integration/contract tests
  ops/             # service config, health, backup/rollback
  docs/             # runbook and architecture decisions
```

Release gate: frontend/backend versions agree, migrations are known, health endpoint passes, runtime assets are local, configuration has no secrets committed, and rollback steps are documented.
