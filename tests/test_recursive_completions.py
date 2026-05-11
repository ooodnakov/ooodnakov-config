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


def test_zsh_completion_interactively_resolves_subcommand_values() -> None:
    if not shutil.which("zsh") or not shutil.which("expect"):
        pytest.skip("zsh and expect are required for interactive completion smoke test")

    completions_dir = (REPO_ROOT / "home/.config/ooodnakov/zsh/completions").as_posix()
    bin_dir = (REPO_ROOT / "home/.config/ooodnakov/bin").as_posix()

    def run_completion(command: str, expected: str, sentinel: str) -> str:
        script = f"""
set timeout 5
spawn env TERM=xterm-256color zsh -dfi
expect "%"
send {{PATH={bin_dir}:$PATH; fpath=({completions_dir} $fpath); autoload -Uz compinit; compinit -D; bindkey "^I" complete-word\r}}
expect "%"
send "{command}"
expect {{
    "{expected}" {{ puts "{sentinel}" }}
    timeout {{ puts "TIMEOUT_{sentinel}" }}
}}
send "\003exit\r"
expect eof
"""
        result = subprocess.run(
            ["expect", "-c", script],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, result.stderr
        return result.stdout

    agents_output = run_completion("oooconf agents \t\t", "detect", "FOUND_DETECT")
    install_output = run_completion("oooconf install wez\t", "wezterm", "FOUND_WEZTERM")

    assert "FOUND_DETECT" in agents_output
    assert "FOUND_WEZTERM" in install_output
    assert "TIMEOUT_" not in agents_output + install_output


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


def test_zsh_dispatch_scans_actual_subcommand_position_after_global_options(tmp_path: Path) -> None:
    spec_path = write_spec(
        tmp_path,
        """
[global]
options = { "-C" = "set repo root path", "--repo-root" = "set repo root path" }
completers = { "-C" = "_files -/", "--repo-root" = "_files -/" }

[commands.agents]
description = "agent workflows"

[commands.agents.subcommands.mcp]
description = "manage MCP servers"

[commands.agents.subcommands.mcp.subcommands.sync]
description = "sync servers"
""",
    )
    spec = load_cli_spec(spec_path)

    zsh = render_zsh(["agents"], spec)

    assert "_oooconf_option_takes_value" in zsh
    assert "_oooconf_global_opts_with_args=(-C --repo-root)" in zsh
    assert "case $words[3]" not in zsh
    assert 'token="$words[i]"' in zsh
    assert "'1:subcommand:->command'" in zsh
    assert 'words=("${(@)words[i,-1]}")' in zsh
    assert "_oooconf_agents_mcp" in zsh


def test_zsh_shared_value_sets_are_emitted_once(tmp_path: Path) -> None:
    spec_path = write_spec(
        tmp_path,
        """
[definitions.deps_keys]
git = "version control"

[commands.install]
description = "install things"
value_set = "deps_keys"

[commands.deps]
description = "install deps"
value_set = "deps_keys"
""",
    )
    spec = load_cli_spec(spec_path)

    zsh = render_zsh(["install", "deps"], spec)

    assert zsh.count("typeset -ga _oooconf_values_deps_keys") == 1
    assert zsh.count("'git:version control'") == 1
    assert zsh.count('values=("${_oooconf_values_deps_keys[@]}")') == 2
    assert "'1:value:->value'" in zsh


def test_powershell_parser_keeps_boolean_flag_following_subcommand(tmp_path: Path) -> None:
    if not shutil.which("pwsh"):
        pytest.skip("pwsh is not available")
    spec_path = write_spec(
        tmp_path,
        """
[commands.root]
description = "root command"
options = { "--flag" = "boolean flag", "--config" = "config path" }
completers = { "--config" = "_files" }

[commands.root.subcommands.child]
description = "child command"

[commands.root.subcommands.child.subcommands.leaf]
description = "leaf command"
""",
    )
    spec = load_cli_spec(spec_path)
    completion_path = tmp_path / "completion.ps1"
    completion_path.write_text(render_powershell(["root"], spec), encoding="utf-8")
    command = (
        f". {completion_path}; "
        "$ast = [scriptblock]::Create('oooconf root --flag child ').Ast.EndBlock.Statements[0].PipelineElements[0]; "
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
    assert "leaf" in result.stdout.splitlines()
    assert "child" not in result.stdout.splitlines()


def test_powershell_command_regex_accepts_windows_backslash_paths() -> None:
    spec = load_cli_spec(REPO_ROOT / "scripts/oooconf-cli-spec.toml", extra_definitions=load_dependency_definitions())
    ps = render_powershell(["install"], spec)

    assert "(^|[\\\\\\\\/])(oooconf|o)" in ps
