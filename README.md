# Offline Tools Setup

One-click Windows 10/11 developer, data, Office automation, PDF, OCR, database, and full-stack setup for machines that never connect to the internet.

## Core rule

Target machines must perform **zero network downloads**. Every installer, runtime, wheel, package, database component, language file, and dependency must already exist inside the offline bundle.

The project therefore has two stages:

1. **Bundle Builder** — runs on a trusted internet-connected Windows x64 machine and downloads/locks all required artifacts.
2. **Offline Installer** — runs on Windows 10/11 target machines and installs only from local media after integrity checks.

## Planned default stack

### Python

- Python 3.14.x — newest feature line
- Python 3.13.x — primary compatibility line
- Python 3.12.10 — last 3.12 Windows binary installer
- Python 3.11.9 — last 3.11 Windows binary installer

Each Python line gets its own local wheelhouse because binary package support differs by interpreter version.

### Python package profiles

- Core developer tooling
- Data analysis and science
- Excel and Microsoft Office automation
- PDF creation, reading, extraction, and conversion
- OCR and image processing
- Databases and SQL connectivity
- Web/API backend development
- Testing and quality tooling

### Web development

- Node.js LTS
- npm
- TypeScript
- React / Vite
- Next.js
- Express / API tooling
- Offline npm cache/package bundle

### Databases

- DuckDB
- SQLite tooling
- SQLAlchemy and ODBC client libraries
- Microsoft SQL Server Express/Developer media as an optional profile
- Microsoft SQL Server ODBC driver

### Office / document automation

- Excel: openpyxl, XlsxWriter, pandas, xlrd, pyxlsb
- Office COM automation: pywin32, comtypes
- Word: python-docx
- PowerPoint: python-pptx
- PDF: PyMuPDF, pypdf, pdfplumber, pikepdf, reportlab

### OCR / images

- Tesseract OCR engine and selected language packs
- pytesseract
- Pillow
- OpenCV
- optional heavy OCR profile for EasyOCR/PaddleOCR when compatible wheels are available

## Safety and reliability

The generated bundle will contain a SHA-256 manifest. The offline installer verifies files before executing them. Installation is resumable, logged, idempotent where possible, and never falls back to internet package sources.

## Repository structure

```text
config/                 Version and profile definitions
requirements/           Python package groups
scripts/                Builder, installer, verification scripts
offline-bundle/         Generated payload (ignored by Git)
START-HERE.cmd          One-click entry point on target machines
```

Large binary installers are intentionally not committed to GitHub. The builder creates the transportable offline bundle for USB, external SSD, ISO, or approved internal file transfer.

## Status

Initial architecture and bootstrap implementation are in progress.
