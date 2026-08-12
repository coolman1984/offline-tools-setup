# Automation Governance Scenarios

- Same input retried: idempotency prevents duplicate business data.
- Column renamed with low mapping confidence: run waits for approval, not AI guesswork.
- Published KPI correction: explicit replacement approval + audit receipt.
- Calculation error halfway through: no partial publish and previous result remains active.
- Model proposes arithmetic: deterministic service re-computes and validates before acceptance.
- Duplicate business keys: quality gate fails before aggregation.
- Missing target/master data: warning/failure follows workflow policy and is evidence-linked.
- Secret accidentally appears in proposed output: release gate rejects/redacts before persistence.
