# Offline Automation & Development Suite

Professional one-click Windows 10/11 x64 workstation setup for restricted corporate environments.

## Target environment

Target PCs may access approved AI authentication/inference endpoints, but they must not download software, package-manager content, VS Code extensions, updates, or local generative AI models.

Everything required for installation is prepared on a separate connected builder PC and transported inside a verified offline bundle.

## One-click target experience

Run:

```text
START-HERE.cmd
```

The launcher opens the self-contained professional setup interface with Windows administrator elevation.

The setup interface provides:

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

## Locked Core Foundation

Every installation includes the common managed foundation:

- Microsoft Visual C++ runtime
- PowerShell 7
- MinGit
- portable VS Code
- Python 3.11 / 3.12 / 3.13 / 3.14 side-by-side
- isolated managed Node.js LTS
- local Python and Node package stores
- Microsoft SQL Server ODBC driver
- local Gitea development hub

Existing user Python/Node/Git/VS Code installations are not treated as the managed suite. Managed runtimes live under `C:\OfflineTools` to reduce conflicts with existing projects.

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

### AI Coding Tools

Pre-bundled only. Target devices never use extension/package stores.

- Codex
- Cline
- Kilo Code
- OpenCode
- OpenCode Desktop payload

Claude Code is intentionally excluded from the guaranteed Windows profile because the target corporate policy forbids Git Bash and WSL, which its supported Windows runtime path currently requires.

### Testing & Quality

- pytest
- Ruff
- mypy
- formatters

## Presets

- Recommended Professional Setup
- Automation & Office Workstation
- Full-Stack Development Workstation
- Complete Workstation
- Custom Selection
- Diagnostics Only

## Build workflow

On a trusted internet-connected Windows x64 builder PC run:

```text
BUILD-BUNDLE.cmd
```

The builder prepares all runtimes, package stores, VS Code extensions, developer payloads and the self-contained setup UI, then creates the final SHA-256 integrity manifest.

Optional approved native media is supplied under `native-source/` before building.

## Reliability model

The suite uses:

- verify-before-install SHA-256 manifest
- no target-side package/extension downloads
- Windows-native PowerShell/CMD workflow; no Bash/WSL dependency
- side-by-side managed Python versions
- isolated managed Node runtime
- bounded Windows Installer busy retries
- restart-required tracking
- profile-specific smoke tests
- bounded Office COM validation
- checkpoint state under `C:\OfflineTools\state`
- logs under `C:\OfflineTools\logs`
- plans under `%ProgramData%\OfflineToolsSetup\plans`

The project deliberately does not promise a fake single-transaction rollback across unrelated MSI, EXE, ZIP, Python, Node and database installers. Reliability comes from preflight validation, idempotent managed locations, checkpoints, vendor-supported repair/uninstall and safe resume/repair behavior.

## Repository structure

```text
config/                    versions, profiles and policy
requirements/profiles/     selectable Python package profiles
installer-ui/              professional self-contained console UI
scripts/                   builders, installers and validation
docs/                      UX architecture and edge-case policy
templates/                 offline project templates
native-source/             optional approved native media
offline-bundle/            generated transport bundle (ignored by Git)
BUILD-BUNDLE.cmd            connected builder entry point
START-HERE.cmd              restricted target entry point
```

## Validation

GitHub Actions builds the professional UI on Windows, publishes the self-contained x64 executable, validates JSON, parses every PowerShell script, and uploads a test artifact on relevant changes.
