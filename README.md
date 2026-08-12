# Offline Automation & Development Suite

Professional one-click Windows 10/11 x64 workstation setup and safe-care toolkit for restricted corporate environments.

## Target environment

Target PCs may access approved AI authentication/inference endpoints, but they must not download software, package-manager content, VS Code extensions, updates, or local generative AI models.

Everything required for installation is prepared on a separate connected builder PC and transported inside a verified offline bundle.

## One-click target experience

Run:

```text
START-HERE.cmd
```

The launcher opens the self-contained elevated **desktop control surface** (PySide6 + Qt Quick, `desktop-ui/`) when it is present in the bundle:

```text
Home  |  Setup  |  Safe Repair  |  Device Details  |  Skills Hub  |  Logs & Evidence
```

If the desktop executable is missing from the bundle, `START-HERE.cmd` falls back in order to the tabbed console suite shell, then the setup engine alone, then the legacy console installer — each with a plain-English explanation rather than a silent failure:

```text
SETUP  |  SAFE REPAIR  |  DEVICE DETAILS  |  LOGS
```

Both interfaces keep workstation setup separated from Windows repair/diagnostics and drive the same PowerShell engines under `scripts/`. See `desktop-ui/README.md` for the desktop control surface's architecture and local-development instructions.

## SETUP

The professional setup engine provides:

- animated workstation preflight scan
- keyboard navigation
- Space to select/unselect profiles and components
- locked Core Foundation included in every setup
- recommended presets plus full custom selection
- disk/TEMP/restart/Office/tool detection
- visibility of optional native media before it can be selected
- installation plan before system changes
- live progress reporting
- profile-aware validation
- durable logs, checkpoints and receipts

## SAFE REPAIR

Windows Safe Care is conservative by design.

Read-only presets:

- Quick Health Check
- Deep Diagnostics
- All Diagnostics

Custom mode allows individual diagnostics and explicitly selected low/moderate-risk repairs.

Built-in checks include:

- disk-space/candidate analysis
- pending restart detection
- Windows Installer health
- Windows time/synchronization health
- Windows runtime and recovery readiness
- WinRE, BitLocker, TPM and Secure Boot servicing state
- development environment/PATH/policy readiness
- DISM component-store checks
- SFC verify-only
- online CHKDSK scan
- physical disk reliability/health
- Plug and Play device problems
- critical/error event summaries
- Windows Update health
- VSS health
- power/battery diagnostics

Optional safe repairs include:

- stale temporary-file cleanup from approved temp folders only
- Delivery Optimization cache cleanup using the Windows command
- supported DISM component cleanup without ResetBase
- Windows image repair only from a metadata-verified matching pre-bundled local source with network fallback disabled
- SFC repair
- reversible-first Windows Update working-cache rebuild

Selected repairs attempt a Windows restore point first where the feature and policy allow it.

Permanent guardrails prohibit user-folder deletion, registry cleaners, manual WinSxS deletion, Windows Installer cache deletion, boot/WinRE/BitLocker/Secure Boot changes, security-control bypass, automatic driver replacement/removal, DISM ResetBase and automatic offline CHKDSK repair scheduling.

See `docs/WINDOWS-SAFE-CARE.md`.

## DEVICE DETAILS

Read-only device intelligence subviews:

- Overview
- Network & IP
- Storage & Disk Health
- Security & Policy
- Problems & Events
- Updates & Services

The structured inventory includes hardware, BIOS, CPU, memory, GPU, disks/partitions, disk reliability counters, IP addresses, gateways, DNS, Windows version/build/revision, BitLocker, TPM, Secure Boot servicing state, WinRE information, updates, device problems, startup items, services, policy and recent critical events.

The suite also writes the full inventory to:

```text
C:\OfflineTools\state\device-inventory.json
```

## Skills Hub

A canonical local library of AI development skills lives under `skills/catalog/`. Each skill carries a `SKILL.md` contract, starter templates and deterministic validation scripts, and can be published to whichever supported AI coding tools are detected on the workstation (Codex, Claude Code, Cline, Kilo Code, OpenCode) without any of them maintaining a separate copy.

The desktop UI's Skills Hub page provides search, validation status and AI-target detection directly; the standalone `skills-hub/` engine handles advanced deployment, creation, import and Project Brain operations during the interface migration. See `docs/SKILLS-HUB-ARCHITECTURE.md`.

## Locked Core Foundation

Every installation includes the common managed foundation:

- Microsoft Visual C++ runtimes for x64 and x86
- PowerShell 7
- MinGit
- isolated Portable Git Bash fallback
- portable VS Code
- Python 3.11 / 3.12 / 3.13 / 3.14 side-by-side
- isolated managed Node.js LTS
- local Python and Node package stores
- Microsoft SQL Server ODBC driver
- local Gitea development hub

Existing user Python/Node/Git/VS Code installations are not treated as the managed suite. Managed runtimes live under `C:\OfflineTools` to reduce conflicts with existing projects.

Only `C:\OfflineTools\bin` is exposed as the managed command gateway. Tool directories are not scattered across the machine PATH.

## Selectable professional profiles

### Office Automation Pro

- Excel file engineering
- Microsoft Office COM automation
- Word document automation
- PowerPoint automation
- Office encryption helpers
- optional legacy Excel support

### PDF Engineering Pro

- PDF read/write/manipulation
- rendering
- text/table extraction
- PDF creation/reporting
- repair/structural tools

### OCR & Imaging

- image processing
- optional Tesseract OCR when approved native media is supplied
- optional advanced OCR package profile

### Data & Database Pro

- analytics/scientific stack
- DuckDB
- SQLite tooling
- SQL clients
- optional SQL Server Express from complete offline media

### Full-Stack Web Development

- TypeScript toolchain
- React + Vite
- Next.js
- Node backend tooling
- Python API/backend tooling
- linting/formatting
- optional native Microsoft C/C++ build toolchain
- .NET 10 SDK
- pre-bundled Node headers for native add-ons

### AI Coding Tools

Pre-bundled only. Target devices never use extension/package stores.

- Codex CLI / VS Code integration
- Claude Code CLI / VS Code extension
- Cline CLI / VS Code extension
- Kilo Code CLI / VS Code extension
- OpenCode CLI / VS Code extension
- OpenCode Desktop payload

PowerShell and Command Prompt remain the primary shells. Portable Git Bash exists only as an isolated compatibility fallback. Claude Code uses the managed Bash path when corporate application-control policy permits it; if Bash execution is blocked, Claude Code alone is unavailable and the rest of the suite remains operational.

### Testing & Quality

- pytest
- Ruff
- mypy
- formatters

## Build workflow

On a trusted internet-connected Windows x64 builder PC run:

```text
BUILD-BUNDLE.cmd
```

The builder prepares runtimes, package stores, VS Code extensions, AI/developer payloads, Portable Git Bash, native build tooling, both self-contained interfaces, Windows Care configuration, and the final SHA-256 integrity manifest.

Optional approved native media is supplied under `native-source/` before building.

Optional Windows repair sources should first be prepared with:

```powershell
scripts\Prepare-WindowsRepairSource.ps1 -SourceWindowsPath <expanded Windows directory>
```

Prepared builder profiles use:

```text
native-source/windows-repair/<PROFILE_ID>/
  source-metadata.json
  Windows/
```

The final bundle preserves them under:

```text
payload/windows-repair/<PROFILE_ID>/
  source-metadata.json
  Windows/
```

Windows Care permits local DISM repair only when source metadata matches the target build, UBR/revision, architecture and system language; `/LimitAccess` disables Windows Update fallback.

## Reliability model

The suite uses:

- verify-before-install SHA-256 manifest
- no target-side package/extension downloads
- PowerShell/CMD-first Windows workflow
- isolated optional Git Bash compatibility fallback
- side-by-side managed Python versions
- isolated managed Node runtime
- local Node headers and native build toolchain
- bounded Windows Installer busy retries
- restart-required tracking
- profile-specific smoke tests
- bounded Office COM validation
- conservative Windows Care guardrails
- read-only recovery/encryption/boot readiness diagnostics
- restore-point attempt before selected repairs
- evidence-first and reversible-first maintenance
- checkpoint state under `C:\OfflineTools\state`
- logs under `C:\OfflineTools\logs`
- plans under `%ProgramData%\OfflineToolsSetup\plans`

The project deliberately does not promise a fake single-transaction rollback across unrelated MSI, EXE, ZIP, Python, Node, Windows servicing and database installers. Reliability comes from preflight validation, managed isolated locations, checkpoints, reversible-first maintenance, vendor-supported servicing and safe resume/repair behavior.

## Repository structure

```text
config/                    versions, setup profiles, developer and Windows Care policy
requirements/profiles/     selectable Python package profiles
desktop-ui/                primary PySide6/Qt Quick desktop control surface
installer-ui/              professional setup engine (console-fallback UI)
suite-shell/               tabbed terminal application (console-fallback UI)
skills-hub/                standalone Skills Hub engine (advanced operations)
skills/catalog/            canonical local AI development skill library
scripts/                   builders, installers, diagnostics and Windows Care engine
docs/                      architecture, compatibility and safety policy
templates/                 offline project templates
native-source/             optional approved native/Windows repair media
offline-bundle/            generated transport bundle (ignored by Git)
BUILD-BUNDLE.cmd            connected builder entry point
START-HERE.cmd              restricted target entry point
```

## Validation

GitHub Actions builds the PySide6 desktop control surface and the console-fallback Windows applications, publishes all self-contained x64 executables, runs the desktop UI's pytest suite and QML lint, validates all JSON configuration including Windows Care, parses every PowerShell script, validates the canonical skill catalog and its executable scenario tests, verifies the produced executables and uploads a test artifact on relevant changes.

## Contributing

See `CONTRIBUTING.md` for how to propose a change and which checks to run locally, and `SECURITY.md` to report a vulnerability privately.

## License

MIT — see `LICENSE`.
