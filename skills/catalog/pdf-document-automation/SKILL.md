---
name: pdf-document-automation
description: Use for professional enterprise PDF inspection, extraction, OCR, manipulation, creation, validation and report production while preserving source evidence and choosing text, rendering and OCR methods appropriately.
compatibility: Offline Python/PDF/OCR toolchain bundled in the Offline Automation & Development Suite.
metadata:
  category: Office & Documents
  version: 1.1.0
---

# PDF Document Automation

## Mission

Treat PDF as both a structured document and a rendered visual artifact. Choose extraction/render/OCR paths based on evidence instead of assuming every PDF is text-readable.

## Inspection order

1. Hash and preserve original.
2. Inspect encryption, permissions, page count, metadata and object health.
3. Attempt native text extraction.
4. Inspect layout/tables/images where required.
5. Render representative pages to verify visual interpretation.
6. Use OCR only for image/scanned regions/pages where text is absent or unreliable.
7. Reconcile extracted/OCR text with page coordinates and confidence.

## Typical offline tools

Use the installed approved stack as appropriate: PyMuPDF, pypdf, pdfplumber, Camelot/Tabula-compatible tooling where dependencies exist, ReportLab/WeasyPrint-compatible creation paths, Pillow/OpenCV and Tesseract or approved OCR engines.

Do not attempt target-side package downloads.

## Extraction contract

Capture:

- document/page metadata
- text with page reference and coordinates when useful
- tables with page/bounding box and extraction method
- images and dimensions when requested
- links/bookmarks/outlines
- forms/annotations where supported
- extraction confidence/warnings
- OCR method/language/confidence for OCR-derived content

Never merge native text and OCR text blindly; deduplicate overlapping regions.

## Creation

For professional generated PDFs:

- define typography and page grid centrally,
- handle page breaks deliberately,
- repeat table headers across pages,
- support long text and overflow,
- embed or substitute fonts legally and consistently,
- use vector charts where practical,
- include document metadata,
- validate rendering after creation.

## Edge cases

Handle encrypted PDFs, permission restrictions, malformed xref/object streams, rotated pages, mixed page sizes, scanned + digital mixed documents, multi-column text, embedded fonts, right-to-left text, Korean/Arabic/English mixtures, huge images, forms, signatures and corrupted pages.

Never remove protection to gain access. If authorized decryption credentials are explicitly supplied, use them only for the requested operation and do not persist them in logs.

## Validation

Reopen the produced PDF, verify page count and basic structure, render sample pages, check expected text/tables, and compare output hash/size against zero/obviously truncated artifacts.

## Execution pack

Use the bundled PDF contract, example and validator:

- `assets/pdf-job.schema.json`
- `templates/pdf-job.example.json`
- `scripts/validate_pdf_output.py`
- `scenarios/README.md`

Treat successful creation as provisional until the validator reopens the PDF and, where requested, renders a representative page.
