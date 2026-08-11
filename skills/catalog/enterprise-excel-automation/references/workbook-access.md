# Authorized Workbook Compatibility Access

This reference is implementation detail for `enterprise-excel-automation`.

## Purpose

Some corporate workbooks are readable by the authorized Windows user in Microsoft Excel but cannot be parsed correctly by ordinary ZIP/XML or third-party workbook libraries because enterprise protection is enforced by the installed Office application.

The fallback is **authorized Microsoft Excel COM automation** under the current user context. It is not a DRM bypass and must never be used to defeat passwords, access controls, or permissions.

## Decision order

1. Try direct readers first (`openpyxl`, `python-calamine`, appropriate XLS/XLSB readers, or another approved installed parser).
2. If the parser reports an encrypted/protected/unreadable container while the authorized user can open it normally in Excel, use Excel COM through `pywin32` / `win32com.client` or an equivalent Windows automation bridge already bundled in the suite.
3. If Excel itself denies access, requires credentials the operator does not have, or corporate policy blocks automation, stop and report the condition.

## COM lifecycle

Use a dedicated Excel application instance where possible. Configure it conservatively for unattended extraction:

- `Visible = False` unless an interactive diagnostic is explicitly requested.
- `DisplayAlerts = False` only around operations whose behavior is understood; restore state on exit.
- Disable event-triggered automation when appropriate for read-only extraction.
- Prefer opening read-only when no write is required.
- Record the workbook `FullName`, read-only state, file format and Excel version.
- Never save over the source during extraction.

Always close in `finally` order:

1. release ranges/charts/shapes and other child objects,
2. close workbook without saving,
3. quit only the Excel instance created by the automation,
4. release COM references,
5. force Python garbage collection only as a final reference-release aid,
6. verify that the owned Excel process exited within a bounded timeout.

Never kill arbitrary `EXCEL.EXE` processes. Track the instance/process created by the workflow and leave user-owned Excel sessions alone.

## Extraction strategy

Avoid cell-by-cell COM calls for large ranges. Read rectangular `Value2` and `Formula` blocks in batches, then obtain formatting in bounded chunks only where formatting is required. COM round trips are expensive and are a common cause of slow automation.

Capture:

- worksheets/order/visibility
- `UsedRange` bounds, while treating bloated UsedRange as suspect
- `Value2`, formulas and number formats
- font/fill/border/alignment metadata
- row height / column width
- merged areas
- list objects/tables, filters and validation
- names
- frozen panes
- shapes/charts metadata and anchors
- page setup/print metadata
- links/connections/pivots as accessible

For styles, deduplicate repeated style objects into a style table and reference them by `style_id` from cells/ranges. This keeps JSON manageable.

## Protected workbook edge cases

- Protected sheet does not imply permission to unprotect it. Read only what Excel exposes to the authorized session.
- A password prompt must not be bypassed or guessed.
- If a workbook opens in Protected View, treat it as a security state. Do not automatically enable editing or active content.
- Do not enable macros merely to extract data.
- Never add trusted locations or weaken Trust Center settings automatically.
- External links should not be refreshed automatically. Preserve existing cached values and record link state.
- Disable automatic update of links during open where supported.
- If corporate protection blocks programmatic access even though interactive viewing is allowed, record the limitation and stop that path.

## Reliability

Use bounded timeouts around open, calculation and close. Detect modal-dialog hangs. Keep a per-workbook run log. If extraction fails midway, discard partial analytical tables unless the run format explicitly supports resumable checkpoints with row/range evidence.

The UI should describe this generically as a trusted/compatible workbook access path. The implementation may retain these details in engineering skills and logs intended for developers.
