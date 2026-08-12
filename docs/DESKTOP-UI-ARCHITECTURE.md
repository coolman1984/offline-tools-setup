# Desktop Control Surface Architecture

## Product goal

`desktop-ui/` is the primary interface for the Offline Automation & Development Suite: a self-contained Windows x64 desktop application that presents Setup, Safe Repair, Device Details, Skills Hub and Logs & Evidence as a single always-visible left-rail navigation, rather than the sequential full-screen prompts of a console tool.

It supersedes `installer-ui/` and `suite-shell/` as the interface `START-HERE.cmd` launches by default. Those two .NET/Spectre.Console applications, plus `skills-hub/`, remain in the bundle as fallbacks and for functionality the desktop UI does not yet reimplement (see [Migration status](#migration-status)).

The desktop UI is a presentation and orchestration layer only. It does not reimplement setup, diagnostic or inventory logic — every action it exposes shells out to the same PowerShell engines under `scripts/` that the console tools use, so behavior and safety guarantees stay identical across interfaces.

## UI technology

- Python 3.11+, run through the primary managed runtime pinned in `config/tool-manifest.json`.
- PySide6 6.11.1 (Qt for Python).
- Qt Quick / QML for the view layer, with the `FluentWinUI3` Quick Controls style pinned to light mode regardless of the host's dark-mode setting (`desktop-ui/main.py`).
- `pyside6-deploy` (Nuitka-based) compiles the application to a single-file `OfflineToolsDesktop.exe` via `scripts/Build-PySide6Ui.ps1`.

## Process layout

```text
desktop-ui/
  main.py           entry point: elevation, style setup, QML engine bootstrap
  backend.py         AppBackend(QObject): all state, config loading, process orchestration
  qml/Main.qml        the entire UI — six pages behind one ApplicationWindow
  requirements.txt    pinned PySide6 dependency
  pyproject.toml      pyside6-project file list + pytest configuration
  tests/               pytest suite for backend.py
```

`main.py` does three things before handing off to Qt: requests UAC elevation via `ShellExecuteW(..., "runas", ...)` and exits the unelevated process if a new elevated one was launched (`ensure_windows_admin`); forces the Fluent light style; and resolves the bundle root (`--bundle-root <path>` argument, `OFFLINE_TOOLS_BUNDLE_ROOT` environment variable, or a walk up from the current working directory / executable directory looking for `config/setup-profiles.json`), falling back to the repository checkout root so the UI can run against a bare `git clone` before a full offline bundle exists.

`backend.py` is a single `QObject` subclass (`AppBackend`) exposed to QML as the `backend` context property. It owns:

- **Config surfaces** — `setup_config`, `care_config`, `skills_config` loaded once from `config/setup-profiles.json`, `config/windows-care.json` and `config/skills-hub.json`, and re-exposed to QML as read-only `QVariantMap`/`QVariantList` properties (`appData`, `preflight`, `deviceData`, `logs`).
- **Selection state** — the active setup preset, selected profiles/components, and selected Windows Care actions, mutated only through `@Slot` methods (`setProfileSelected`, `setComponentSelected`, `applyCarePreset`, `setCareSelected`, ...) and summarized through computed properties (`selectionSummary`, `careSummary`) so QML never recomputes footprint or repair-risk math itself.
- **Background work** — a preflight scan runs on a plain `threading.Thread` (`runPreflight` / `_scan_preflight`) since it only touches the filesystem and registry; setup, Windows Care and device-inventory runs are `QProcess` children (`_start_process`) so their stdout/stderr can be streamed back into the UI without blocking the Qt event loop.

`Main.qml` renders six pages behind a single `ApplicationWindow` and a `StackLayout` keyed on left-rail selection (Home, Setup, Safe Repair, Device Details, Skills Hub, Logs & Evidence). It never duplicates business logic: every list is driven by a `Repeater` over an `appData`/`preflight`/`careSummary` property, and every mutation goes through a `backend.*` slot call.

## Process orchestration and stdout protocols

`_start_process` launches a PowerShell script as a `QProcess`, tags it with a task name (`"setup"`, `"care"`, or `"inventory"`), and reports progress back to QML through the `progressChanged(percent, message)` signal, which drives the busy overlay's progress bar and status text.

Two of the three backing scripts speak different protocols on stdout, and the backend understands both:

- `scripts/Install-SelectedProfiles.ps1` emits `@@EVENT|<percent 0-100>|<message>` at each phase boundary (`Emit-Event` in that script). `_read_stdout` parses this directly into the reported percentage.
- `scripts/Invoke-SafeWindowsCare.ps1` emits `@@CARE|<action-id>|<message>` (`Write-CareEvent`) once per diagnostic/repair action, with no percentage — it was originally written for the console suite shell, which streams raw process output straight to the terminal rather than parsing it. `_read_stdout` estimates a percentage from actions-reported vs. actions-selected (`_care_action_total` / `_care_action_done`), capped at 99% so 100% is only ever reported by the real completion signal from `_process_finished`.
- `scripts/Get-DeviceInventory.ps1` emits no structured progress markers at all; the busy overlay shows "Starting…" for the duration of a device scan and then jumps to complete.

Any future PowerShell engine wired into the desktop UI should either emit `@@EVENT|` directly, or be given the same treatment as Windows Care if it already has its own console-oriented status protocol — silently dropping unrecognized lines is intentional (so plain diagnostic text doesn't get misparsed as progress), but it means a new protocol prefix needs an explicit `elif` branch in `_read_stdout`, not just a hope that `@@EVENT|` covers it.

## Guardrail and safety text

Windows Care's safety copy (the "never deletes user folders, disables security controls, ..." text shown in the repair confirmation dialog and the Safe Repair page) is generated by `AppBackend.guardrailSummary` from `config/windows-care.json`'s `guardrails` block rather than hardcoded in QML, so the two can't drift apart as guardrails are added or changed.

## Testing

`desktop-ui/tests/` covers `backend.py` with `pytest`: preset/selection state transitions, `writeSetupPlan()`'s output shape, both stdout protocols, and `guardrailSummary`. Tests instantiate `AppBackend` against the real repository config (not mocks) so they exercise the actual `config/*.json` shape, and run against a `QCoreApplication` rather than `QGuiApplication` so they need no display or platform plugin. CI runs them on every push/PR that touches `desktop-ui/**` (`.github/workflows/installer-ui-ci.yml`).

QML has no automated behavioral tests; `pyside6-project qmllint` catches static errors and unbound-context warnings but not runtime logic, which is why the business logic under test deliberately lives in `backend.py` and not in QML bindings.

## Build and deployment

`scripts/Build-PySide6Ui.ps1` creates an isolated virtual environment, installs `desktop-ui/requirements.txt` into it, and runs `pyside6-deploy -f --name OfflineToolsDesktop --extra-modules Quick,Qml,QuickControls2` to produce a one-file executable, which it copies to `payload/bootstrap/OfflineToolsDesktop.exe` in the bundle under construction. `scripts/Build-SetupUi.ps1` calls this after building the three .NET fallback applications, and treats a missing or empty desktop executable as a fatal build error. CI (`.github/workflows/installer-ui-ci.yml`) runs the same build script and applies the same minimum-size check used for the .NET executables, so a `pyside6-deploy`/Nuitka regression is caught before it reaches a real builder machine.

## Migration status

Fully on the desktop UI: Home, Setup, Safe Repair, Device Details.

Partial: Skills Hub's search, validation-status display and AI-target detection are native to the desktop UI; "Advanced operations" (deployment, creation, import, Project Brain) still shells out to `payload/bootstrap/OfflineSkillsHub.exe`, the standalone `skills-hub/` C# engine, via `openSkillsEngine()`.

Not migrated: nothing else — `installer-ui/` and `suite-shell/` exist purely as `START-HERE.cmd` fallbacks for a bundle that was built without the desktop executable (older builder, or a `pyside6-deploy` failure), not as an interface a user would choose over the desktop UI.
