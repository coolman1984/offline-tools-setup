from __future__ import annotations

import ctypes
import os
import subprocess
import sys
from pathlib import Path

from PySide6.QtCore import QTimer, QUrl, Qt
from PySide6.QtGui import QFont, QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle

from backend import AppBackend, resolve_bundle_root


def ensure_windows_admin() -> bool:
    if os.name != "nt":
        return True
    try:
        if ctypes.windll.shell32.IsUserAnAdmin():
            return True
    except (AttributeError, OSError):
        return True

    if Path(sys.argv[0]).suffix.lower() == ".exe":
        executable = str(Path(sys.argv[0]).resolve())
        args = sys.argv[1:]
    else:
        executable = sys.executable
        args = [str(Path(__file__).resolve()), *sys.argv[1:]]
    parameters = subprocess.list2cmdline(args)
    try:
        result = ctypes.windll.shell32.ShellExecuteW(None, "runas", executable, parameters, None, 1)
        return int(result) <= 32
    except (AttributeError, OSError, TypeError):
        return True


def main() -> int:
    smoke_test = "--smoke-test" in sys.argv
    if smoke_test:
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    elif not ensure_windows_admin():
        return 0

    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "FluentWinUI3")
    os.environ.setdefault("QT_QUICK_CONTROLS_HOVER_ENABLED", "1")
    QQuickStyle.setStyle("FluentWinUI3")
    QQuickStyle.setFallbackStyle("Fusion")

    app = QGuiApplication(sys.argv)
    app.setApplicationName("Offline Automation & Development Suite")
    app.setOrganizationName("Offline Tools")
    app.setOrganizationDomain("local.offlinetools")
    app.setFont(QFont("Segoe UI Variable", 10))

    # The product intentionally stays light so workstation status and warnings
    # remain visually consistent on locked-down corporate PCs.
    try:
        app.styleHints().setColorScheme(Qt.ColorScheme.Light)
    except (AttributeError, TypeError):
        pass

    bundle_root = resolve_bundle_root(sys.argv[1:])
    backend = AppBackend(bundle_root)

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)
    qml_path = Path(__file__).resolve().parent / "qml" / "PremiumMain.qml"
    engine.load(QUrl.fromLocalFile(str(qml_path)))
    if not engine.rootObjects():
        return 2

    if smoke_test:
        QTimer.singleShot(800, app.quit)
    else:
        backend.runPreflight()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
