## Summary

<!-- What changed, and why. Link an issue if there is one. -->

## Testing

<!-- What you ran, and what happened. Copy in relevant output. -->

- [ ] Ran the applicable checks from `CONTRIBUTING.md#running-the-checks-locally`
- [ ] For `desktop-ui/` changes: `pytest` passes and `pyside6-project qmllint` is clean
- [ ] For `config/*.json` changes: every consumer that reads the changed field was checked, and `requirements/recommended.txt` was updated if a profile's package list changed
- [ ] For build-script changes that add a download: it's verified (pinned SHA-256, or Authenticode for Microsoft binaries)

## Checklist

- [ ] Changes are scoped to what this PR is about
- [ ] Commit messages are short, imperative, lower-case, matching existing history
