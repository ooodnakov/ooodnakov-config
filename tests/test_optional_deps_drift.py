"""Drift checks for optional dependency metadata consumers."""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from scripts.cli.read_optional_deps import load_deps, normalized_deps  # noqa: E402


def _catalog_keys() -> list[str]:
    return [dep.get("key", "") for dep in load_deps()["deps"] if dep.get("key")]


def _powershell_completion_keys() -> list[str]:
    content = (REPO_ROOT / "home/.config/ooodnakov/completions/oooconf-completions.ps1").read_text(encoding="utf-8")
    match = re.search(r"'install' = @\{(?P<body>.*?)\n\s*}\n", content, flags=re.DOTALL)
    assert match, "Failed to find install node in PowerShell completions"
    values = re.search(r"Values = @\((?P<values>.*?)\)", match.group("body"), flags=re.DOTALL)
    assert values, "Failed to find install dependency values in PowerShell completions"
    return re.findall(r"'([^']+)'", values.group("values"))


def _zsh_completion_keys() -> list[str]:
    content = (REPO_ROOT / "home/.config/ooodnakov/zsh/completions/_oooconf").read_text(encoding="utf-8")
    shared = re.search(r"_oooconf_values_deps_keys=\((?P<body>.*?)\n\)", content, flags=re.DOTALL)
    if shared:
        return re.findall(r"'([^:']+):", shared.group("body"))

    match = re.search(r"_oooconf_install\(\).*?values=\((?P<body>.*?)\n\s*\)", content, flags=re.DOTALL)
    assert match, "Failed to find install value block in zsh completions"
    return re.findall(r"'([^:']+):", match.group("body"))


def test_completion_keys_match_optional_deps_catalog() -> None:
    expected = _catalog_keys()
    assert _powershell_completion_keys() == expected
    assert _zsh_completion_keys() == expected


def test_completions_generator_uses_canonical_parser() -> None:
    content = (REPO_ROOT / "scripts/cli/generate_oooconf_completions.py").read_text(encoding="utf-8")
    assert "from read_optional_deps import load_deps" in content
    assert "from oooconf_cli_spec import CliSpec, Command, load_cli_spec, shell_safe_name" in content
    assert "def parse_optional_deps" not in content
    assert 'eval "local -a' not in content
    assert "def walk_commands" in content
    assert "subsubcommand" not in content.lower()
    assert "scripts/generate_oooconf_completions.py" not in content
    assert "scripts/oooconf-cli-spec.toml" not in content


def test_autogen_completion_manifest_descriptions_are_clean() -> None:
    content = (REPO_ROOT / "scripts/generate/autogen-completions.txt").read_text(encoding="utf-8")
    assert "comepltions" not in content
    assert "Generate " not in content


def test_spec_driven_subcommand_options_are_emitted() -> None:
    zsh_content = (REPO_ROOT / "home/.config/ooodnakov/zsh/completions/_oooconf").read_text(encoding="utf-8")
    assert "--strict-config-paths[require strict config paths]" in zsh_content
    assert "--client-secret[API client secret]" in zsh_content
    assert "--method[login method]:value:(auto password apikey)" in zsh_content

    pwsh_content = (REPO_ROOT / "home/.config/ooodnakov/completions/oooconf-completions.ps1").read_text(
        encoding="utf-8"
    )
    assert "'agents:detect' = @{" in pwsh_content
    assert "Options = @('--repo-root', '--config', '--json')" in pwsh_content
    assert "'agents:mcp:sync' = @{" in pwsh_content
    assert "Options = @('--check')" in pwsh_content
    assert "'secrets:login' = @{" in pwsh_content
    assert "Options = @('--server', '--method', '--client-id', '--client-secret')" in pwsh_content
    assert "'--method' = @('auto', 'password', 'apikey')" in pwsh_content


def test_spec_driven_subcommand_descriptions_are_emitted() -> None:
    zsh_content = (REPO_ROOT / "home/.config/ooodnakov/zsh/completions/_oooconf").read_text(encoding="utf-8")
    assert "detect:detect configured agent CLIs on PATH" in zsh_content
    assert "forgit-aliases:toggle plain vs forgit git aliases" in zsh_content

    spec_content = (REPO_ROOT / "scripts/cli/oooconf-cli-spec.toml").read_text(encoding="utf-8")
    assert "[commands.agents.subcommands.detect]" in spec_content
    assert "[commands.agents.subcommands.mcp.subcommands.sync]" in spec_content
    assert "[commands.shell.subcommands.forgit-aliases]" in spec_content
    assert "subsubcommands" not in spec_content


def test_nested_command_metadata_is_emitted_for_zsh_and_powershell() -> None:
    zsh_content = (REPO_ROOT / "home/.config/ooodnakov/zsh/completions/_oooconf").read_text(encoding="utf-8")
    assert "_oooconf_agents_mcp()" in zsh_content
    assert "'sync:synchronize managed MCP servers'" in zsh_content
    assert "_oooconf_agents_mcp_sync()" in zsh_content
    assert "'--check[check only]'" in zsh_content

    pwsh_content = (REPO_ROOT / "home/.config/ooodnakov/completions/oooconf-completions.ps1").read_text(
        encoding="utf-8"
    )
    assert "'agents:mcp' = @{" in pwsh_content
    assert "Subcommands = @('sync', 'status', 'add')" in pwsh_content
    assert "'agents:mcp:sync' = @{" in pwsh_content
    assert "Options = @('--check')" in pwsh_content


def _setup_bash_sources() -> str:
    paths = [
        "scripts/setup/setup.sh",
        "scripts/setup/lib/setup-ui.sh",
        "scripts/setup/lib/setup-optional-deps.sh",
        "scripts/setup/lib/setup-installers.sh",
        "scripts/setup/lib/setup-links.sh",
        "scripts/setup/lib/setup-completions.sh",
        "scripts/setup/lib/setup-summary.sh",
        "scripts/setup/lib/setup-doctor.sh",
    ]
    return "\n".join((REPO_ROOT / path).read_text(encoding="utf-8") for path in paths)


def _setup_pwsh_sources() -> str:
    paths = [
        "scripts/setup/setup.ps1",
        "scripts/setup/lib/setup-installers.ps1",
        "scripts/setup/lib/setup-ui.ps1",
        "scripts/setup/lib/setup-optional-deps.ps1",
        "scripts/setup/lib/setup-summary.ps1",
        "scripts/setup/lib/setup-links.ps1",
        "scripts/setup/lib/setup-completions.ps1",
        "scripts/setup/lib/setup-doctor.ps1",
        "scripts/setup/lib/setup-dispatch.ps1",
    ]
    return "\n".join((REPO_ROOT / path).read_text(encoding="utf-8") for path in paths)


def _oooconf_bash_sources() -> str:
    paths = [
        "scripts/setup/ooodnakov.sh",
        "scripts/setup/lib/oooconf-ui.sh",
        "scripts/setup/lib/oooconf-shell.sh",
        "scripts/setup/lib/oooconf-color.sh",
        "scripts/setup/lib/oooconf-wm.sh",
        "scripts/setup/lib/oooconf-bar.sh",
        "scripts/setup/lib/oooconf-help.sh",
        "scripts/setup/lib/oooconf-dispatch.sh",
    ]
    return "\n".join((REPO_ROOT / path).read_text(encoding="utf-8") for path in paths)


def _oooconf_pwsh_sources() -> str:
    paths = [
        "scripts/setup/ooodnakov.ps1",
        "scripts/setup/lib/oooconf-ui.ps1",
        "scripts/setup/lib/oooconf-shell.ps1",
        "scripts/setup/lib/oooconf-color.ps1",
        "scripts/setup/lib/oooconf-wm.ps1",
        "scripts/setup/lib/oooconf-bar.ps1",
        "scripts/setup/lib/oooconf-help.ps1",
        "scripts/setup/lib/oooconf-dispatch.ps1",
    ]
    return "\n".join((REPO_ROOT / path).read_text(encoding="utf-8") for path in paths)


def test_top_level_command_values_are_emitted() -> None:
    zsh_content = (REPO_ROOT / "home/.config/ooodnakov/zsh/completions/_oooconf").read_text(encoding="utf-8")
    assert "_oooconf_wm()" in zsh_content
    assert "'komorebi:Komorebi'" in zsh_content
    assert "'glazewm:GlazeWM'" in zsh_content

    pwsh_content = (REPO_ROOT / "home/.config/ooodnakov/completions/oooconf-completions.ps1").read_text(
        encoding="utf-8"
    )
    assert "'wm' = @{" in pwsh_content
    assert "Values = @('komorebi', 'glazewm', 'aerospace', 'omniwm')" in pwsh_content


def test_oooconf_completions_command_wires_generator() -> None:
    setup_sh = _setup_bash_sources()
    assert 'OOOCONF_COMPLETIONS_GENERATOR="$REPO_ROOT/scripts/cli/generate_oooconf_completions.py"' in setup_sh
    assert 'run_python "$OOOCONF_COMPLETIONS_GENERATOR"' in setup_sh
    assert "generate_tracked_completions()" in setup_sh
    assert "prepare_completion_output_path" in setup_sh
    assert "generate_tracked_completions || true" in setup_sh

    setup_ps1 = _setup_pwsh_sources()
    assert (
        '$OooconfCompletionsGenerator = Join-Path $RepoRoot "scripts/cli/generate_oooconf_completions.py"' in setup_ps1
    )
    assert "$null = Run-Python -ScriptPath $scriptPath -ScriptArgs @()" in setup_ps1
    assert "function Generate-TrackedCompletions" in setup_ps1
    assert "Generate-TrackedCompletions" in setup_ps1
    completions_branch = setup_ps1.split('"completions" {', 1)[1].split('"minimal"', 1)[0]
    assert "Generate-AutogenCompletions" in completions_branch
    assert "Generate-OooconfCompletions" in completions_branch
    assert "if (-not $DryRun)" not in completions_branch

    ooosh = _oooconf_bash_sources()
    assert "completions)" in ooosh
    assert 'exec_setup_command completions 1 "$@"' in ooosh

    ooops1 = _oooconf_pwsh_sources()
    assert '"completions" {' in ooops1
    assert 'Invoke-SetupCommand -SetupCommand "completions" -SupportsDryRun -RemainingArgs $remaining' in ooops1


def test_setup_dispatch_uses_handler_metadata() -> None:
    setup_sh = _setup_bash_sources()
    assert 'handler_func="maybe_install_${handler//-/_}"' in setup_sh
    assert (
        'case "$key" in'
        not in setup_sh.split("install_optional_dependency_from_catalog()", 1)[1].split("run_with_spinner()", 1)[0]
    )

    setup_ps1 = _setup_pwsh_sources()
    install_fn = setup_ps1.split("function Install-OptionalDependencyFromSpec", 1)[1]
    assert "switch ($handler)" in install_fn


def test_unix_handlers_have_setup_sh_implementations() -> None:
    """Ensure handler-based bash dispatch doesn't silently fall back for unix-special handlers."""
    deps = load_deps()["deps"]
    setup_sh = _setup_bash_sources()

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


def test_setup_optional_deps_cache_lookups_are_literal_safe() -> None:
    setup_sh = _setup_bash_sources()

    pipe_lookup = setup_sh.split("lookup_pipe_cache_value()", 1)[1].split("optional_dependency_check_command()", 1)[0]
    assert "printf '%s\\n' \"$cache\"" in pipe_lookup
    assert re.search(r"\|\s+awk -F'\|'", pipe_lookup)
    assert "substr($0, index($0, FS) + 1)" in pipe_lookup
    assert '$1=""' not in pipe_lookup
    assert "<<EOF" not in pipe_lookup

    install_lookup = setup_sh.split("optional_dependency_install_info_line()", 1)[1].split(
        "optional_dependency_applicable()", 1
    )[0]
    assert "printf '%s\\n' \"$OPTIONAL_DEPS_INSTALL_INFO_CACHE\"" in install_lookup
    assert re.search(r'\|\s+awk -F"\$us"', install_lookup)
    assert "<<EOF" not in install_lookup


def test_setup_fast_path_only_applies_to_default_dependency_check() -> None:
    setup_sh = _setup_bash_sources()
    check_fn = setup_sh.split("check_dependency_status()", 1)[1].split("maybe_install_dependency()", 1)[0]

    assert 'check_cmd="$(optional_dependency_check_command "$command_name")"' in check_fn
    assert '[ "$check_cmd" = "command -v $command_name" ] && command -v "$command_name"' in check_fn
    assert "Richer" in check_fn and "node+npm" in check_fn


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

    setup_sh = _setup_bash_sources()
    setup_ps1 = _setup_pwsh_sources()

    expected_unix = {"", "apt", "brew", "cargo", "curl", "custom", "download", "github-release", "pip", "pnpm"}
    expected_windows = {"", "cargo", "choco", "custom", "download", "github-release", "pip", "pnpm", "scoop", "winget"}
    assert unix_managers == expected_unix
    assert windows_managers == expected_windows

    for pattern in ["custom | curl)", "pnpm)", "pip)", "github-release)", '"")']:
        assert pattern in setup_sh
    for manager in ["apt", "brew", "cargo"]:
        assert f'if [ "$manager" = "{manager}" ]' in setup_sh or f"{manager})" in setup_sh
    assert "maybe_install_bw()" in setup_sh  # download manager is handled by the bw handler.
    assert "docker daemon: no docker, continuing" in setup_sh
    assert "python3 unavailable for pip" in setup_sh
    assert 'pnpm_cmd="$(ensure_pnpm_available)' not in setup_sh
    assert "pip unavailable for $python_cmd" in setup_sh
    assert "return 0" in setup_sh.split("python3 unavailable for pip", 1)[1].split("check_pip_dependency_status", 1)[0]
    assert 'check_pip_dependency_status "$command_name" "$python_cmd"' in setup_sh
    assert 'check_cmd="$python_cmd ${check_cmd#python }"' in setup_sh

    for manager in ["custom", "curl", "winget", "choco", "cargo", "scoop", "pnpm", "github-release", "pip"]:
        assert f'"{manager}" {{' in setup_ps1
    assert '"bw" { return (Install-BitwardenCliIfMissing) }' in setup_ps1  # download manager handler.
    assert "function Get-PythonCommand" in setup_ps1
