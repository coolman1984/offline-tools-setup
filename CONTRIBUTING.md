# Contributing

## Before you start

This project has a specific constraint that shapes almost every design decision: target machines must never download software, packages, extensions, updates, or models at install time. Everything a target PC needs is prepared ahead of time on a trusted, connected builder PC and shipped as a verified offline bundle. If a change would require a target-side download, it needs a different approach, not an exception.

See `README.md` for the overall architecture, `docs/INSTALLER-UX-ARCHITECTURE.md` for the setup UX, `docs/DESKTOP-UI-ARCHITECTURE.md` for the primary desktop interface, and `docs/WINDOWS-SAFE-CARE.md` for the Windows Care guardrail model before touching anything in those areas.

## Making a change

1. Fork and branch from `main`.
2. Keep changes scoped — this repo spans PowerShell, C#, Python/PySide6, QML and JSON config, and a change that touches one layer usually shouldn't also touch the others unless the task genuinely requires it.
3. If you change `config/*.json`, keep it valid JSON and keep every consumer (PowerShell, C#, `desktop-ui/backend.py`) in sync — several fields are read from more than one place.
4. If you change `requirements/profiles/*.txt`, also update `requirements/recommended.txt` (and `requirements/ocr-heavy.txt` for the optional heavy OCR stack) to match — the profile files are what gets installed at target time via `pip install --no-index`, but `recommended.txt` is what actually gets downloaded into the offline wheelhouse at build time. A package or version pinned in one but not the other breaks the install on a real target machine invisibly, since nothing surfaces the mismatch until someone runs the full bundle build and install end to end.
5. If you add a download to a build script, verify it — either a pinned SHA-256 checked against the file, or (for Microsoft-published binaries) an Authenticode signature check. `scripts/Build-OfflineBundle.ps1`'s `Get-RemoteFile` throws by default unless a hash is supplied or `-SkipVerification` is passed explicitly for a file verified immediately afterward some other way.
6. Run what CI runs before opening a PR — see below.
7. Commit messages in this repo are short, imperative, lower-case ("add executable automation skill packs and scenario validation", "fix DuckDB sample schema reserved target keyword"). Match that style.

## Running the checks locally

Full CI is Windows-only (`.github/workflows/installer-ui-ci.yml`, `runs-on: windows-latest`), but most of it can be exercised locally:

```powershell
# desktop UI: Python syntax, QML lint, backend test suite
python -m py_compile desktop-ui/main.py desktop-ui/backend.py
pip install -r desktop-ui/requirements.txt pytest
cd desktop-ui; pyside6-project qmllint; python -m pytest -v; cd ..

# config JSON validity
Get-Content config/*.json -Raw | ForEach-Object { $_ | ConvertFrom-Json | Out-Null }

# every PowerShell script parses
Get-ChildItem scripts -Filter *.ps1 | ForEach-Object {
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$null)
}

# skill catalog structure + executable scenarios
python scripts/Test-SkillExecutionPacks.py
python scripts/Run-SkillScenarioTests.py
```

The two full application builds (`installer-ui/`, `suite-shell/`, `skills-hub/` via `dotnet build`/`publish`, and the desktop UI via `scripts/Build-PySide6Ui.ps1`) require Windows and are best left to CI unless you're specifically working on packaging.

## Pull requests

Use the PR template. Describe what changed and why, and how you verified it — "ran the CI checks locally" is a fine answer when that's genuinely what you did. Screenshots or a short description of manual testing are appreciated for `desktop-ui/qml/Main.qml` changes, since QML has no automated behavioral tests.
