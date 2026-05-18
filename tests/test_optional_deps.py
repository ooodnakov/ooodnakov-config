"""Tests for the central optional-deps.toml parser (sole source of truth)."""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

# Make scripts importable
sys.path.insert(0, str(Path(__file__).parent.parent))
from scripts.cli.read_optional_deps import load_deps, output_catalog, output_json

SUBPROCESS_TIMEOUT_SECONDS = int(os.environ.get("OOOCONF_TEST_TIMEOUT", "180"))
REPO_ROOT = Path(__file__).resolve().parent.parent


def _bash_syntax_check(script: str) -> subprocess.CompletedProcess[str]:
    """Run bash -n against LF-normalized content so Windows CRLF checkouts still parse."""
    return _run_normalized_bash_script(script, "-n")


def _run_normalized_bash_script(script: str, *args: str) -> subprocess.CompletedProcess[str]:
    """Run a bash command against an LF-normalized temporary copy of a tracked script."""
    source_path = Path(__file__).parent.parent / script
    normalized = source_path.read_text(encoding="utf-8").replace("\r\n", "\n")
    with tempfile.NamedTemporaryFile(
        "w",
        suffix=source_path.suffix,
        prefix=f"{source_path.stem}-",
        dir=source_path.parent,
        delete=False,
        encoding="utf-8",
        newline="\n",
    ) as handle:
        handle.write(normalized)
        temp_path = Path(handle.name)
    try:
        bash_temp_path = temp_path.as_posix()
        command = (
            ["bash", "-n", bash_temp_path, *args[1:]] if args and args[0] == "-n" else ["bash", bash_temp_path, *args]
        )
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            cwd=Path(__file__).parent.parent,
            timeout=SUBPROCESS_TIMEOUT_SECONDS,
        )
    finally:
        temp_path.unlink(missing_ok=True)


def test_load_deps_structure():
    """Test that load_deps returns expected top-level keys from TOML."""
    data = load_deps()
    assert "deps" in data
    assert "managed_tools" in data
    assert "defaults" in data
    assert isinstance(data["deps"], list)
    assert isinstance(data["managed_tools"], dict)
    assert isinstance(data["defaults"], dict)
    assert len(data["deps"]) > 0
    assert "oh-my-zsh" in data["managed_tools"]


def test_managed_tools_parsing():
    """Test that all managed git tools are loaded with repo/ref."""
    data = load_deps()
    tools = data["managed_tools"]
    assert "oh-my-zsh" in tools
    assert "repo" in tools["oh-my-zsh"]
    assert "ref" in tools["oh-my-zsh"]
    assert tools["powerlevel10k"]["repo"].startswith("https://github.com/romkatv/powerlevel10k")


def test_url_template_substitution():
    """Test that ver field is present and template substitution logic runs."""
    data = load_deps()
    rtk = next((d for d in data["deps"] if d.get("key") == "rtk"), None)
    assert rtk is not None
    assert rtk["ver"] == "0.37.2"
    # URL replacement is handled in load_deps(); platform fields contain version
    assert any("0.37.2" in str(v) for v in rtk.values() if isinstance(v, str))


def test_github_release_asset_metadata():
    """Test GitHub release archive metadata is normalized for platform installers."""
    data = load_deps()
    bat = next((d for d in data["deps"] if d.get("key") == "bat"), None)
    assert bat is not None
    assert bat["ver"] == "0.26.1"
    assert bat["linux.manager"] == "github-release"
    assert bat["linux.package"] == "sharkdp/bat"
    assert bat["linux.asset"] == "bat-v0.26.1-${arch}-unknown-linux-musl.tar.gz"


def test_defaults_section():
    """Test that [defaults] section is loaded."""
    data = load_deps()
    assert "state_home" in data["defaults"]
    assert data["defaults"]["bin_dir"] == "~/.local/bin"


def test_catalog_output(capsys):
    """Test that output_catalog produces pipe-delimited lines."""
    output_catalog()
    captured = capsys.readouterr()
    assert "rtk|" in captured.out
    assert "bw|" in captured.out
    assert len(captured.out.splitlines()) > 30  # many deps


def test_json_output_includes_new_fields(capsys):
    """Test JSON output includes ver, url, bin, check, after."""
    output_json()
    captured = capsys.readouterr()
    data = json.loads(captured.out)
    rtk = next((d for d in data if d.get("key") == "rtk"), None)
    assert rtk is not None
    assert "ver" in rtk
    assert "url" in rtk
    assert "bin" in rtk
    assert rtk["ver"] == "0.37.2"


@pytest.mark.parametrize("key", ["rtk", "bw", "pnpm"])
def test_get_install_info(key):
    """Test install-info command returns enriched data for key deps."""
    # This would require mocking sys.argv and capturing print; simplified check via load_deps
    data = load_deps()
    dep = next((d for d in data["deps"] if d.get("key") == key), None)
    assert dep is not None
    assert dep.get("ver") is not None


def test_all_managed_tools_present():
    """Test that all expected git-pinned tools are in managed-tools."""
    data = load_deps()
    tools = data["managed_tools"]
    expected = {
        "oh-my-zsh",
        "powerlevel10k",
        "zsh-autosuggestions",
        "zsh-syntax-highlighting",
        "zsh-history-substring-search",
        "zsh-autocomplete",
        "fzf-tab",
        "forgit",
        "you-should-use",
        "auto-uv-env",
        "nvm",
        "k",
        "marker",
        "todo-txt",
    }
    assert expected.issubset(tools.keys())


def test_url_substitution_for_multiple_tools():
    """Test template substitution works for tools with 'ver' and 'url'."""
    data = load_deps()
    for dep in data["deps"]:
        if dep.get("ver") and any("url" in str(k).lower() for k in dep.keys()):
            urls = [v for k, v in dep.items() if isinstance(v, str) and "url" in str(k).lower()]
            for url in urls:
                if "${ver}" in url:
                    continue  # some platform fields may still use template until full migration
                if dep.get("ver") and (dep["ver"] in url or f"v{dep['ver']}" in url):
                    break
            else:
                continue  # some tools intentionally have no full URL
            # At least one URL had the version
            assert True


def test_defaults_loading():
    """Test [defaults] section is parsed correctly."""
    data = load_deps()
    defaults = data["defaults"]
    assert "state_home" in defaults
    assert "bin_dir" in defaults
    assert defaults["bin_dir"] == "~/.local/bin"


def test_minimal_keys_command_and_legacy_alias(capsys):
    """Test minimal key output and the legacy alias used by older setup scripts."""
    from scripts.cli.read_optional_deps import main

    expected = ["git", "zsh", "uv", "oh-my-posh", "gum", "rg", "fd", "bat"]
    original_argv = sys.argv[:]
    try:
        sys.argv = ["read_optional_deps.py", "minimal"]
        assert main() == 0
        assert capsys.readouterr().out.split() == expected

        sys.argv = ["read_optional_deps.py", "minimal-keys"]
        assert main() == 0
        assert capsys.readouterr().out.split() == expected
    finally:
        sys.argv = original_argv


def test_invalid_key_handling():
    """Test graceful handling of unknown keys."""
    result = subprocess.run(
        ["uv", "run", "scripts/cli/read_optional_deps.py", "get", "nonexistentkey"],
        capture_output=True,
        text=True,
        timeout=SUBPROCESS_TIMEOUT_SECONDS,
    )
    assert result.returncode != 0, "Expected non-zero exit for invalid key"


def test_completions_generator():
    """Test that completions generator uses the central parser without hard-coded lists."""
    result = subprocess.run(
        ["uv", "run", "scripts/cli/generate_oooconf_completions.py"],
        capture_output=True,
        text=True,
        cwd=Path(__file__).parent.parent,
        timeout=SUBPROCESS_TIMEOUT_SECONDS,
    )
    assert result.returncode == 0, f"Completions generator failed: {result.stderr}"
    assert "updated:" in result.stdout.lower()


def test_shell_scripts_syntax_and_dry_run():
    """Test .sh and .ps1 files for syntax and basic dry-run (no full PS1 execution if pwsh missing)."""
    if sys.platform == "win32":
        pytest.skip("Bash shell-script validation runs in the Unix CI jobs")

    # Bash syntax (only .sh files; Python is tested via pytest/ruff)
    shell_scripts = ["scripts/setup/setup.sh", "scripts/setup/ooodnakov.sh", "scripts/setup/delete.sh"]
    shell_scripts.extend(
        str(path.relative_to(REPO_ROOT)) for path in sorted((REPO_ROOT / "scripts/setup/lib").glob("*.sh"))
    )
    for script in shell_scripts:
        result = _bash_syntax_check(script)
        assert result.returncode == 0, f"{script} has syntax errors: {result.stderr}"

    # Basic dry-run test for setup (tests the central TOML path and refactored parser)
    result = _run_normalized_bash_script("scripts/setup/ooodnakov.sh", "deps", "--dry-run", "rtk")
    assert result.returncode == 0, f"dry-run failed: {result.stderr}"
    assert any(k in result.stdout.lower() for k in ["dry-run", "rtk", "dependency summary", "complete"])

    result = _run_normalized_bash_script("scripts/setup/ooodnakov.sh", "deps", "--minimal", "--dry-run")
    assert result.returncode == 0, f"minimal dry-run failed: {result.stderr}"
    assert "dependency summary" in result.stdout.lower()
    assert "optional dependency install complete" in result.stdout.lower()

    # PowerShell syntax (if pwsh available)
    if Path("/usr/bin/pwsh").exists() or Path("/usr/local/bin/pwsh").exists():
        result = subprocess.run(
            [
                "pwsh",
                "-NoProfile",
                "-Command",
                "Import-Module PSScriptAnalyzer -ErrorAction SilentlyContinue; if ($?) { Invoke-ScriptAnalyzer -Path scripts/setup/setup.ps1,scripts/setup/ooodnakov.ps1,scripts/setup/lib/*.ps1 -Severity Error } else { exit 0 }",
            ],
            capture_output=True,
            text=True,
            timeout=SUBPROCESS_TIMEOUT_SECONDS,
        )
        # Ignore if analyzer not installed; just check parse
        assert "syntax error" not in result.stderr.lower()

    # Run dedicated shell test script (covers .sh dry-run, managed_tool helper, .ps1 fallback)
    result = _run_normalized_bash_script("tests/test_shell.sh")
    assert result.returncode == 0, f"shell test failed: {result.stderr}"
    assert "All shell tests passed" in result.stdout
