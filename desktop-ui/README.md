# Offline Tools Desktop UI

Primary Windows desktop control surface for the Offline Automation & Development Suite.

## Technology

- Python 3.11+
- PySide6 6.11.1
- Qt Quick / QML
- Qt Quick Controls `FluentWinUI3` light style
- `pyside6-deploy` for the self-contained Windows executable

The desktop UI is a presentation and orchestration layer. It deliberately reuses the repository's existing PowerShell setup, Windows Care and device-inventory engines instead of duplicating their business rules.

## Navigation

- **Home** — readiness summary and task-focused quick actions.
- **Setup** — preset radio choices, locked Core Foundation, profile/component checkboxes, footprint summary, plan-only save and installation execution.
- **Safe Repair** — read-only health presets, optional repair visibility, explicit action checkboxes, risk/duration labels and a second confirmation for repairs.
- **Device Details** — read-only overview, network, storage, security/policy, problems/events and updates/services views.
- **Skills Hub** — local skill catalog, search, validation status and AI target detection. Advanced deployment/create/import/Project Brain operations continue through the existing Skills Hub engine during the migration.
- **Logs & Evidence** — searchable plans, state files and runtime logs.

## Design principles

The interface is intentionally light, quiet and information-first: neutral canvas, white cards, restrained blue accent, generous spacing, clear hierarchy, plain-English helper text and status labels that never rely on color alone.

Top-level navigation stays in the left rail. Tabs/segmented controls are used only inside a page for closely related views.

## Local development

```powershell
cd desktop-ui
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe main.py --bundle-root ..
```

The source mode can run from a repository checkout even before a complete offline bundle exists. Actions that require bundled PowerShell engines or bootstrap executables will explain what is missing rather than silently failing.

## Bundle build

`scripts/Build-PySide6Ui.ps1` creates an isolated builder environment and uses `pyside6-deploy` to generate:

```text
payload\bootstrap\OfflineToolsDesktop.exe
```

`START-HERE.cmd` prefers this desktop executable and retains the current console suite and setup engine as fallbacks.
