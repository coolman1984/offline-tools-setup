# Internal Server Reporting Scenarios

1. Interrupted upload: incomplete staging file is never published.
2. Duplicate hash + same period: return duplicate/conflict policy, never append twice.
3. Corrected historical period: explicit replacement run with audit trail.
4. Worker crash: lease expires and a retry reclaims safely.
5. Database deadlock/timeout: transaction rolls back and previous production remains intact.
6. Server disk full: fail before publish with required-space evidence.
7. Browser reconnect: status is reconstructed from durable job state.
8. Schema drift: stage stops before production merge and routes to mapping review.
9. Publish failure: last known-good dashboard stays live.
10. Two simultaneous uploads for the same dataset: dataset lock serializes mutation.
