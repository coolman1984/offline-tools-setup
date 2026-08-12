from __future__ import annotations

import json
from pathlib import Path

import pytest

from backend import AppBackend, resolve_bundle_root


# ---- resolve_bundle_root -----------------------------------------------

def test_resolve_bundle_root_explicit_flag(repo_root):
    found = resolve_bundle_root(["--bundle-root", str(repo_root)])
    assert found == repo_root.resolve()


def test_resolve_bundle_root_explicit_flag_equals_form(repo_root):
    found = resolve_bundle_root([f"--bundle-root={repo_root}"])
    assert found == repo_root.resolve()


def test_resolve_bundle_root_walks_up_from_a_subdirectory(repo_root, monkeypatch):
    monkeypatch.chdir(repo_root / "desktop-ui" / "qml")
    found = resolve_bundle_root([])
    assert found == repo_root.resolve()


def test_resolve_bundle_root_falls_back_when_nothing_matches(tmp_path):
    found = resolve_bundle_root(["--bundle-root", str(tmp_path)])
    # Falls back to the desktop-ui/.. checkout root rather than raising.
    assert (found / "desktop-ui").is_dir()


# ---- preset / selection state -------------------------------------------

def test_backend_boots_with_the_recommended_preset(backend):
    assert backend.activePreset == "recommended"
    assert backend.selectionSummary["profileCount"] > 0


def test_apply_preset_switches_selection_and_active_preset(backend):
    before = backend.selectionVersion
    backend.applyPreset("complete")
    assert backend.activePreset == "complete"
    assert backend.selectionVersion == before + 1
    # "complete" is defined to include every profile in setup-profiles.json.
    all_profile_ids = {p["id"] for p in backend.appData["profiles"]}
    selected_ids = {p for p in all_profile_ids if backend.isProfileSelected(p)}
    assert selected_ids == all_profile_ids


def test_apply_unknown_preset_does_not_change_the_active_selection(backend):
    before_preset = backend.activePreset
    before_profiles = set(backend._selected_profiles)
    # applyPreset() always bumps selectionVersion/emits selectionChanged as a
    # matter of course, even for an id that doesn't resolve to anything — a
    # harmless redundant re-render, not a change in selection state.
    backend.applyPreset("does-not-exist")
    assert backend.activePreset == before_preset
    assert backend._selected_profiles == before_profiles


def test_use_custom_selection_marks_preset_custom_without_changing_choices(backend):
    selected_before = dict(backend._selected_components)
    backend.useCustomSelection()
    assert backend.activePreset == "custom"
    assert backend._selected_components == selected_before


def test_set_profile_selected_toggles_and_switches_to_custom(backend):
    profile_id = backend.appData["profiles"][0]["id"]
    backend.setProfileSelected(profile_id, True)
    assert backend.isProfileSelected(profile_id) is True
    assert backend.activePreset == "custom"

    backend.setProfileSelected(profile_id, False)
    assert backend.isProfileSelected(profile_id) is False
    # Deselecting drops any per-profile component choices too.
    assert profile_id not in backend._selected_components


def test_set_profile_selected_seeds_default_components(backend):
    profile = next(p for p in backend.appData["profiles"] if p.get("components"))
    backend.setProfileSelected(profile["id"], False)
    backend.setProfileSelected(profile["id"], True)

    expected_defaults = {
        c["id"]
        for c in profile["components"]
        if c.get("selectedByDefault") and c.get("supported", True) is not False
    }
    selected = {
        c["id"]
        for c in profile["components"]
        if backend.isComponentSelected(profile["id"], c["id"])
    }
    assert selected == expected_defaults


def test_set_component_selected_auto_selects_owning_profile(backend):
    profile = next(p for p in backend.appData["profiles"] if p.get("components"))
    component_id = profile["components"][0]["id"]
    backend.setProfileSelected(profile["id"], False)

    backend.setComponentSelected(profile["id"], component_id, True)

    assert backend.isProfileSelected(profile["id"]) is True
    assert backend.isComponentSelected(profile["id"], component_id) is True
    assert backend.activePreset == "custom"


def test_component_hint_falls_back_for_unknown_ids(backend):
    assert backend.componentHint("not-a-real-component-id")
    assert "optional" in backend.componentHint("not-a-real-component-id").lower()


# ---- selection summary / footprint math ----------------------------------

def test_selection_summary_reflects_core_plus_selected_profiles(backend):
    backend.applyPreset("recommended")
    summary = backend.selectionSummary
    core_mb = backend.setup_config["core"]["estimatedMb"]
    profile_mb = sum(
        p["estimatedMb"]
        for p in backend.setup_config["profiles"]
        if backend.isProfileSelected(p["id"])
    )
    assert summary["estimatedMb"] == core_mb + profile_mb
    assert summary["safeGb"] >= summary["estimatedGb"]


# ---- Windows Care preset / selection state -------------------------------

def test_backend_boots_with_quick_health_care_preset(backend):
    quick_health = next(
        p["actions"] for p in backend.care_config["presets"] if p["id"] == "quick-health"
    )
    assert backend.careSummary["selectedCount"] == len(quick_health)


def test_apply_care_preset_replaces_prior_selection(backend):
    backend.setCareSelected("some-made-up-action-id", True)
    backend.applyCarePreset("quick-health")
    assert backend.isCareSelected("some-made-up-action-id") is False


def test_set_care_selected_toggles_membership(backend):
    action_id = backend.care_config["actions"][0]["id"]
    backend.setCareSelected(action_id, True)
    assert backend.isCareSelected(action_id) is True
    backend.setCareSelected(action_id, False)
    assert backend.isCareSelected(action_id) is False


def test_care_summary_separates_repairs_from_diagnostics(backend):
    repair_action = next(a for a in backend.care_config["actions"] if a["mode"] == "repair")
    backend.applyCarePreset("quick-health")
    backend.setCareSelected(repair_action["id"], True)
    summary = backend.careSummary
    assert summary["hasRepairs"] is True
    assert summary["repairCount"] >= 1
    assert summary["selectedCount"] == summary["repairCount"] + summary["diagnosticCount"]


# ---- guardrail summary ----------------------------------------------------

def test_guardrail_summary_reflects_config_flags(backend):
    text = backend.guardrailSummary
    assert text.startswith("The suite never")
    assert "deletes user folders" in text
    assert text.endswith(".")


def test_guardrail_summary_singular_clause_has_no_dangling_or(backend):
    backend.care_config = {"guardrails": {"neverDeleteUserFolders": True}}
    assert backend.guardrailSummary == "The suite never deletes user folders."


def test_guardrail_summary_empty_config_has_a_safe_fallback(backend):
    backend.care_config = {"guardrails": {}}
    assert backend.guardrailSummary == "This suite follows conservative Windows Care guardrails."


# ---- setup plan writing ---------------------------------------------------

def test_write_setup_plan_produces_the_documented_shape(backend, tmp_path):
    backend.applyPreset("recommended")
    path_str = backend.writeSetupPlan()

    assert path_str, "writeSetupPlan should return a non-empty path on success"
    plan_path = Path(path_str)
    assert plan_path.is_file()
    assert str(tmp_path) in str(plan_path)  # honored the redirected PROGRAMDATA

    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    assert plan["SchemaVersion"] == 1
    assert plan["InstallRoot"] == r"C:\OfflineTools"
    assert set(plan["Profiles"]) == backend._selected_profiles
    assert plan["Components"].keys() <= backend._selected_profiles
    assert "ScanRunning" not in plan["Scan"]
    assert "ScannedAt" not in plan["Scan"]


def test_write_setup_plan_flags_ai_tools_only_when_ai_dev_profile_selected(backend):
    backend.applyPreset("recommended")  # does not include ai-dev
    plan = json.loads(Path(backend.writeSetupPlan()).read_text(encoding="utf-8"))
    assert plan["InstallAiTools"] is False

    backend.setProfileSelected("ai-dev", True)
    plan = json.loads(Path(backend.writeSetupPlan()).read_text(encoding="utf-8"))
    assert plan["InstallAiTools"] is True


# ---- stdout protocol parsing ----------------------------------------------

class _FakeProcess:
    """Stands in for the QProcess _read_stdout reads from."""

    def __init__(self, text: str):
        self._data = text.encode("utf-8")

    def readAllStandardOutput(self):
        return self._data


def test_read_stdout_parses_event_protocol(backend):
    seen = []
    backend.progressChanged.connect(lambda pct, msg: seen.append((pct, msg)))
    backend._process = _FakeProcess("@@EVENT|42|Installing things\n")

    backend._read_stdout()

    assert seen == [(42.0, "Installing things")]


def test_read_stdout_clamps_event_percent_to_0_100(backend):
    seen = []
    backend.progressChanged.connect(lambda pct, msg: seen.append((pct, msg)))
    backend._process = _FakeProcess("@@EVENT|150|Overshoot\n@@EVENT|-10|Undershoot\n")

    backend._read_stdout()

    assert seen == [(100.0, "Overshoot"), (0.0, "Undershoot")]


def test_read_stdout_ignores_unrelated_lines(backend):
    seen = []
    backend.progressChanged.connect(lambda pct, msg: seen.append((pct, msg)))
    backend._process = _FakeProcess("just some plain PowerShell output\n")

    backend._read_stdout()

    assert seen == []


def test_read_stdout_parses_care_protocol_as_estimated_progress(backend):
    seen = []
    backend.progressChanged.connect(lambda pct, msg: seen.append((pct, msg)))
    backend._care_action_total = 2
    backend._care_action_done = 0

    backend._process = _FakeProcess("@@CARE|disk-space-analysis|Measuring disk space\n")
    backend._read_stdout()
    backend._process = _FakeProcess("@@CARE|pending-reboot|Checking pending restart\n")
    backend._read_stdout()

    assert seen == [(50.0, "Measuring disk space"), (99.0, "Checking pending restart")]


def test_read_stdout_care_progress_never_reaches_100_percent(backend):
    # 100% is reserved for the real "completed" signal fired from
    # _process_finished; @@CARE| events must never claim full completion
    # on their own, even if more actions report in than were selected.
    seen = []
    backend.progressChanged.connect(lambda pct, msg: seen.append((pct, msg)))
    backend._care_action_total = 1

    backend._process = _FakeProcess("@@CARE|a|first\n@@CARE|b|second\n")
    backend._read_stdout()

    assert all(pct <= 99.0 for pct, _ in seen)


# ---- device section JSON ---------------------------------------------------

def test_device_section_json_prompts_for_a_scan_before_any_data_exists(backend):
    assert "scan" in backend.deviceSectionJson("overview").lower()


def test_device_section_json_scopes_to_the_requested_section(backend):
    backend._device_data = {"computer": {"name": "PC1"}, "network": {"ip": "10.0.0.1"}}
    payload = json.loads(backend.deviceSectionJson("overview"))
    assert "computer" in payload
    assert "network" not in payload
