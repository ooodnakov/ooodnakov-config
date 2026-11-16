"""herdr-task and herdr-artifact: per-folder lists the oo-tasks/oo-artifacts mods read."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

BIN = Path(__file__).resolve().parent.parent / "home" / ".config" / "ooodnakov" / "bin"


def load(module_name: str, filename: str):
    path = BIN / filename
    spec = importlib.util.spec_from_loader(module_name, importlib.machinery.SourceFileLoader(module_name, str(path)))
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def tools(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("OODNAKOV_HERDR_DATA", str(tmp_path / "data"))
    return load("herdr_task_cli", "herdr-task"), load("herdr_artifact_cli", "herdr-artifact")


def test_task_add_list_and_status(tmp_path: Path, tools, capsys: pytest.CaptureFixture[str]) -> None:
    task, _ = tools
    folder = str(tmp_path / "repo")

    assert task.main(["add", "Split", "the importer", "--note", "Then run the tests", "--folder", folder]) == 0
    added = capsys.readouterr().out
    task_id = added.split()[0]
    assert task_id.startswith("t-")

    # The oo-tasks mod reads the same JSON list the command wrote.
    store = Path(os.environ["OODNAKOV_HERDR_DATA"])
    index = json.loads((store / "index.json").read_text(encoding="utf-8"))
    slug = index["folders"][folder.replace("\\", "/")]
    saved = json.loads((store / "tasks" / f"{slug}.json").read_text(encoding="utf-8"))
    assert saved["folder"] == folder.replace("\\", "/")
    assert saved["tasks"][0]["title"] == "Split the importer"
    assert saved["tasks"][0]["note"] == "Then run the tests"

    assert task.main(["list", "--json", "--folder", folder]) == 0
    listing = json.loads(capsys.readouterr().out)
    assert [row["status"] for row in listing["tasks"]] == ["todo"]

    assert task.main(["set", task_id, "doing", "--folder", folder]) == 0
    assert task.main(["list", "--folder", folder]) == 0
    assert capsys.readouterr().out.split("\t")[1] == "doing"

    assert task.main(["rm", task_id, "--folder", folder]) == 0
    assert task.main(["list", "--folder", folder]) == 0
    assert "no tasks" in capsys.readouterr().err


def test_folders_with_the_same_name_get_their_own_lists(tmp_path: Path, tools, capsys: pytest.CaptureFixture[str]) -> None:
    task, _ = tools
    first, second = str(tmp_path / "a" / "repo"), str(tmp_path / "b" / "repo")

    assert task.main(["add", "First", "--folder", first]) == 0
    capsys.readouterr()
    assert task.main(["add", "Second", "--folder", second]) == 0
    capsys.readouterr()

    index = json.loads((Path(os.environ["OODNAKOV_HERDR_DATA"]) / "index.json").read_text(encoding="utf-8"))
    assert index["folders"][first.replace("\\", "/")] != index["folders"][second.replace("\\", "/")]

    assert task.main(["list", "--folder", first]) == 0
    assert "First" in capsys.readouterr().out
    assert task.main(["list", "--folder", second]) == 0
    out = capsys.readouterr().out
    assert "Second" in out and "First" not in out


def test_artifact_versions_and_content(tmp_path: Path, tools, capsys: pytest.CaptureFixture[str]) -> None:
    _, artifact = tools
    folder = str(tmp_path / "repo")
    source = tmp_path / "report.md"
    source.write_text("# Report\n\nAll green.\n", encoding="utf-8")

    assert artifact.main(["add", "Weekly report", "--text", "# Draft", "--folder", folder]) == 0
    artifact_id = capsys.readouterr().out.split()[0]

    assert artifact.main(["show", artifact_id, "--folder", folder]) == 0
    assert capsys.readouterr().out == "# Draft\n"

    assert artifact.main(["update", artifact_id, "--from", str(source), "--folder", folder]) == 0
    assert "v2" in capsys.readouterr().out
    assert artifact.main(["show", artifact_id, "--folder", folder]) == 0
    assert capsys.readouterr().out == "# Report\n\nAll green.\n"

    store = Path(os.environ["OODNAKOV_HERDR_DATA"])
    index = json.loads((store / "index.json").read_text(encoding="utf-8"))
    slug = index["folders"][folder.replace("\\", "/")]
    saved = json.loads((store / "artifacts" / f"{slug}.json").read_text(encoding="utf-8"))
    assert [version["n"] for version in saved["artifacts"][0]["versions"]] == [1, 2]
    assert (store / saved["artifacts"][0]["versions"][1]["path"]).read_text(encoding="utf-8") == "# Report\n\nAll green.\n"

    assert artifact.main(["rm", artifact_id, "--folder", folder]) == 0
    assert not (store / "artifacts" / "files" / artifact_id).exists()


def test_json_flag_before_the_command(tmp_path: Path, tools, capsys: pytest.CaptureFixture[str]) -> None:
    task, _ = tools
    folder = str(tmp_path / "repo")
    assert task.main(["--json", "add", "Hello", "--folder", folder]) == 0
    assert json.loads(capsys.readouterr().out)["title"] == "Hello"


def test_task_label_bind_and_unbind(tmp_path: Path, tools, capsys: pytest.CaptureFixture[str]) -> None:
    task, _ = tools
    folder = str(tmp_path / "repo")
    assert task.main(["add", "Delegated review", "--folder", folder]) == 0
    task_id = capsys.readouterr().out.split()[0]

    # The label is what an agent's terminal carries so the panel finds it again.
    assert task.main(["label", task_id, "--folder", folder]) == 0
    assert capsys.readouterr().out.strip() == f"herdr.task=repo#{task_id}"

    assert task.main(["bind", task_id, "t7", "--folder", folder]) == 0
    assert "t7" in capsys.readouterr().out
    assert task.main(["show", "--json", task_id, "--folder", folder]) == 0
    assert json.loads(capsys.readouterr().out)["terminal"] == "t7"

    assert task.main(["bind", task_id, "--folder", folder]) == 0
    assert "unbound" in capsys.readouterr().out
    assert task.main(["show", "--json", task_id, "--folder", folder]) == 0
    assert json.loads(capsys.readouterr().out)["terminal"] is None


def test_spawn_dry_run_prints_the_hc_command(tmp_path: Path, tools, capsys: pytest.CaptureFixture[str]) -> None:
    task, _ = tools
    folder = str(tmp_path / "repo")
    assert task.main(["add", "Run a review", "--folder", folder]) == 0
    task_id = capsys.readouterr().out.split()[0]

    assert task.main(["spawn", task_id, "--folder", folder, "--dry-run", "--", "claude", "-p", "review"]) == 0
    command = capsys.readouterr().out.strip()
    assert command.startswith("hc run --keep --bg --json")
    assert f"herdr.task=repo#{task_id}" in command
    assert command.endswith("-- claude -p review")
    # A dry run changes nothing.
    assert task.main(["show", "--json", task_id, "--folder", folder]) == 0
    assert json.loads(capsys.readouterr().out).get("terminal") is None

    assert task.main(["spawn", task_id, "--folder", folder, "--dry-run"]) == 1
    assert "spawn needs a program" in capsys.readouterr().err


def test_spawn_keep_open_dry_run_wraps_the_program(tmp_path: Path, tools, capsys: pytest.CaptureFixture[str]) -> None:
    task, _ = tools
    folder = str(tmp_path / "repo")
    assert task.main(["add", "Keep it open", "--folder", folder]) == 0
    task_id = capsys.readouterr().out.split()[0]

    argv = ["spawn", task_id, "--folder", folder, "--dry-run", "--keep-open", "--", "claude", "-p", "review"]
    assert task.main(argv) == 0
    command = capsys.readouterr().out.strip()
    assert command.endswith("""-- sh -c 'claude -p review; exec "${SHELL:-sh}"'""")


def make_repo(path: Path) -> Path:
    def git(*argv: str) -> None:
        subprocess.run(["git", "-C", str(path), *argv], check=True, capture_output=True, text=True)

    path.mkdir()
    git("init", "-q")
    git("config", "user.email", "test@example.com")
    git("config", "user.name", "Test")
    git("commit", "--allow-empty", "-q", "-m", "init")
    return path


def test_spawn_worktree_dry_run_prints_git_then_hc(tmp_path: Path, tools, capsys: pytest.CaptureFixture[str]) -> None:
    task, _ = tools
    repo = make_repo(tmp_path / "repo")
    assert task.main(["add", "Worktree work", "--folder", str(repo)]) == 0
    task_id = capsys.readouterr().out.split()[0]

    argv = ["spawn", task_id, "--folder", str(repo), "--worktree", "--dry-run", "--", "claude"]
    assert task.main(argv) == 0
    worktree = task.normalize(str(repo.parent / "repo-wt" / task_id))
    git_line, hc_line = capsys.readouterr().out.splitlines()
    assert git_line == f"git -C {repo.as_posix()} worktree add -b herdr/{task_id} {worktree}"
    assert hc_line.startswith("hc run --keep --bg --json")
    assert f"--cwd {worktree}" in hc_line
    assert hc_line.endswith("-- claude")
    # A dry run creates no worktree and records nothing.
    assert not (repo.parent / "repo-wt").exists()
    assert task.main(["show", "--json", task_id, "--folder", str(repo)]) == 0
    shown = json.loads(capsys.readouterr().out)
    assert shown.get("worktree") is None and shown.get("branch") is None


@pytest.mark.skipif(shutil.which("git") is None, reason="git is needed to create a worktree")
def test_spawn_worktree_creates_it_and_records_branch(
    tmp_path: Path, tools, capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    task, _ = tools
    repo = make_repo(tmp_path / "repo")
    assert task.main(["add", "Worktree work", "--folder", str(repo)]) == 0
    task_id = capsys.readouterr().out.split()[0]

    real_run = subprocess.run
    hc_calls: list[list[str]] = []

    def fake_run(command, **kwargs):
        if command and command[0] == "hc":
            hc_calls.append(list(command))
            return subprocess.CompletedProcess(command, 0, json.dumps({"address": "t7"}), "")
        return real_run(command, **kwargs)

    monkeypatch.setattr(task.subprocess, "run", fake_run)
    monkeypatch.setattr(task.shutil, "which", lambda name: f"/fake/{name}")

    assert task.main(["spawn", task_id, "--folder", str(repo), "--worktree", "--", "claude"]) == 0
    capsys.readouterr()
    worktree = repo.parent / "repo-wt" / task_id
    assert (worktree / ".git").exists()
    head = subprocess.run(
        ["git", "-C", str(worktree), "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True, check=True
    )
    assert head.stdout.strip() == f"herdr/{task_id}"
    assert hc_calls[0][hc_calls[0].index("--cwd") + 1] == task.normalize(str(worktree))

    assert task.main(["show", "--json", task_id, "--folder", str(repo)]) == 0
    shown = json.loads(capsys.readouterr().out)
    assert shown["worktree"] == task.normalize(str(worktree))
    assert shown["branch"] == f"herdr/{task_id}"
    assert shown["terminal"] == "t7"
