"""Drift checks for optional dependency metadata consumers."""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from scripts.read_optional_deps import load_deps  # noqa: E402


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
    assert "def parse_optional_deps" not in content


def test_setup_dispatch_uses_handler_metadata() -> None:
    setup_sh = (REPO_ROOT / "scripts/setup.sh").read_text(encoding="utf-8")
    assert "handler_func=\"maybe_install_${handler//-/_}\"" in setup_sh
    assert "case \"$key\" in" not in setup_sh.split("install_optional_dependency_from_catalog()", 1)[1].split("run_with_spinner()", 1)[0]

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
