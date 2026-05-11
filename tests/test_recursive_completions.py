"""Tests for recursive oooconf completion spec parsing and generation."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from generate_oooconf_completions import (  # noqa: E402
    load_commands,
    load_dependency_definitions,
    render_powershell,
    render_zsh,
    walk_commands,
)
from oooconf_cli_spec import load_cli_spec  # noqa: E402


def write_spec(tmp_path: Path, body: str) -> Path:
    path = tmp_path / "spec.toml"
    path.write_text(body, encoding="utf-8")
    return path


def test_recursive_spec_parses_deep_tree_and_shared_definitions(tmp_path: Path) -> None:
    spec_path = write_spec(
        tmp_path,
        """
[global]
options = { "--repo-root" = "set repo root path" }
completers = { "--repo-root" = "_files -/" }

[definitions.deps_keys]
git = "version control"

[definitions.regions]
"global" = "global region"
china = "China region"

[commands.install]
description = "install things"
value_set = "deps_keys"

[commands.agents]
description = "agent workflows"

[commands.agents.subcommands.mcp]
description = "manage MCP servers"

[commands.agents.subcommands.mcp.subcommands.sync]
description = "sync servers"
options = { "--region" = "provider region" }
option_value_sets = { "--region" = "regions" }

[commands.agents.subcommands.mcp.subcommands.sync.subcommands.audit]
description = "audit sync"
options = { "--repo-root" = "set repo root path" }
completers = { "--repo-root" = "_files -/" }
""",
    )

    spec = load_cli_spec(spec_path)
    assert spec.commands["install"].value_set == "deps_keys"
    sync = spec.commands["agents"].subcommands["mcp"].subcommands["sync"]
    assert sync.option_value_sets == {"--region": "regions"}
    audit = sync.subcommands["audit"]
    assert audit.completers == {"--repo-root": "_files -/"}

    nodes = {node.key: node for node in walk_commands(spec.commands, spec)}
    assert "agents:mcp:sync:audit" in nodes
    assert nodes["install"].values == {"git": "version control"}
    assert nodes["agents:mcp:sync"].option_values["--region"] == {
        "global": "global region",
        "china": "China region",
    }


@pytest.mark.parametrize(
    ("body", "message"),
    [
        (
            """
[commands.check]
alias_for = "doctor"
""",
            "aliases unknown command",
        ),
        (
            """
[commands.install]
value_set = "missing"
""",
            "unknown value_set",
        ),
        (
            """
[commands.test]
options = { "--known" = "known option" }
completers = { "--missing" = "_files" }
""",
            "completer references unknown option",
        ),
        (
            """
[commands.foo-bar]

[commands.foo_bar]
""",
            "collides",
        ),
    ],
)
def test_recursive_spec_validation_errors(tmp_path: Path, body: str, message: str) -> None:
    spec_path = write_spec(tmp_path, body)
    with pytest.raises(ValueError, match=message):
        load_cli_spec(spec_path)


def test_generated_completions_are_depth_agnostic(tmp_path: Path) -> None:
    spec_path = write_spec(
        tmp_path,
        """
[definitions.deps_keys]
git = "version control"

[commands.install]
description = "install things"
value_set = "deps_keys"

[commands.alpha]
description = "alpha root"

[commands.alpha.subcommands.beta]
description = "beta child"

[commands.alpha.subcommands.beta.subcommands.gamma]
description = "gamma child"

[commands.alpha.subcommands.beta.subcommands.gamma.subcommands.delta]
description = "delta child"
options = { "--flag" = "deep flag" }
""",
    )
    spec = load_cli_spec(spec_path)

    zsh = render_zsh(["install", "alpha"], spec)
    ps = render_powershell(["install", "alpha"], spec)

    assert "_oooconf_alpha_beta_gamma_delta()" in zsh
    assert "alpha:beta:gamma:delta" in ps
    assert "git:version control" in zsh
    assert "Values = @('git')" in ps
    assert "Subsub" not in ps
    assert "subsub" not in zsh.lower()


def test_repo_completion_spec_uses_optional_deps_as_shared_definition() -> None:
    spec = load_cli_spec(REPO_ROOT / "scripts/oooconf-cli-spec.toml", extra_definitions=load_dependency_definitions())
    nodes = {node.key: node for node in walk_commands(spec.commands, spec)}

    assert "agents:mcp:sync" in nodes
    assert "wm:bar:set" in nodes
    assert "wget" in nodes["install"].values
    assert "overline-zebar" in nodes["deps"].values
    assert nodes["agents:provider:sync"].option_values["--region"] == {
        "global": "global",
        "china": "china",
    }


def test_generated_files_are_current() -> None:
    spec = load_cli_spec(REPO_ROOT / "scripts/oooconf-cli-spec.toml", extra_definitions=load_dependency_definitions())
    commands = load_commands(REPO_ROOT / "scripts/oooconf-commands.txt")

    assert (REPO_ROOT / "home/.config/ooodnakov/zsh/completions/_oooconf").read_text(encoding="utf-8") == render_zsh(
        commands, spec
    )
    assert (REPO_ROOT / "home/.config/ooodnakov/completions/oooconf-completions.ps1").read_text(
        encoding="utf-8"
    ) == render_powershell(commands, spec)


def test_zsh_completion_file_has_valid_syntax() -> None:
    if not shutil.which("zsh"):
        pytest.skip("zsh is not available")
    result = subprocess.run(
        ["zsh", "-n", "home/.config/ooodnakov/zsh/completions/_oooconf"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr


def test_powershell_completion_resolves_commands_after_global_repo_root() -> None:
    if not shutil.which("pwsh"):
        pytest.skip("pwsh is not available")
    command = (
        ". ./home/.config/ooodnakov/completions/oooconf-completions.ps1; "
        "$ast = [scriptblock]::Create('oooconf -C /tmp agents mcp ').Ast.EndBlock.Statements[0].PipelineElements[0]; "
        "Get-OooconfCompletions -wordToComplete '' -commandAst $ast -cursorPosition 27 | ForEach-Object CompletionText"
    )
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    assert {"sync", "status", "add"}.issubset(set(result.stdout.splitlines()))
