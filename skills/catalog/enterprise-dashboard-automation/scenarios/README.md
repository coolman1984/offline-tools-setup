# Dashboard Scenarios

- Latest period added: controls, charts, tables and KPIs all expose it from data, not hard-coded markup.
- Partial latest period: a visible warning is carried from the result contract.
- Missing target: render an em dash/neutral state, never divide by null.
- Empty filtered result: show an intentional empty state rather than broken axes.
- Historical correction: cache/version changes atomically and previous period remains comparable.
- Very long category labels: wrap/truncate accessibly without changing underlying labels.
- Large category count: aggregate/top-N or virtualize; do not create thousands of DOM nodes blindly.
- Concurrent refresh: old result stays visible until new result JSON is fully published.
- Reduced-motion preference: animations are suppressed.
- Offline/restricted runtime: no CDN/font/script request is required.
