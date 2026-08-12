# Internal Web App Scenarios

- Browser refresh while a long job runs: state recovers from server.
- Backend restart: in-flight job becomes resumable/failed by lease rules, never false-success.
- Frontend/backend version skew: health/contract check blocks incompatible publish.
- SQL outage: request fails safely and no partial business transaction is committed.
- Disk full during upload: staging cleanup and explicit error.
- Concurrent uploads: job IDs isolate files and dataset lock protects shared mutation.
- Expired authentication: protected APIs fail closed without exposing report data.
- Restricted network: app loads with zero public CDN/package calls.
