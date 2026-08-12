# Enterprise Excel Automation Scenarios

1. **Normal workbook**: direct reader succeeds; manifest, DuckDB and result JSON validate.
2. **Protected corporate workbook readable by the authorized user**: direct parser fails; trusted compatibility path is used without weakening protection.
3. **Access denied**: installed Office also denies access; stop with evidence and no partial publish.
4. **Large sparse sheet**: suspicious UsedRange is bounded; bulk reads are used; memory stays controlled.
5. **Mixed totals/detail**: totals rows are separated from analytical detail and reconciliation passes.
6. **1904 date system / locale values**: dates and decimals normalize explicitly and preserve source values.
7. **External links unavailable**: cached values are preserved; links are not refreshed; warning is emitted.
8. **Retry after failure**: same source hash/run does not duplicate analytical rows.
9. **Style-heavy workbook**: styles are deduplicated into a style table instead of exploding JSON size.
10. **Workbook already open**: automation never kills the user's Excel process and only closes owned objects.

For release testing, keep at least one fixture for scenarios 1, 4, 5 and 9 and one corporate-authorized fixture for scenario 2 in the internal test vault.
