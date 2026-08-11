# Offline Tools Setup

One-click Windows 10/11 developer, data, Office automation, PDF, OCR, database, web-development, Git, VS Code, and AI-agent workstation setup.

## Target-network rule

Target PCs use a restricted corporate network:

- AI authentication/inference traffic may be allowed by corporate policy.
- Program downloads are forbidden.
- Package-registry downloads are forbidden.
- VS Code Marketplace/extension downloads are forbidden.
- Self-updates are disabled.
- No local AI models are installed or downloaded.

Every executable, extension, runtime, package, native dependency, and development tool must therefore be prepared on the connected builder PC and transported inside the verified offline bundle.

## Two-stage design

1. **Connected Bundle Builder** — runs on a trusted internet-connected Windows x64 PC and prepares the complete frozen payload.
2. **Restricted Target Installer** — verifies the payload and installs everything locally with zero target-side downloads.

## Developer workstation

The bundle now prepares:

- Portable Visual Studio Code with a private portable profile
- Pre-bundled VS Code extensions; no Marketplace access required on target PCs
- Git for Windows + Git Bash
- Local Gitea server with SQLite as an offline GitHub-like development hub
- Codex CLI
- Claude Code CLI
- Cline CLI
- Kilo CLI
- OpenCode CLI
- OpenCode Windows desktop payload
- Codex VS Code extension
- Claude Code VS Code extension
- Cline VS Code extension
- Kilo Code VS Code extension
- OpenCode VS Code extension
- Python, PowerShell, Jupyter, ESLint, Prettier, Git tooling extensions
- pnpm, Yarn, TypeScript, TSX, ESLint, Prettier, VS Code extension tooling

ChatGPT/Codex Desktop and Claude Desktop have offline-payload hooks under `vendor/desktop/`. If your organization provides approved offline Windows application packages, place them there before running the bundle builder; they will be transported without target-side downloads.

Kilo currently uses its CLI/VS Code surfaces plus its local browser-based console rather than a Windows desktop application. Cline is supplied through its CLI and VS Code extension.

## Core data and automation stack

### Python

- Python 3.14.x
- Python 3.13.x primary environment
- Python 3.12.x compatibility
- Python 3.11.x legacy compatibility
- Separate local wheelhouse per interpreter line

### Python profiles

- Core developer tooling
- Data analysis/science
- Excel and Microsoft Office automation
- PDF creation/reading/extraction
- OCR and image processing
- Databases/SQL connectivity
- Web/API backend development
- Testing and quality tooling

### Web development

- Node.js LTS
- npm
- pnpm
- Yarn
- TypeScript
- React / Vite
- Next.js
- Express / API tooling
- Prebuilt offline npm payloads/cache

### Databases

- DuckDB
- SQLite tooling
- SQLAlchemy and ODBC clients
- Microsoft SQL Server ODBC driver
- Optional SQL Server Express offline media
- Local Gitea uses SQLite by default

### Office / documents

- Excel: openpyxl, XlsxWriter, pandas, xlrd, pyxlsb
- Office automation: pywin32, comtypes
- Word: python-docx
- PowerPoint: python-pptx
- PDF: PyMuPDF, pypdf, pdfplumber, pikepdf, reportlab

### OCR / images

- RapidOCR baseline
- Optional Tesseract engine + English/Arabic data
- pytesseract
- Pillow
- OpenCV
- Optional heavy OCR package profile when compatible wheels are available

## Security and reliability

- SHA-256 manifest for the complete final payload
- Verify-before-install behavior
- No target-side package or extension downloads
- VS Code program/extension auto-update disabled
- Claude Code updater disabled in the managed environment
- npm forced into offline mode on target PCs
- No local AI models
- Installation logs and smoke tests
- Side-by-side Python versions
- Local Git server bound to `127.0.0.1` by default

## Main entry points

```text
BUILD-BUNDLE.cmd         Run on the connected builder PC
START-HERE.cmd           Run on the restricted target PC
```

## Repository structure

```text
config/                  Version, policy, and profile definitions
requirements/            Python package groups
scripts/                 Builder, installer, verification scripts
templates/               Offline project templates
vendor/desktop/          Optional approved desktop app payloads
offline-bundle/          Generated payload (ignored by Git)
BUILD-BUNDLE.cmd         Complete bundle builder
START-HERE.cmd           One-click target installer
```

Large binary payloads are intentionally not committed to GitHub. The builder creates the transportable bundle for approved USB, external SSD, ISO, or internal transfer media.
