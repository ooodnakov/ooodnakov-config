from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from scripts.cli import lifecycle_tool  # noqa: E402

SENTINEL = "SUPER_SECRET_SENTINEL_7f29"


@pytest.fixture
def isolated_state(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "config"))
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    monkeypatch.setenv("BW_SESSION", SENTINEL)
    monkeypatch.setenv("OPENAI_API_KEY", SENTINEL)
    monkeypatch.setenv("AGENT_CREDENTIAL", SENTINEL)
    return tmp_path


def test_diagnostics_are_versioned_stable_and_secret_free(isolated_state: Path) -> None:
    document = lifecycle_tool.diagnostics(REPO_ROOT, "linux", "minimal", "doctor")
    schema = json.loads((REPO_ROOT / "scripts/cli/schemas/diagnostics-v1.schema.json").read_text(encoding="utf-8"))
    assert schema["properties"]["schema_version"]["const"] == document["schema_version"]
    assert set(schema["required"]) == set(document)

    assert [check["id"] for check in document["checks"]] == [
        "profile.selection",
        "links.managed",
        "dependencies.available",
        "transactions.incomplete",
        "generated.drift",
    ]
    for output_format in ("text", "json"):
        assert SENTINEL not in lifecycle_tool.render_diagnostics(document, output_format)


def test_doctor_and_status_exit_rules(isolated_state: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert lifecycle_tool.cli(["--repo-root", str(REPO_ROOT), "doctor", "--format", "json"]) == 1
    doctor = json.loads(capsys.readouterr().out)
    assert doctor["summary"]["error"] > 0

    assert lifecycle_tool.cli(["--repo-root", str(REPO_ROOT), "status", "--format", "json"]) == 0
    status = json.loads(capsys.readouterr().out)
    assert status["managed_links"]["healthy"] == 0


def test_incomplete_transaction_is_reported_without_leaking_secrets(
    isolated_state: Path,
) -> None:
    journal_dir = isolated_state / "state/ooodnakov-config/transactions"
    journal_dir.mkdir(parents=True)
    journal = {"journal_version": 1, "status": "applying", "error": SENTINEL}
    (journal_dir / "test.json").write_text(json.dumps(journal), encoding="utf-8")

    document = lifecycle_tool.diagnostics(REPO_ROOT, "linux", "minimal", "status")
    assert document["incomplete_transactions"] == 1
    assert SENTINEL not in json.dumps(document)


def test_snapshot_round_trip_contains_only_allowlisted_portable_values(
    isolated_state: Path, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("OOOCONF_THEME", "gruvbox")
    monkeypatch.setenv("OOOCONF_COLOR_MODE", "dark")
    monkeypatch.setenv("UNRECOGNIZED_SETTING", SENTINEL)
    document = lifecycle_tool._snapshot_document(REPO_ROOT, "linux", "terminal")
    rendered = lifecycle_tool.render_snapshot(document)

    assert SENTINEL not in rendered
    assert str(tmp_path) not in rendered
    assert "gruvbox" in rendered
    snapshot = tmp_path / "snapshot.toml"
    snapshot.write_text(rendered, encoding="utf-8")
    loaded = lifecycle_tool.load_snapshot(snapshot, REPO_ROOT, "linux")
    assert loaded == document
    preview = lifecycle_tool.snapshot_preview(loaded, REPO_ROOT, "linux")
    assert preview["valid"] is True
    assert preview["profile"] == "terminal"


@pytest.mark.parametrize(
    "change",
    (
        '\nsecret = "bad"\n',
        '\n[preferences]\nunknown = "bad"\n',
        '\n[preferences]\ntheme = "../../private-key"\n',
    ),
)
def test_snapshot_rejects_non_allowlisted_content(tmp_path: Path, change: str) -> None:
    base = 'version = 1\nprofile = "minimal"\ncapabilities = ["shell"]\n'
    snapshot = tmp_path / "bad.toml"
    snapshot.write_text(base + change, encoding="utf-8")
    with pytest.raises(lifecycle_tool.LifecycleError):
        lifecycle_tool.load_snapshot(snapshot, REPO_ROOT, "linux")


def test_snapshot_apply_plans_then_uses_transaction_executor(
    isolated_state: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    calls: list[str] = []
    original_build_plan = lifecycle_tool.build_plan

    def record_plan(*args: object, **kwargs: object) -> dict[str, object]:
        calls.append("plan")
        return original_build_plan(*args, **kwargs)

    def record_apply(repo_root: Path, platform: str, profile: str) -> tuple[None, int]:
        del repo_root, platform, profile
        calls.append("apply")
        return None, 0

    monkeypatch.setattr(lifecycle_tool, "build_plan", record_plan)
    monkeypatch.setattr(lifecycle_tool, "apply", record_apply)
    monkeypatch.setattr(lifecycle_tool, "_atomic_text", lambda _path, _content: calls.append("profile"))
    document = {
        "version": 1,
        "profile": "minimal",
        "capabilities": ["shell"],
        "preferences": {"theme": "nord"},
    }
    assert lifecycle_tool.apply_snapshot(document, REPO_ROOT, "linux") == 0
    assert calls == ["plan", "apply", "profile"]
    local = isolated_state / "config/ooodnakov/local"
    assert "OOOCONF_THEME=nord" in (local / "env.zsh").read_text(encoding="utf-8")
    assert SENTINEL not in (local / "env.zsh").read_text(encoding="utf-8")
