from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest
from PySide6.QtCore import QCoreApplication


@pytest.fixture(scope="session", autouse=True)
def qt_app():
    # AppBackend is a QObject; PySide6 needs a live QCoreApplication for
    # signal/slot machinery even when nothing is rendered. QCoreApplication
    # (not QGuiApplication) needs no display/platform plugin, so this runs
    # on a headless CI runner without QT_QPA_PLATFORM tricks.
    app = QCoreApplication.instance() or QCoreApplication(sys.argv[:1])
    yield app


@pytest.fixture
def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


@pytest.fixture
def backend(repo_root, monkeypatch, tmp_path):
    from backend import AppBackend

    plan_dir = tmp_path / "ProgramData"
    monkeypatch.setenv("PROGRAMDATA", str(plan_dir))
    return AppBackend(repo_root)
