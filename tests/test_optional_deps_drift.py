"""Drift checks for optional dependency metadata consumers."""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from scripts.read_optional_deps import load_deps, normalized_deps  # noqa: E402


def _catalog_keys() -> list[str]:
    return [dep.get("key", "") for dep in load_deps()["deps"] if dep.get("key")]


def _powershell_completion_keys() -> list[str]:
    content = (REPO_ROOT / "home/.config/ooodnakov/completions/oooconf-completions.ps1").read_text(encoding="utf-8")
    match = re.search(r"\$OooconfDepsKeys\s*=\s*@\((?P<body>.*?)\n\s*\)", content, flags=re.DOTALL)
    assert match, "Failed to find $OooconfDepsKeys block in PowerShell completions"
    return re.findall(r"'([^']+)'", match.group("body"))


def _zsh_completion_keys() -> list[str]:
    content = (REPO_ROOT / "home/.config/ooodnakov/zsh/completions/_oooconf").read_text(encoding="utf-8")
    match = re.search(r"deps_keys=\((?P<body>.*?)\n\)", content, flags=re.DOTALL)
    assert match, "Failed to find deps_keys block in zsh completions"
    return re.findall(r"'([^:']+):", match.group("body"))


def test_completion_keys_match_optional_deps_catalog() -> None:
    expected = _catalog_keys()
    assert _powershell_completion_keys() == expected
    assert _zsh_completion_keys() == expected


def test_completions_generator_uses_canonical_parser() -> None:
    content = (REPO_ROOT / "scripts/generate_oooconf_completions.py").read_text(encoding="utf-8")
    assert "from read_optional_deps import load_deps" in content
    assert "from oooconf_cli_spec import CliSpec, CommandSpec, load_cli_spec" in content
    assert "def parse_optional_deps" not in content
    assert 'eval "local -a' not in content
    assert "${(@P)var_" in content


def test_spec_driven_subcommand_options_are_emitted() -> None:
    zsh_content = (REPO_ROOT / "home/.config/ooodnakov/zsh/completions/_oooconf").read_text(encoding="utf-8")
    assert "oooconf subcommand option" in zsh_content
    assert "--strict-config-paths:strict-config-paths" in zsh_content
    assert "--client-secret:client-secret" in zsh_content

    pwsh_content = (REPO_ROOT / "home/.config/ooodnakov/completions/oooconf-completions.ps1").read_text(
        encoding="utf-8"
    )
    assert "'agents:detect' = @('--repo-root', '--config', '--json')" in pwsh_content
    assert "'agents:mcp:sync' = @('--check')" in pwsh_content
    assert "'secrets:login' = @('--server', '--method', '--client-id', '--client-secret')" in pwsh_content
    assert "'secrets:--method' = @('auto', 'password', 'apikey')" in pwsh_content


def test_spec_driven_subcommand_descriptions_are_emitted() -> None:
    zsh_content = (REPO_ROOT / "home/.config/ooodnakov/zsh/completions/_oooconf").read_text(encoding="utf-8")
    assert "detect:detect configured agent CLIs on PATH" in zsh_content
    assert "forgit-aliases:toggle plain vs forgit git aliases" in zsh_content

    spec_content = (REPO_ROOT / "scripts/oooconf-cli-spec.toml").read_text(encoding="utf-8")
    assert "[commands.agents.subcommand_descriptions]" in spec_content
    assert "[commands.agents.subsubcommands]" in spec_content
    assert 'mcp = ["sync", "status", "add"]' in spec_content
    assert "[commands.shell.subcommand_descriptions]" in spec_content


def test_subsubcommand_metadata_is_emitted_for_zsh_and_powershell() -> None:
    zsh_content = (REPO_ROOT / "home/.config/ooodnakov/zsh/completions/_oooconf").read_text(encoding="utf-8")
    assert "cmd_agents_mcp_subsubcommands=(" in zsh_content
    assert "'sync:synchronize managed MCP servers'" in zsh_content
    assert "cmd_agents_mcp_sync_options=(" in zsh_content
    assert "'--check:check'" in zsh_content

    pwsh_content = (REPO_ROOT / "home/.config/ooodnakov/completions/oooconf-completions.ps1").read_text(
        encoding="utf-8"
    )
    assert "'agents:mcp' = @('sync', 'status', 'add')" in pwsh_content
    assert "'agents:mcp:sync' = @('--check')" in pwsh_content


def test_top_level_command_values_are_emitted() -> None:
    zsh_content = (REPO_ROOT / "home/.config/ooodnakov/zsh/completions/_oooconf").read_text(encoding="utf-8")
    assert "cmd_wm_values=(" in zsh_content
    assert "'komorebi:komorebi'" in zsh_content
    assert "'glazewm:glazewm'" in zsh_content

    pwsh_content = (REPO_ROOT / "home/.config/ooodnakov/completions/oooconf-completions.ps1").read_text(
        encoding="utf-8"
    )
    assert "'wm' = @('komorebi', 'glazewm')" in pwsh_content


def test_oooconf_completions_command_wires_generator() -> None:
    setup_sh = (REPO_ROOT / "scripts/setup.sh").read_text(encoding="utf-8")
    assert 'OOOCONF_COMPLETIONS_GENERATOR="$REPO_ROOT/scripts/generate_oooconf_completions.py"' in setup_sh
    assert 'run_python "$OOOCONF_COMPLETIONS_GENERATOR"' in setup_sh

    setup_ps1 = (REPO_ROOT / "scripts/setup.ps1").read_text(encoding="utf-8")
    assert '$OooconfCompletionsGenerator = Join-Path $PSScriptRoot "generate_oooconf_completions.py"' in setup_ps1
    assert "$null = Run-Python -ScriptPath $scriptPath -ScriptArgs @()" in setup_ps1

    ooosh = (REPO_ROOT / "scripts/ooodnakov.sh").read_text(encoding="utf-8")
    assert "completions)" in ooosh
    assert 'exec_setup_command completions 1 "$@"' in ooosh

    ooops1 = (REPO_ROOT / "scripts/ooodnakov.ps1").read_text(encoding="utf-8")
    assert '"completions" {' in ooops1
    assert 'Invoke-SetupCommand -SetupCommand "completions" -SupportsDryRun -RemainingArgs $remaining' in ooops1


def test_setup_dispatch_uses_handler_metadata() -> None:
    setup_sh = (REPO_ROOT / "scripts/setup.sh").read_text(encoding="utf-8")
    assert 'handler_func="maybe_install_${handler//-/_}"' in setup_sh
    assert (
        'case "$key" in'
        not in setup_sh.split("install_optional_dependency_from_catalog()", 1)[1].split("run_with_spinner()", 1)[0]
    )

    setup_ps1 = (REPO_ROOT / "scripts/setup.ps1").read_text(encoding="utf-8")
    install_fn = setup_ps1.split("function Install-OptionalDependencyFromSpec", 1)[1]
    assert "switch ($handler)" in install_fn


def test_unix_handlers_have_setup_sh_implementations() -> None:
    """Ensure handler-based bash dispatch doesn't silently fall back for unix-special handlers."""
    deps = load_deps()["deps"]
    setup_sh = (REPO_ROOT / "scripts/setup.sh").read_text(encoding="utf-8")

    missing: list[str] = []
    for dep in deps:
        handler = dep.get("handler")
        if not handler:
            continue

        # Only enforce for deps that can apply on Unix, since setup.sh dispatch is Unix-side.
        linux_manager = dep.get("linux.manager")
        macos_manager = dep.get("macos.manager")
        if not linux_manager and not macos_manager:
            continue

        fn_name = f"maybe_install_{str(handler).replace('-', '_')}"
        if f"{fn_name}()" not in setup_sh:
            missing.append(f"{dep.get('key')} -> {fn_name}")

    assert not missing, f"Missing setup.sh handler implementations: {', '.join(missing)}"


def test_documented_optional_dependency_examples_exist_in_catalog() -> None:
    """Ensure README examples do not mention dependency keys missing from the catalog."""
    readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
    catalog = set(_catalog_keys())
    documented: set[str] = set()

    for match in re.finditer(r"oooconf deps (?P<args>[^`\n]+)", readme):
        args = match.group("args").split()
        for arg in args:
            if arg.startswith("-") or arg.startswith("<") or arg.endswith("..."):
                continue
            documented.add(arg.strip(",."))

    assert documented
    assert documented <= catalog, f"README references unknown optional deps: {sorted(documented - catalog)}"


def test_minimal_dependency_keys_exist_in_catalog() -> None:
    """Ensure the documented minimal set stays backed by real optional dependency records."""
    data = load_deps()
    minimal_keys = data.get("minimal", {}).get("keys", [])
    assert minimal_keys == ["git", "zsh", "uv", "oh-my-posh", "gum", "rg", "fd", "bat"]
    assert set(minimal_keys) <= set(_catalog_keys())


def test_catalog_managers_are_handled_by_setup_dispatchers() -> None:
    """Validate every manager used in optional-deps.toml has an installer or explicit path."""
    unix_managers = {dep["manager"] for platform in ("linux", "macos") for dep in normalized_deps(platform)}
    windows_managers = {dep["manager"] for dep in normalized_deps("windows")}

    setup_sh = (REPO_ROOT / "scripts/setup.sh").read_text(encoding="utf-8")
    setup_ps1 = (REPO_ROOT / "scripts/setup.ps1").read_text(encoding="utf-8")

    expected_unix = {"", "apt", "brew", "cargo", "curl", "custom", "download", "github-release", "pip", "pnpm"}
    expected_windows = {"", "cargo", "choco", "custom", "download", "github-release", "pip", "pnpm", "scoop", "winget"}
    assert unix_managers == expected_unix
    assert windows_managers == expected_windows

    for pattern in ["custom|curl)", "pnpm)", "pip)", "github-release)", '"")']:
        assert pattern in setup_sh
    for manager in ["apt", "brew", "cargo"]:
        assert f'if [ "$manager" = "{manager}" ]' in setup_sh or f"{manager})" in setup_sh
    assert "maybe_install_bw()" in setup_sh  # download manager is handled by the bw handler.
    assert "python3 unavailable for pip" in setup_sh
    assert "pip unavailable for $python_cmd" in setup_sh
    assert "return 0" in setup_sh.split("python3 unavailable for pip", 1)[1].split("check_pip_dependency_status", 1)[0]
    assert 'check_pip_dependency_status "$command_name" "$python_cmd"' in setup_sh
    assert 'check_cmd="$python_cmd ${check_cmd#python }"' in setup_sh

    for manager in ["custom", "curl", "winget", "choco", "cargo", "scoop", "pnpm", "github-release", "pip"]:
        assert f'"{manager}" {{' in setup_ps1
    assert '"bw" { return (Install-BitwardenCliIfMissing) }' in setup_ps1  # download manager handler.
    assert "function Get-PythonCommand" in setup_ps1
