from __future__ import annotations

import ctypes
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import tempfile
import threading
from pathlib import Path
from typing import Any

from PySide6.QtCore import QObject, Property, QProcess, QUrl, Signal, Slot
from PySide6.QtGui import QDesktopServices

try:
    import winreg
except ImportError:  # pragma: no cover - non-Windows developer machines
    winreg = None


FRONTMATTER_RE = re.compile(r"^---\s*$", re.MULTILINE)
SKILL_NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def resolve_bundle_root(args: list[str]) -> Path:
    explicit: str | None = None
    for index, arg in enumerate(args):
        if arg == "--bundle-root" and index + 1 < len(args):
            explicit = args[index + 1]
            break
        if arg.startswith("--bundle-root="):
            explicit = arg.split("=", 1)[1]
            break

    candidates: list[Path] = []
    if explicit:
        candidates.append(Path(explicit))
    env_root = os.environ.get("OFFLINE_TOOLS_BUNDLE_ROOT")
    if env_root:
        candidates.append(Path(env_root))
    candidates.extend([Path.cwd(), Path(__file__).resolve().parent])

    exe = Path(sys_executable_dir())
    candidates.append(exe)

    checked: set[Path] = set()
    for candidate in candidates:
        current = candidate.resolve()
        for _ in range(8):
            if current in checked:
                break
            checked.add(current)
            if (current / "config" / "setup-profiles.json").is_file():
                return current
            if current.parent == current:
                break
            current = current.parent

    # Developer checkout fallback. It lets the UI open before a complete bundle exists.
    return Path(__file__).resolve().parents[1]


def sys_executable_dir() -> str:
    import sys

    return str(Path(sys.executable).resolve().parent)


class AppBackend(QObject):
    dataChanged = Signal()
    preflightChanged = Signal()
    selectionChanged = Signal()
    careSelectionChanged = Signal()
    deviceDataChanged = Signal()
    logsChanged = Signal()
    busyChanged = Signal()
    progressChanged = Signal(float, str)
    processFinished = Signal(bool, str)
    toastRequested = Signal(str, str)
    _preflightScanned = Signal(object)

    def __init__(self, bundle_root: Path) -> None:
        super().__init__()
        self.bundle_root = bundle_root.resolve()
        self.setup_config = self._load_json("config/setup-profiles.json", {})
        self.care_config = self._load_json("config/windows-care.json", {})
        self.skills_config = self._load_json("config/skills-hub.json", {})
        self._preflight: dict[str, Any] = self._empty_preflight()
        self._device_data: dict[str, Any] = {}
        self._logs: list[dict[str, Any]] = []
        self._busy = False
        self._process: QProcess | None = None
        self._active_task = ""
        self._active_output = ""
        self._selection_version = 0
        self._care_selection_version = 0
        self._active_preset = "recommended"
        self._selected_profiles: set[str] = set()
        self._selected_components: dict[str, set[str]] = {}
        self._selected_care: set[str] = set()
        self._care_action_total = 0
        self._care_action_done = 0
        self._app_data: dict[str, Any] = {}
        self._preflightScanned.connect(self._apply_preflight)
        self._apply_preset_internal("recommended")
        self._apply_care_preset_internal("quick-health")
        self._rebuild_app_data()
        self._refresh_logs_internal()

    @Property("QVariantMap", notify=dataChanged)
    def appData(self) -> dict[str, Any]:
        return self._app_data

    @Property("QVariantMap", notify=preflightChanged)
    def preflight(self) -> dict[str, Any]:
        return self._preflight

    @Property("QVariantMap", notify=deviceDataChanged)
    def deviceData(self) -> dict[str, Any]:
        return self._device_data

    @Property("QVariantList", notify=logsChanged)
    def logs(self) -> list[dict[str, Any]]:
        return self._logs

    @Property(bool, notify=busyChanged)
    def busy(self) -> bool:
        return self._busy

    @Property(int, notify=selectionChanged)
    def selectionVersion(self) -> int:
        return self._selection_version

    @Property(int, notify=careSelectionChanged)
    def careSelectionVersion(self) -> int:
        return self._care_selection_version

    @Property(str, notify=selectionChanged)
    def activePreset(self) -> str:
        return self._active_preset

    @Property("QVariantMap", notify=selectionChanged)
    def selectionSummary(self) -> dict[str, Any]:
        selected_profiles = self._selected_profile_defs()
        selected_components = sum(len(v) for v in self._selected_components.values())
        estimated_mb = int(self.setup_config.get("core", {}).get("estimatedMb", 0))
        estimated_mb += sum(int(profile.get("estimatedMb", 0)) for profile in selected_profiles)
        estimated_gb = estimated_mb / 1024.0
        safe_gb = int((estimated_gb * 1.25 + 2.0) + 0.999)
        return {
            "profileCount": len(selected_profiles),
            "componentCount": selected_components,
            "estimatedMb": estimated_mb,
            "estimatedGb": round(estimated_gb, 1),
            "safeGb": safe_gb,
            "freeGb": self._preflight.get("FreeDiskGb", 0.0),
            "enoughSpace": float(self._preflight.get("FreeDiskGb", 0.0)) >= safe_gb,
        }

    @Property("QVariantMap", notify=careSelectionChanged)
    def careSummary(self) -> dict[str, Any]:
        actions = {a.get("id"): a for a in self.care_config.get("actions", [])}
        selected = [actions[action_id] for action_id in self._selected_care if action_id in actions]
        repairs = [a for a in selected if a.get("mode") == "repair"]
        long_actions = [a for a in selected if a.get("duration") == "long"]
        return {
            "selectedCount": len(selected),
            "repairCount": len(repairs),
            "diagnosticCount": len(selected) - len(repairs),
            "longCount": len(long_actions),
            "hasRepairs": bool(repairs),
        }

    GUARDRAIL_LABELS: dict[str, str] = {
        "neverDeleteUserFolders": "deletes user folders",
        "neverDisableSecurityControls": "disables security controls",
        "neverModifyBootConfiguration": "changes boot, WinRE, BitLocker or Secure Boot configuration",
        "neverDeleteWinSxSManually": "manually deletes the WinSxS component store",
        "neverDeleteWindowsInstallerCache": "deletes the Windows Installer cache",
        "neverUseDismResetBase": "runs DISM with ResetBase",
        "neverForceChkdskOfflineRepairByDefault": "schedules an offline CHKDSK repair automatically",
        "neverDeleteUpdateRollbackDataWithoutExplicitAdvancedChoice": "deletes Windows Update rollback data without an explicit advanced choice",
    }

    @Property(str, notify=dataChanged)
    def guardrailSummary(self) -> str:
        guardrails = self.care_config.get("guardrails", {})
        clauses = [label for key, label in self.GUARDRAIL_LABELS.items() if guardrails.get(key)]
        if not clauses:
            return "This suite follows conservative Windows Care guardrails."
        if len(clauses) == 1:
            body = clauses[0]
        else:
            body = ", ".join(clauses[:-1]) + " or " + clauses[-1]
        return f"The suite never {body}."

    @Slot(str)
    def applyPreset(self, preset_id: str) -> None:
        self._apply_preset_internal(preset_id)
        self._selection_version += 1
        self.selectionChanged.emit()

    @Slot()
    def useCustomSelection(self) -> None:
        self._active_preset = "custom"
        self._selection_version += 1
        self.selectionChanged.emit()

    def _apply_preset_internal(self, preset_id: str) -> None:
        presets = self.setup_config.get("presets", [])
        preset = next((p for p in presets if p.get("id") == preset_id), None)
        if not preset:
            return
        self._active_preset = preset_id
        self._selected_profiles = set(preset.get("profiles", []))
        self._selected_components = {}
        include_all = preset_id == "complete"
        for profile in self.setup_config.get("profiles", []):
            profile_id = profile.get("id", "")
            if profile_id not in self._selected_profiles or not self._profile_available(profile_id):
                self._selected_profiles.discard(profile_id)
                continue
            chosen: set[str] = set()
            for component in profile.get("components", []):
                if component.get("supported", True) is False or not self._component_available(component.get("id", "")):
                    continue
                if include_all or component.get("selectedByDefault", False):
                    chosen.add(component.get("id", ""))
            self._selected_components[profile_id] = chosen

    @Slot(str, bool)
    def setProfileSelected(self, profile_id: str, selected: bool) -> None:
        if selected:
            if not self._profile_available(profile_id):
                self.toastRequested.emit("Profile unavailable", "Required local installation media is not included in this bundle.")
                return
            self._selected_profiles.add(profile_id)
            profile = self._profile_by_id(profile_id)
            self._selected_components.setdefault(
                profile_id,
                {c.get("id", "") for c in profile.get("components", []) if c.get("selectedByDefault", False) and c.get("supported", True) is not False and self._component_available(c.get("id", ""))},
            )
        else:
            self._selected_profiles.discard(profile_id)
            self._selected_components.pop(profile_id, None)
        self._active_preset = "custom"
        self._selection_version += 1
        self.selectionChanged.emit()

    @Slot(str, str, bool)
    def setComponentSelected(self, profile_id: str, component_id: str, selected: bool) -> None:
        if selected and not self._component_available(component_id):
            self.toastRequested.emit("Component unavailable", "Required local installation media is not included in this bundle.")
            return
        if profile_id not in self._selected_profiles:
            self._selected_profiles.add(profile_id)
        bucket = self._selected_components.setdefault(profile_id, set())
        if selected:
            bucket.add(component_id)
        else:
            bucket.discard(component_id)
        self._active_preset = "custom"
        self._selection_version += 1
        self.selectionChanged.emit()

    @Slot(str, result=bool)
    def isProfileSelected(self, profile_id: str) -> bool:
        return profile_id in self._selected_profiles

    @Slot(str, str, result=bool)
    def isComponentSelected(self, profile_id: str, component_id: str) -> bool:
        return component_id in self._selected_components.get(profile_id, set())

    @Slot(str, result=bool)
    def componentAvailable(self, component_id: str) -> bool:
        return self._component_available(component_id)

    @Slot(str, result=bool)
    def profileAvailable(self, profile_id: str) -> bool:
        return self._profile_available(profile_id)

    def _component_available(self, component_id: str) -> bool:
        requirements = {
            "tesseract": "TesseractMediaPresent",
            "sql-server-express": "SqlServerMediaPresent",
            "webview2": "WebView2MediaPresent",
            "advanced-ocr": "HeavyOcrPresent",
        }
        if component_id in {"dotnet-sdk-10", "msvc-build-tools", "windows-sdk", "cmake", "node-gyp", "node-headers"}:
            return bool(self._preflight.get("VisualStudioBuildToolsMediaPresent", False))
        key = requirements.get(component_id)
        return True if key is None else bool(self._preflight.get(key, False))

    def _profile_available(self, profile_id: str) -> bool:
        if profile_id == "native-build":
            return bool(self._preflight.get("VisualStudioBuildToolsMediaPresent", False))
        return True

    @Slot(str, result=str)
    def componentHint(self, component_id: str) -> str:
        hints = {
            "word-docx": "Create, edit and validate Word documents without relying on cloud services.",
            "powerpoint-pptx": "Generate and automate presentation files for repeatable reporting workflows.",
            "office-encryption": "Adds helpers for protected Office files and controlled local document workflows.",
            "legacy-excel": "Adds support for older workbook formats when a legacy process still depends on them.",
            "pdf-read-write": "Open, modify, merge and split PDF documents locally.",
            "pdf-render": "Render PDF pages to high-quality images for inspection and downstream processing.",
            "pdf-extract": "Extract text and tables from business PDFs for analysis and automation.",
            "pdf-create": "Create polished PDF reports and documents from structured data.",
            "pdf-repair": "Inspect and recover structurally problematic PDF files when possible.",
            "image-processing": "Prepare, clean, resize and transform document images before extraction or reporting.",
            "tesseract": "Optional offline OCR engine. It appears only when approved local media is available.",
            "advanced-ocr": "Heavier OCR libraries for more demanding document-image workloads.",
            "analytics": "Installs the core scientific and data-analysis stack used by reporting automations.",
            "duckdb": "Fast embedded analytical database for large local files and reporting pipelines.",
            "sqlite": "Lightweight local relational database tooling for applications and structured state.",
            "sql-clients": "Drivers and libraries for connecting automation code to enterprise SQL databases.",
            "sql-server-express": "Optional local SQL Server instance from pre-bundled approved installation media.",
            "typescript": "Type-safe JavaScript development tools for modern web applications.",
            "react-vite": "Fast modern frontend stack for internal tools and interactive web applications.",
            "nextjs": "Full-stack React framework for applications that need routing, server logic and deployment structure.",
            "node-backend": "Node.js server and API tooling for local and internal application backends.",
            "python-api": "Python web API libraries for services, automation endpoints and data applications.",
            "quality-tools": "Formatting and linting tools that keep web projects consistent and maintainable.",
            "dotnet-sdk-10": "Modern .NET SDK for Windows applications and components that require the Microsoft toolchain.",
            "msvc-build-tools": "C/C++ compilers required by Python and Node packages that include native code.",
            "windows-sdk": "Windows headers and build support required by native Windows development.",
            "cmake": "Build-system tooling used by many native libraries and extensions.",
            "node-gyp": "Build support for Node.js packages that compile native add-ons.",
            "node-headers": "Local Node.js headers so native add-ons can build without downloading anything.",
            "codex": "Installs the pre-bundled Codex command-line and editor integration payload.",
            "cline": "Installs the pre-bundled Cline command-line and editor integration payload.",
            "kilo": "Installs the pre-bundled Kilo Code command-line and editor integration payload.",
            "opencode": "Installs the pre-bundled OpenCode command-line payload.",
            "opencode-desktop": "Installs the pre-bundled OpenCode desktop application payload.",
            "webview2": "Offline Microsoft browser runtime used by desktop tools that embed modern web interfaces.",
            "claude-code": "Shown for clarity, but unavailable when the required shell runtime is prohibited by policy.",
            "pytest": "Python test runner for repeatable automated verification.",
            "ruff": "Fast Python linting for common correctness and quality problems.",
            "mypy": "Static type checking for larger Python codebases.",
            "formatters": "Automatic code formatting for consistent, reviewable source files.",
        }
        return hints.get(component_id, "Optional capability included in this professional profile.")

    @Slot()
    def runPreflight(self) -> None:
        if self._preflight.get("ScanRunning"):
            return
        self._preflight["ScanRunning"] = True
        self.preflightChanged.emit()
        threading.Thread(target=self._scan_preflight, daemon=True).start()

    def _scan_preflight(self) -> None:
        result = self._empty_preflight()
        is_windows = os.name == "nt"
        result["IsWindows"] = is_windows
        result["Is64Bit"] = (os.environ.get("PROCESSOR_ARCHITECTURE", "").endswith("64") or (8 * __import__("struct").calcsize("P") == 64))
        result["IsAdministrator"] = self._is_admin()
        result["WindowsName"] = self._registry_string(r"SOFTWARE\Microsoft\Windows NT\CurrentVersion", "ProductName") or os.environ.get("OS", "Windows")
        result["WindowsBuild"] = self._registry_string(r"SOFTWARE\Microsoft\Windows NT\CurrentVersion", "CurrentBuildNumber") or "Unknown"
        system_drive = Path(os.environ.get("SystemDrive", "C:") + "\\") if is_windows else Path("/")
        try:
            result["FreeDiskGb"] = round(shutil.disk_usage(system_drive).free / (1024**3), 1)
        except OSError:
            result["FreeDiskGb"] = 0.0
        try:
            result["TempFreeGb"] = round(shutil.disk_usage(Path(tempfile.gettempdir())).free / (1024**3), 1)
        except OSError:
            result["TempFreeGb"] = 0.0
        result["PendingReboot"] = self._pending_reboot()
        result["LongPathsEnabled"] = self._registry_dword(r"SYSTEM\CurrentControlSet\Control\FileSystem", "LongPathsEnabled") == 1
        office = self._detect_office()
        result.update(office)
        result["PythonVersion"] = self._command_version("python", "--version")
        result["NodeVersion"] = self._command_version("node", "--version")
        result["GitVersion"] = self._command_version("git", "--version")
        result["PowerShell7Version"] = self._command_version("pwsh", "-NoLogo", "-NoProfile", "-Command", "$PSVersionTable.PSVersion.ToString()")
        result["VsCodeVersion"] = self._command_version("code", "--version")
        result["BundleManifestPresent"] = (self.bundle_root / "bundle-sha256.json").is_file()
        result["SqlServerMediaPresent"] = (self.bundle_root / "payload/native/sql-server-express/setup.exe").is_file()
        result["TesseractMediaPresent"] = (self.bundle_root / "payload/native/tesseract/tesseract-installer.exe").is_file()
        result["VisualStudioBuildToolsMediaPresent"] = (self.bundle_root / "payload/native/vs-build-tools/vs_BuildTools.exe").is_file()
        result["WebView2MediaPresent"] = (self.bundle_root / "payload/native/webview2/MicrosoftEdgeWebView2RuntimeInstallerX64.exe").is_file()
        heavy_ocr_dirs = list((self.bundle_root / "payload/wheelhouse").glob("py*-ocr-heavy"))
        result["HeavyOcrPresent"] = bool(heavy_ocr_dirs) and all(
            any(path.glob("*.whl")) and not (path / "_missing-packages.txt").exists() for path in heavy_ocr_dirs
        )
        result["ProfessionalUiPresent"] = (self.bundle_root / "payload/bootstrap/OfflineToolsDesktop.exe").is_file()
        result["ScanRunning"] = False
        result["ScannedAt"] = dt.datetime.now().strftime("%Y-%m-%d %H:%M")
        self._preflightScanned.emit(result)

    @Slot(object)
    def _apply_preflight(self, result: object) -> None:
        if isinstance(result, dict):
            self._preflight = result
        if self._active_preset != "custom":
            self._apply_preset_internal(self._active_preset)
            self._selection_version += 1
        self.preflightChanged.emit()
        self.selectionChanged.emit()
        self.toastRequested.emit("Device scan complete", "Workstation readiness has been refreshed.")

    @Slot(result=str)
    def writeSetupPlan(self) -> str:
        try:
            path = self._write_setup_plan()
            self.toastRequested.emit("Plan saved", path)
            return path
        except Exception as exc:  # noqa: BLE001
            self.toastRequested.emit("Plan could not be created", str(exc))
            return ""

    @Slot()
    def startSetup(self) -> None:
        if self._busy:
            self.toastRequested.emit("Another task is running", "Finish the current operation before starting setup.")
            return
        try:
            summary = self.selectionSummary
            if not self._selected_profiles:
                raise RuntimeError("Select at least one professional profile before installing.")
            if self._preflight.get("IsWindows") is False:
                raise RuntimeError("This bundle targets Windows 10/11 x64.")
            if self._preflight.get("IsAdministrator") is False:
                raise RuntimeError("Administrator rights are required for workstation setup.")
            if not self._preflight.get("BundleManifestPresent") or not self._preflight.get("ProfessionalUiPresent"):
                raise RuntimeError("The offline bundle is incomplete or corrupted. Rebuild it before installing.")
            if self._preflight.get("FreeDiskGb", 0) and not summary.get("enoughSpace", True):
                raise RuntimeError("The selected plan needs more free disk space.")
            plan_path = self._write_setup_plan()
            script = self.bundle_root / "scripts/Install-SelectedProfiles.ps1"
            if not script.is_file():
                raise FileNotFoundError(f"Setup backend is missing: {script}")
            shell = self._powershell_path()
            args = ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script), "-PlanPath", plan_path, "-BundleRoot", str(self.bundle_root)]
            self._start_process("setup", shell, args)
        except Exception as exc:  # noqa: BLE001
            self.toastRequested.emit("Setup could not start", str(exc))

    def _write_setup_plan(self) -> str:
        common_data = Path(os.environ.get("PROGRAMDATA", r"C:\ProgramData"))
        plan_dir = common_data / "OfflineToolsSetup" / "plans"
        plan_dir.mkdir(parents=True, exist_ok=True)
        stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        path = plan_dir / f"plan-{stamp}.json"
        profiles = self._selected_profile_defs()
        python_profiles: list[str] = list(self.setup_config.get("core", {}).get("pythonRequirementProfiles", []))
        for profile in profiles:
            for requirement in profile.get("pythonRequirementProfiles", []):
                if requirement not in python_profiles:
                    python_profiles.append(requirement)
        all_components = {component for values in self._selected_components.values() for component in values}
        plan = {
            "SchemaVersion": 1,
            "CreatedAtUtc": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
            "BundleRoot": str(self.bundle_root),
            "InstallRoot": r"C:\OfflineTools",
            "Profiles": [profile.get("id") for profile in profiles],
            "Components": {key: sorted(value) for key, value in self._selected_components.items() if key in self._selected_profiles},
            "PythonRequirementProfiles": python_profiles,
            "IncludeTesseract": "tesseract" in all_components,
            "IncludeSqlServerExpress": "sql-server-express" in all_components,
            "InstallAiTools": "ai-dev" in self._selected_profiles,
            "Scan": {k: v for k, v in self._preflight.items() if k not in {"ScanRunning", "ScannedAt"}},
        }
        path.write_text(json.dumps(plan, indent=2), encoding="utf-8")
        return str(path)

    @Slot(str)
    def applyCarePreset(self, preset_id: str) -> None:
        self._apply_care_preset_internal(preset_id)
        self._care_selection_version += 1
        self.careSelectionChanged.emit()

    def _apply_care_preset_internal(self, preset_id: str) -> None:
        preset = next((p for p in self.care_config.get("presets", []) if p.get("id") == preset_id), None)
        if preset:
            self._selected_care = set(preset.get("actions", []))

    @Slot(str, bool)
    def setCareSelected(self, action_id: str, selected: bool) -> None:
        if selected:
            self._selected_care.add(action_id)
        else:
            self._selected_care.discard(action_id)
        self._care_selection_version += 1
        self.careSelectionChanged.emit()

    @Slot(str, result=bool)
    def isCareSelected(self, action_id: str) -> bool:
        return action_id in self._selected_care

    @Slot()
    def runCare(self) -> None:
        if self._busy:
            self.toastRequested.emit("Another task is running", "Finish the current operation before starting Windows Care.")
            return
        if not self._selected_care:
            self.toastRequested.emit("Nothing selected", "Choose at least one diagnostic or repair action.")
            return
        script = self.bundle_root / "scripts/Invoke-SafeWindowsCare.ps1"
        if not script.is_file():
            self.toastRequested.emit("Windows Care backend is missing", str(script))
            return
        actions = ",".join(sorted(self._selected_care))
        args = ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script), "-Actions", actions, "-BundleRoot", str(self.bundle_root)]
        self._care_action_total = len(self._selected_care)
        self._care_action_done = 0
        self._start_process("care", self._powershell_path(), args)

    @Slot()
    def collectDeviceInventory(self) -> None:
        if self._busy:
            self.toastRequested.emit("Another task is running", "Finish the current operation before refreshing device details.")
            return
        script = self.bundle_root / "scripts/Get-DeviceInventory.ps1"
        if not script.is_file():
            self.toastRequested.emit("Device inventory backend is missing", str(script))
            return
        output = Path(r"C:\OfflineTools\state\device-inventory.json")
        output.parent.mkdir(parents=True, exist_ok=True)
        self._active_output = str(output)
        args = ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script), "-OutputPath", str(output), "-SummaryOnly"]
        self._start_process("inventory", self._powershell_path(), args)

    @Slot(str, result=str)
    def deviceSectionJson(self, section: str) -> str:
        if not self._device_data:
            return "Run a device scan to load the latest read-only workstation inventory."
        keys = {
            "overview": ["computer", "windows", "bios", "cpu", "memoryModules", "gpu"],
            "network": ["networkAdapters", "network"],
            "storage": ["volumes", "disks", "partitions", "physicalDiskHealth"],
            "security": ["security", "recovery", "environment"],
            "problems": ["deviceProblems", "recentCriticalAndErrorEvents"],
            "updates": ["updates", "autoServicesNotRunning", "startupItems"],
        }.get(section, [])
        payload = {key: self._device_data.get(key) for key in keys if key in self._device_data}
        return json.dumps(payload or self._device_data, indent=2, ensure_ascii=False, default=str)

    @Slot()
    def refreshSkills(self) -> None:
        self._rebuild_app_data()
        self.dataChanged.emit()
        self.toastRequested.emit("Skills refreshed", "The local skill library and tool detection were scanned again.")

    @Slot()
    def openSkillsEngine(self) -> None:
        exe = self.bundle_root / "payload/bootstrap/OfflineSkillsHub.exe"
        if exe.is_file():
            try:
                subprocess.Popen([str(exe), str(self.bundle_root)], cwd=str(self.bundle_root))
                return
            except OSError as exc:
                self.toastRequested.emit("Skills engine could not open", str(exc))
                return
        self.toastRequested.emit("Advanced skills engine is not in this checkout", "It is added to the final offline bundle during the build process.")

    @Slot()
    def refreshLogs(self) -> None:
        self._refresh_logs_internal()
        self.logsChanged.emit()

    @Slot(str)
    def openPath(self, path: str) -> None:
        if not path:
            return
        QDesktopServices.openUrl(QUrl.fromLocalFile(path))

    def _start_process(self, task: str, program: str, args: list[str]) -> None:
        if self._process is not None:
            self._process.deleteLater()
        process = QProcess(self)
        process.setProgram(program)
        process.setArguments(args)
        process.setWorkingDirectory(str(self.bundle_root))
        process.setProcessChannelMode(QProcess.ProcessChannelMode.SeparateChannels)
        process.readyReadStandardOutput.connect(self._read_stdout)
        process.readyReadStandardError.connect(self._read_stderr)
        process.finished.connect(self._process_finished)
        process.errorOccurred.connect(self._process_error)
        self._process = process
        self._active_task = task
        self._set_busy(True)
        self.progressChanged.emit(2.0, "Starting…")
        process.start()

    @Slot()
    def _read_stdout(self) -> None:
        if not self._process:
            return
        text = bytes(self._process.readAllStandardOutput()).decode("utf-8", errors="replace")
        for raw in text.splitlines():
            line = raw.strip()
            if line.startswith("@@EVENT|"):
                parts = line.split("|", 2)
                if len(parts) == 3:
                    try:
                        percent = max(0.0, min(100.0, float(parts[1])))
                    except ValueError:
                        percent = 0.0
                    self.progressChanged.emit(percent, parts[2])
            elif line.startswith("@@CARE|"):
                # Invoke-SafeWindowsCare.ps1 reports per-action status as
                # "@@CARE|<action-id>|<message>" instead of a percentage, so
                # progress is estimated from how many of the selected actions
                # have reported in.
                parts = line.split("|", 2)
                if len(parts) == 3:
                    self._care_action_done += 1
                    total = max(self._care_action_total, self._care_action_done)
                    percent = max(0.0, min(99.0, (self._care_action_done / total) * 100.0))
                    self.progressChanged.emit(percent, parts[2])

    @Slot()
    def _read_stderr(self) -> None:
        if not self._process:
            return
        text = bytes(self._process.readAllStandardError()).decode("utf-8", errors="replace").strip()
        if text:
            self.progressChanged.emit(0.0, text.splitlines()[-1][:240])

    def _process_finished(self, exit_code: int, exit_status: QProcess.ExitStatus) -> None:
        success = exit_code == 0 and exit_status == QProcess.ExitStatus.NormalExit
        task = self._active_task
        if task == "inventory" and success:
            try:
                self._device_data = json.loads(Path(self._active_output).read_text(encoding="utf-8-sig"))
                self.deviceDataChanged.emit()
                self.runPreflight()
            except Exception as exc:  # noqa: BLE001
                success = False
                self.toastRequested.emit("Inventory output could not be read", str(exc))
        self._refresh_logs_internal()
        self.logsChanged.emit()
        self._set_busy(False)
        if success:
            self.progressChanged.emit(100.0, "Completed successfully")
            label = {"setup": "Setup completed", "care": "Windows Care completed", "inventory": "Device scan completed"}.get(task, "Task completed")
            self.processFinished.emit(True, label)
        else:
            self.processFinished.emit(False, f"{task.title()} ended with code {exit_code}")
        self._active_task = ""

    def _process_error(self, error: QProcess.ProcessError) -> None:
        if not self._process:
            return
        self._set_busy(False)
        self.processFinished.emit(False, self._process.errorString())

    def _set_busy(self, value: bool) -> None:
        if self._busy != value:
            self._busy = value
            self.busyChanged.emit()

    def _rebuild_app_data(self) -> None:
        self._app_data = {
            "productName": self.setup_config.get("ui", {}).get("productName", "Offline Automation & Development Suite"),
            "subtitle": self.setup_config.get("ui", {}).get("subtitle", "Professional offline workstation control"),
            "core": self.setup_config.get("core", {}),
            "profiles": self.setup_config.get("profiles", []),
            "presets": self.setup_config.get("presets", []),
            "carePresets": self.care_config.get("presets", []),
            "careActions": self.care_config.get("actions", []),
            "guardrails": self.care_config.get("guardrails", {}),
            "skillTargets": self._detect_skill_targets(),
            "skills": self._discover_skills(),
            "bundleRoot": str(self.bundle_root),
        }

    def _discover_skills(self) -> list[dict[str, Any]]:
        roots = [Path(r"C:\OfflineTools\SkillsHub\library"), self.bundle_root / self.skills_config.get("canonicalLibraryRelativePath", "skills/catalog")]
        seen: set[str] = set()
        result: list[dict[str, Any]] = []
        for root in roots:
            if not root.is_dir():
                continue
            for directory in sorted((p for p in root.iterdir() if p.is_dir()), key=lambda p: p.name.lower()):
                if directory.name in seen:
                    continue
                skill_file = directory / "SKILL.md"
                if not skill_file.is_file():
                    continue
                seen.add(directory.name)
                try:
                    text = skill_file.read_text(encoding="utf-8")
                except UnicodeError:
                    text = skill_file.read_text(encoding="utf-8", errors="replace")
                name, description = self._parse_frontmatter(text, directory.name)
                errors: list[str] = []
                if not SKILL_NAME_RE.fullmatch(name):
                    errors.append("Invalid skill name")
                if not description:
                    errors.append("Missing description")
                result.append({
                    "id": name,
                    "name": name,
                    "description": description or "Local managed skill",
                    "status": "Blocked" if errors else "Ready",
                    "path": str(directory),
                    "source": "Managed" if str(root).lower().startswith(r"c:\offlinetools") else "Built-in",
                })
        return result

    @staticmethod
    def _parse_frontmatter(text: str, fallback: str) -> tuple[str, str]:
        lines = text.replace("\r\n", "\n").split("\n")
        if not lines or lines[0].strip() != "---":
            return fallback, ""
        values: dict[str, str] = {}
        for line in lines[1:]:
            if line.strip() == "---":
                break
            if ":" not in line:
                continue
            key, value = line.split(":", 1)
            values[key.strip()] = value.strip().strip('"\'')
        return values.get("name", fallback), values.get("description", "")

    def _detect_skill_targets(self) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        for target in self.skills_config.get("targets", []):
            installed = any(shutil.which(exe) for exe in target.get("executables", []))
            if not installed:
                installed = any(Path(path).is_file() for path in target.get("managedExecutableHints", []))
            result.append({
                "id": target.get("id", ""),
                "name": target.get("displayName", target.get("id", "Unknown")),
                "installed": installed,
                "note": target.get("notes", ""),
            })
        return result

    def _refresh_logs_internal(self) -> None:
        common_data = Path(os.environ.get("PROGRAMDATA", r"C:\ProgramData"))
        roots = [
            (Path(r"C:\OfflineTools\logs"), "Runtime"),
            (Path(r"C:\OfflineTools\state"), "State"),
            (common_data / "OfflineToolsSetup" / "plans", "Plan"),
        ]
        items: list[dict[str, Any]] = []
        for root, kind in roots:
            if not root.is_dir():
                continue
            for path in root.glob("*"):
                if not path.is_file():
                    continue
                try:
                    stat = path.stat()
                except OSError:
                    continue
                items.append({
                    "name": path.name,
                    "path": str(path),
                    "kind": kind,
                    "sizeKb": round(stat.st_size / 1024.0, 1),
                    "modified": dt.datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M"),
                    "mtime": stat.st_mtime,
                })
        items.sort(key=lambda item: item["mtime"], reverse=True)
        self._logs = [{k: v for k, v in item.items() if k != "mtime"} for item in items[:120]]

    def _selected_profile_defs(self) -> list[dict[str, Any]]:
        return [profile for profile in self.setup_config.get("profiles", []) if profile.get("id") in self._selected_profiles]

    def _profile_by_id(self, profile_id: str) -> dict[str, Any]:
        return next((profile for profile in self.setup_config.get("profiles", []) if profile.get("id") == profile_id), {})

    def _powershell_path(self) -> str:
        bundled = self.bundle_root / "payload/developer/powershell/pwsh.exe"
        if bundled.is_file():
            return str(bundled)
        return shutil.which("pwsh") or shutil.which("powershell.exe") or "powershell.exe"

    def _load_json(self, relative: str, default: Any) -> Any:
        path = self.bundle_root / relative
        if not path.is_file():
            return default
        try:
            return json.loads(path.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError):
            return default

    @staticmethod
    def _empty_preflight() -> dict[str, Any]:
        return {
            "IsWindows": True,
            "Is64Bit": True,
            "IsAdministrator": False,
            "WindowsName": "Scanning…",
            "WindowsBuild": "",
            "FreeDiskGb": 0.0,
            "TempFreeGb": 0.0,
            "PendingReboot": False,
            "LongPathsEnabled": False,
            "OfficeInstalled": False,
            "OfficeVersion": "",
            "OfficeArchitecture": "",
            "OfficeProducts": "",
            "PythonVersion": "",
            "NodeVersion": "",
            "GitVersion": "",
            "PowerShell7Version": "",
            "VsCodeVersion": "",
            "BundleManifestPresent": False,
            "SqlServerMediaPresent": False,
            "TesseractMediaPresent": False,
            "VisualStudioBuildToolsMediaPresent": False,
            "WebView2MediaPresent": False,
            "HeavyOcrPresent": False,
            "ProfessionalUiPresent": False,
            "ScanRunning": False,
            "ScannedAt": "Not scanned yet",
        }

    @staticmethod
    def _is_admin() -> bool:
        if os.name != "nt":
            return False
        try:
            return bool(ctypes.windll.shell32.IsUserAnAdmin())
        except (AttributeError, OSError):
            return False

    def _pending_reboot(self) -> bool:
        if winreg is None:
            return False
        keys = [
            r"SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
            r"SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        ]
        for key in keys:
            try:
                handle = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, key)
                handle.Close()
                return True
            except OSError:
                pass
        try:
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SYSTEM\CurrentControlSet\Control\Session Manager") as key:
                winreg.QueryValueEx(key, "PendingFileRenameOperations")
                return True
        except OSError:
            return False

    def _detect_office(self) -> dict[str, Any]:
        data = {
            "OfficeInstalled": False,
            "OfficeVersion": "",
            "OfficeArchitecture": "",
            "OfficeProducts": "",
        }
        if winreg is None:
            return data
        access_flags = [winreg.KEY_READ]
        if hasattr(winreg, "KEY_WOW64_64KEY"):
            access_flags.extend([winreg.KEY_READ | winreg.KEY_WOW64_64KEY, winreg.KEY_READ | winreg.KEY_WOW64_32KEY])
        for access in access_flags:
            try:
                with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Office\ClickToRun\Configuration", 0, access) as key:
                    data["OfficeInstalled"] = True
                    data["OfficeVersion"] = self._query_registry_value(key, "VersionToReport")
                    data["OfficeArchitecture"] = self._query_registry_value(key, "Platform")
                    data["OfficeProducts"] = self._query_registry_value(key, "ProductReleaseIds")
                    return data
            except OSError:
                continue
        return data

    @staticmethod
    def _query_registry_value(key: Any, name: str) -> str:
        try:
            value, _ = winreg.QueryValueEx(key, name)
            return str(value or "")
        except OSError:
            return ""

    def _registry_string(self, path: str, name: str) -> str:
        if winreg is None:
            return ""
        try:
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, path) as key:
                return self._query_registry_value(key, name)
        except OSError:
            return ""

    def _registry_dword(self, path: str, name: str) -> int | None:
        if winreg is None:
            return None
        try:
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, path) as key:
                value, _ = winreg.QueryValueEx(key, name)
                return int(value)
        except (OSError, ValueError, TypeError):
            return None

    @staticmethod
    def _command_version(command: str, *args: str) -> str:
        executable = shutil.which(command)
        if not executable:
            return ""
        try:
            completed = subprocess.run([executable, *args], capture_output=True, text=True, timeout=2.5, creationflags=(0x08000000 if os.name == "nt" else 0))
            text = (completed.stdout + " " + completed.stderr).strip()
            return text.splitlines()[0] if completed.returncode == 0 and text else ""
        except (OSError, subprocess.TimeoutExpired):
            return ""
