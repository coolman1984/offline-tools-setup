# Professional Installer UX Architecture

## Product goal

The target experience is a polished enterprise-grade console setup application for Windows 10/11 x64. It must feel deliberate and safe rather than like a chain of scripts.

The user launches `START-HERE.cmd`, receives the normal Windows administrator prompt, then enters a full-screen keyboard-driven console interface. The interface scans the workstation, explains what is present, allows profile and component selection, resolves required dependencies, presents an installation plan, performs the work from local media only, validates the result, and leaves a durable receipt and logs.

Target machines may reach approved AI service endpoints, but the installer must never depend on target-side downloads from software stores, package registries, extension marketplaces, or update services.

## UI technology

The interactive frontend is a self-contained Windows x64 .NET 10 single-file console executable using Spectre.Console.

Reasons:

- Self-contained single-file deployment means the UI itself does not require a preinstalled .NET runtime.
- .NET 10 is the current LTS line and is suitable for a long-lived enterprise bootstrapper.
- Spectre.Console provides keyboard selection, multi-selection with the spacebar, tables, panels, spinners, progress bars, status displays, and live rendering.
- Windows virtual-terminal capabilities provide modern cursor and formatting behavior, while Spectre.Console handles terminal capability differences.
- The executable includes a `requireAdministrator` application manifest so Windows UAC is the authority for elevation.

Primary references:

- https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview
- https://learn.microsoft.com/en-us/dotnet/core/releases-and-support
- https://learn.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences
- https://learn.microsoft.com/en-us/windows/win32/sbscs/application-manifests
- https://spectreconsole.net/console/
- https://spectreconsole.net/console/prompts/multi-selection-prompt/
- https://spectreconsole.net/console/live/live-display/

## UX flow

### 1. Launch

- Set UTF-8 console mode and an appropriate console size when possible.
- Display product branding immediately.
- UAC elevation is handled by the executable manifest.
- If the professional UI executable is absent, `START-HERE.cmd` falls back to the legacy installer instead of simply failing.

### 2. Animated preflight scan

The scanner checks, without modifying the machine:

- Windows edition and build
- x64 architecture
- administrator state
- free system-drive space
- pending restart markers
- Win32 long-path setting
- Microsoft Office presence, reported version and architecture where detectable
- Python already visible on PATH
- Node.js already visible on PATH
- Git already visible on PATH
- PowerShell 7 already visible on PATH
- VS Code already visible on PATH
- bundle manifest/control files

Future scanner extensions should include:

- Microsoft Installer busy state
- antivirus/quarantine indicators where corporate APIs permit them
- available TEMP space
- corporate execution-policy restrictions
- AppLocker/WDAC denial diagnostics
- SQL Server instance inventory
- local ports used by selected services
- removable-media stability/read-only state
- Office COM launch validation in diagnostics mode

### 3. Setup mode

The user can choose:

- Recommended Professional Setup
- Automation & Office Workstation
- Full-Stack Development Workstation
- Complete Workstation
- Custom Selection
- Diagnostics Only
- Exit

### 4. Core foundation

The Core Foundation is locked and always included. It contains the common runtime and workstation foundation required by the other profiles.

Current core:

- Microsoft Visual C++ runtime
- PowerShell 7
- MinGit
- Portable VS Code
- managed Python 3.11 / 3.12 / 3.13 / 3.14 runtimes
- Node.js LTS
- offline Python and Node package stores
- Microsoft SQL Server ODBC driver
- local Gitea development hub

### 5. Optional professional profiles

Current selectable profiles:

- Office Automation Pro
- PDF Engineering Pro
- OCR & Imaging
- Data & Database Pro
- Full-Stack Web Development
- AI Coding Tools
- Testing & Quality

Each profile owns a separate requirements file. Selecting fewer profiles therefore results in fewer installed packages rather than merely hiding options in the UI.

### 6. Component-level customization

After selecting a profile, the user receives another keyboard-driven multi-selection screen for its components.

Examples:

- Office Automation Pro: Excel file engineering, COM automation, Word, PowerPoint, encryption helpers, legacy formats.
- Data & Database Pro: analytics, DuckDB, SQLite, SQL clients, optional SQL Server Express.
- AI Coding Tools: Codex, Cline, Kilo Code, OpenCode, OpenCode Desktop.

Unsupported choices must be shown as unsupported with a reason, not silently attempted. Claude Code is currently excluded from the guaranteed Windows profile because the corporate environment forbids Git Bash and WSL.

### 7. Installation plan

Before modification, show:

- locked core
- selected profiles
- selected optional native components
- estimated footprint
- safe free-space target
- current free space
- warnings such as pending reboot or missing Office desktop apps

The user then explicitly confirms.

### 8. Execution protocol

The UI writes a versioned JSON plan under `%ProgramData%\OfflineToolsSetup\plans` and invokes `Install-SelectedProfiles.ps1`.

The backend emits machine-readable progress messages:

`@@EVENT|<percentage>|<message>`

The UI converts these into a progress bar and current-step description.

The backend writes a checkpoint after every major phase under:

`C:\OfflineTools\state\setup-state.json`

Major phases:

1. plan validation
2. bundle integrity verification
3. Windows prerequisites
4. native components
5. Python/Node/package layer
6. developer workstation layer
7. post-install validation
8. installation receipt

### 9. Validation

Validation is profile-aware.

Examples:

- Core: managed Python runtime, Node.js, PowerShell 7, Git.
- Office: import automation libraries and, when Microsoft Office is installed, launch and close an isolated Excel COM instance.
- PDF: create a temporary PDF and parse it back.
- Data: import pandas, NumPy, DuckDB and SQLAlchemy.
- Web: import the selected backend frameworks.
- AI tools: verify local CLI launchers exist without downloading anything.

## Integrity model

The final bundle contains a SHA-256 manifest generated only after every payload, profile file, script and the professional UI have been added.

Installation does not begin if integrity verification fails.

A later hardening phase should add Authenticode signature verification for signed vendor executables and code signing for the setup UI itself. PowerShell exposes `Get-AuthenticodeSignature` for this purpose.

Reference:

- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature

## Edge-case policy

### UAC denied

Result: exit cleanly. No partial installation begins.

### Unsupported Windows or architecture

Result: hard stop before mutation. Current target is Windows 10/11 x64.

### Console is too small

Result: request a larger console or switch to a reduced layout. Never draw outside the available buffer.

### Unicode or terminal rendering is limited

Result: fall back to simpler symbols and colors. Functionality must never depend on decorative glyphs.

### Output/input is redirected

Result: interactive mode should refuse or automatically switch to a non-interactive preset/diagnostics mode.

### Insufficient disk space

Result: hard stop before installation. Use estimated footprint plus a safety margin for temporary extraction and installer caches.

### Insufficient TEMP space

Result: detect separately from final install-drive capacity because large installers may unpack into TEMP.

### Pending Windows restart

Result: show a strong warning. Allow an explicit override only when policy permits it.

### Another MSI installation is running

Windows Installer can return 1618 when another installation is already in progress. The orchestrator should wait with a bounded retry policy or ask the user to finish the other installer.

Reference:

- https://learn.microsoft.com/en-us/windows/win32/msi/error-codes

### MSI success requiring restart

Treat 3010 and 1641 as successful outcomes that require restart handling rather than generic failure. The orchestrator should prefer `/norestart` where supported and schedule one controlled restart at the end.

Reference:

- https://learn.microsoft.com/en-us/windows/win32/msi/error-codes

### Files are in use

Prefer Windows Installer packages that cooperate with Restart Manager. Do not kill Office, VS Code, database services, or user applications blindly.

Reference:

- https://learn.microsoft.com/en-us/windows/win32/rstmgr/about-restart-manager

### Existing managed version already matches

Result: validate and skip.

### Existing version is newer than the bundle

Result: do not downgrade automatically. Mark as `newer-present`, validate compatibility, and require explicit repair/downgrade permission if replacement is necessary.

### Existing version is older

Result: upgrade only when the component's installer supports it safely. Otherwise use side-by-side managed locations.

### Existing install is corrupted

Result: offer Repair. Repair must be component-specific rather than a fake global rollback.

### Partial previous setup

Result: load the checkpoint/receipt, rescan reality, and resume idempotently. Never trust only the previous checkpoint; verify the actual component state.

### Power loss or forced shutdown

Result: the next run detects an incomplete state and offers Resume / Repair / Start Over.

### User cancels during planning

Result: no system changes.

### User cancels during execution

Result: stop only at a safe boundary. Do not terminate MSI/database setup processes mid-transaction unless the vendor explicitly supports cancellation.

### Bundle copied incompletely

Result: SHA-256 verification blocks installation before any payload is executed.

### Removable media is disconnected during setup

Result: fail the current phase safely, preserve checkpoint/logs, and allow resume after the media is restored.

### Read-only media

Result: supported. Plans, checkpoints and logs are written under ProgramData / `C:\OfflineTools`, not back into the bundle.

### Antivirus quarantines a payload

Result: integrity verification detects the missing/changed file. Report the exact artifact rather than producing a later obscure installer error.

### Corporate execution policy blocks scripts

Result: the signed/self-contained UI remains the primary frontend. Backend PowerShell is launched explicitly with the expected policy settings, but AppLocker/WDAC policy denials must be reported rather than bypassed.

### Long Windows paths

Enable the Win32 long-path policy where allowed because Python, Node and web projects routinely create deep dependency paths.

Reference:

- https://docs.python.org/3/using/windows.html

### PATH already contains duplicates

Result: normalize and append only managed launcher directories. Do not repeatedly append version-specific runtime folders.

### PATH is near practical limits

Result: use a small number of stable wrapper directories such as `C:\OfflineTools\bin` rather than adding every runtime/package directory.

### Python package missing from wheelhouse

Result: fail before pip is allowed to fall back to any online index. The target environment sets `PIP_NO_INDEX=1` and uses explicit local wheelhouses.

### Python package does not support one interpreter line

Result: the primary managed environment owns the professional package stack. Compatibility Python runtimes may exist side-by-side without forcing every binary package onto every interpreter version.

### Node package missing from cache/payload

Result: hard fail with the package name. The target must never silently contact the public registry.

### VS Code extension missing

Result: target installation uses pre-bundled extension directories / VSIX artifacts. Marketplace fallback is prohibited.

Official VS Code supports portable mode and local VSIX installation:

- https://code.visualstudio.com/docs/setup/portable
- https://code.visualstudio.com/docs/configure/extensions/extension-marketplace

### VS Code update attempts

Result: portable Windows ZIP plus explicit settings disable automatic program/extension updates on target machines.

### Microsoft Office is not installed

Result: file-level Excel/Word/PowerPoint generation remains usable; desktop COM control is marked unavailable and its smoke test is skipped.

### Office architecture/version differs

Result: record x86/x64/version and validate COM behavior. Do not assume a specific Microsoft 365 build.

### Office first-run/license dialogs block automation

Result: COM validation times out and reports an Office readiness issue rather than hanging the entire setup indefinitely.

### Existing Excel instance contains unsaved user work

Result: validation uses an isolated `DispatchEx` instance and never closes arbitrary existing Excel processes.

### Office COM policy is disabled by corporate security

Result: Office file libraries remain installed; COM capability is reported as blocked by policy.

### SQL Server Express already exists

Result: detect the named instance and skip or validate. Never overwrite an existing instance blindly.

### SQL Server port/service conflict

Result: detect before installation and either choose a managed instance configuration or block with a precise message.

### SQL Server offline media not supplied

Result: SQL Server Express remains unavailable/selectable only with a visible warning; DuckDB, SQLite and SQL client libraries still function.

### OCR native media not supplied

Result: do not attempt installation. The UI marks the optional native component unavailable.

### AI service network access fails

Result: this must not affect workstation installation. AI tools are installed locally and later report authentication/network reachability separately.

### Secrets and API keys

Never bake API keys, access tokens or user credentials into the offline bundle, profile JSON, install logs or Git repository.

### Global rollback

Do not promise a single transactional rollback across unrelated MSI, EXE, ZIP, Python, Node and database installers. That would be fiction. The professional model is:

- preflight before mutation
- component-level idempotency
- checkpoints
- component receipts
- vendor-supported uninstall/repair
- resume after interruption

## Logging and receipts

Primary locations:

- `C:\OfflineTools\logs`
- `C:\OfflineTools\state\setup-state.json`
- `C:\OfflineTools\state\last-install.json`
- `%ProgramData%\OfflineToolsSetup\plans`

Logs should contain versions, exit codes, durations and exact failed artifacts, but never credentials or tokens.

## Future UX refinements

- bilingual UI with English as the predictable console-layout default and Arabic help screens
- per-component size estimation from the final generated bundle rather than static estimates
- repair/uninstall screen driven by receipts
- preflight diff showing `Installed / Will install / Will repair / Will skip`
- bounded MSI-busy waiting screen
- reboot coordinator
- resumable media validation
- Authenticode verification and publisher allowlist
- code-sign the bootstrapper
- optional enterprise branding/logo/colors
- exportable diagnostics report for IT support
