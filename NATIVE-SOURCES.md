# Native Offline Sources

The target PCs must never download from the internet. Some native Windows products therefore require complete installation media to be staged on the connected bundle-builder PC before the final bundle is created.

## SQL Server 2022 Express

Do not copy only the small `SQL2022-SSEI-Expr.exe` web bootstrapper to an offline target. On a trusted connected Windows PC:

1. Download SQL Server 2022 Express from Microsoft.
2. Run the bootstrapper as Administrator.
3. Choose **Download Media**.
4. Choose the x64 Express/Core media.
5. Obtain `SQLEXPR_x64_ENU.exe`.
6. Extract that package to:

```text
native-source/sql-server-express/
```

The result must contain this file at the root:

```text
native-source/sql-server-express/setup.exe
```

The complete bundle builder detects that file and copies the whole extracted SQL Server media into the offline bundle. The target installer then runs `setup.exe` locally with updates disabled and no network dependency.

SQL Server Express is optional. If the media is absent, the bundle still includes DuckDB, SQLite support, SQLAlchemy, pyodbc, pymssql, and the Microsoft ODBC Driver for SQL Server.

## Tesseract OCR for Windows

The Tesseract project documentation points Windows users to the UB Mannheim Windows builds. That Windows installer is a third-party binary distribution, not an official Microsoft or Python package.

If Tesseract is required, obtain the trusted x64 installer on the connected builder PC and place it as:

```text
native-source/tesseract/tesseract-installer.exe
```

The bundle builder will include it and will also download the English and Arabic Tesseract model files from the official `tesseract-ocr/tessdata_fast` repository. The final bundle hash manifest protects those exact copied files during transport.

Tesseract is optional because the recommended Python environment already includes `rapidocr-onnxruntime` as an offline OCR baseline.

## Build

After optional native sources are staged, run:

```text
BUILD-BUNDLE.cmd
```

This builds `offline-bundle/`, downloads the Microsoft Visual C++ runtime and Microsoft ODBC Driver while the builder has internet access, creates Python wheelhouses and the npm cache, copies optional native media, and produces a final SHA-256 manifest.

Move only the completed `offline-bundle/` to the isolated target machine. On the target machine run:

```text
START-HERE.cmd
```

The target installer uses local files only.
