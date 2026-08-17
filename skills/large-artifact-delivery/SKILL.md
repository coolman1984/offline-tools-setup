# Large Artifact Delivery Skill

## Purpose

Use this skill when a generated file is too large or unreliable to download through ChatGPT sandbox links or connector file handoff limits.

The preferred solution is to publish the exact validated file as a GitHub Release asset and return the normal browser download URL.

## Trigger Conditions

Use this workflow when any of these are true:

- A sandbox download link fails for the user.
- A single file is hundreds of megabytes or larger.
- A connector refuses to materialize/download an artifact because of a size limit.
- The user explicitly asks for one large downloadable file.
- The file already exists as a validated GitHub Actions artifact and should not be rebuilt differently.

## Core Rule

Never keep retrying the same failing sandbox link for a large file.

If the artifact is already validated, preserve the exact bytes whenever possible and move that same artifact to a proper distribution surface.

Preferred distribution surface:

1. GitHub Release asset in a repository the user controls.
2. Google Drive or another connected file host only when GitHub Releases is unsuitable.

## Proven Workflow

### 1. Build and validate the artifact

Create the final file in CI or locally.

Validate:

- expected file exists
- expected size is reasonable
- archive integrity passes
- required internal files exist
- tests pass
- SHA-256 checksum is recorded

For offline software bundles, test the real offline install path before publishing.

### 2. Keep the validated artifact immutable

Do not rebuild a slightly different package just to publish it.

Prefer moving or copying the already validated artifact byte-for-byte.

Record its SHA-256 checksum before distribution.

### 3. Detect handoff limits early

If ChatGPT sandbox or connector transfer rejects the file due to size, stop retrying that transport.

Typical symptom:

- sandbox link does not start downloading
- connector reports maximum artifact/file size exceeded
- large file is present and healthy but cannot be handed to the user

### 4. Publish through GitHub Release

Create a temporary branch only if needed to run a publishing workflow.

The publishing workflow should:

1. Download the previously validated GitHub Actions artifact.
2. Preserve the exact ZIP or binary.
3. Compute SHA-256 again.
4. Create or update a versioned GitHub Release.
5. Upload the large file as a Release asset.
6. Upload `SHA256SUMS.txt` beside it.
7. Verify the asset state is `uploaded`.
8. Verify the release asset size matches the source artifact.
9. Verify the release digest/checksum when GitHub exposes it.
10. Remove the temporary branch after success.

Do not modify `main` merely to transport a generated binary unless the user explicitly wants the workflow or package committed there.

## Recommended Naming

Release tag:

`<artifact-name>-YYYY-MM-DD`

Release asset:

`<descriptive-name>-Windows-x64.zip`

Checksum file:

`SHA256SUMS.txt`

Use deterministic, readable names. Avoid random IDs in the user-facing filename.

## User-Facing Delivery

Return the GitHub `browser_download_url` for the release asset, not an API URL and not a temporary signed URL.

Also provide:

- exact size
- SHA-256 checksum
- short description of contents

For example:

`https://github.com/<owner>/<repo>/releases/download/<tag>/<file>.zip`

The URL must be observed from the completed GitHub Release response. Never invent it before verifying the release.

## Verification Checklist

Before telling the user the file is ready, confirm all of these:

- CI build completed successfully.
- Artifact validation completed successfully.
- Release creation completed successfully.
- Asset upload completed successfully.
- Asset state is `uploaded`.
- Asset byte size matches expectation.
- SHA-256 is available.
- Browser download URL exists.
- Temporary transport branch is removed if it is no longer needed.

## Large Artifact Edge Cases

### GitHub Actions artifact is over the connector handoff limit

Do not try to download it through the connector.

Run a new GitHub Actions publishing job that downloads the artifact inside GitHub infrastructure and uploads it directly to a GitHub Release.

This avoids moving the large file through ChatGPT.

### User wants exactly one file

Do not split the final deliverable unless there is no other option.

Use GitHub Release so the user receives a single file.

### Existing Release with the same tag

Update the existing release safely or use a new dated/versioned tag.

Avoid silently replacing an unrelated asset.

### Upload fails midway

Retry only the release-upload step after confirming the source artifact is still valid.

Do not rebuild the package unless the build itself was bad.

### Release asset succeeds but checksum differs

Treat this as a failure.

Do not give the user the link until the mismatch is understood and corrected.

## Security and Cleanliness

- Never expose repository tokens or signed internal URLs.
- Use repository-scoped GitHub Actions permissions only as required.
- Prefer a temporary branch for transport-only workflows.
- Delete the temporary branch after successful publication.
- Keep the user-facing download on a stable trusted host.
- Store checksums beside the artifact for later verification.

## Proven Result

This method successfully delivered a validated ~693 MB Python offline toolkit after ChatGPT sandbox download links failed and connector artifact handoff rejected the file due to size.

The successful path was:

validated GitHub Actions artifact -> temporary publish workflow -> GitHub Release asset -> verified `browser_download_url` -> direct browser download.

## Default Decision Rule

For generated files under normal sandbox limits, use a normal sandbox link.

For large files where sandbox delivery fails, switch immediately to the GitHub Release workflow instead of repeatedly retrying the same transport.
