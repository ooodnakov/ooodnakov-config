"""Tests that a single failing tool completion does not abort the whole batch."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from scripts.generate.generate_tool_completions import (  # noqa: E402
    GeneratedCompletion,
    ZshCompletion,
    ZshConfig,
    generate,
    validate_zsh_files,
)


def make_spec(
    tool_key: str,
    output: str,
    *,
    argv: tuple[str, ...],
    binary: str = "sh",
    provides: tuple[str, ...] | None = None,
    filter_name: str | None = None,
) -> ZshCompletion:
    return ZshCompletion(
        tool_key=tool_key,
        binary=binary,
        output=output,
        provides=provides or (tool_key,),
        argv=argv,
        env={},
        filter_name=filter_name,
        description=f"Generating {tool_key} completions",
    )


def make_config(tmp_path: Path) -> ZshConfig:
    return ZshConfig(
        output_dir=tmp_path / "out",
        stamp_name=".autogen-stamp",
        prune=True,
        validate=False,
    )


def test_failing_tool_does_not_abort_other_generations(tmp_path: Path) -> None:
    config = make_config(tmp_path)
    good = make_spec("good", "_good", argv=("sh", "-c", "printf '#compdef good\\n_good() {}\\n'"))
    bad = make_spec("bad", "_bad", argv=("sh", "-c", "echo boom >&2; exit 3"))

    failures = generate(config, [bad, good], tmp_path, validate=False)

    assert len(failures) == 1
    assert "bad" in failures[0]
    assert "exit 3" in failures[0]
    assert (config.output_dir / "_good").read_text(encoding="utf-8") == "#compdef good\n_good() {}\n"
    assert not (config.output_dir / "_bad").exists()
    assert (config.output_dir / config.stamp_name).exists()


def test_filter_failure_is_isolated(tmp_path: Path) -> None:
    config = make_config(tmp_path)
    good = make_spec("good", "_good", argv=("sh", "-c", "printf '#compdef good\\n_good() {}\\n'"))
    broken_filter = make_spec(
        "filtered",
        "_filtered",
        argv=("sh", "-c", "printf 'body\\n'"),
        filter_name="does-not-exist",
    )

    failures = generate(config, [broken_filter, good], tmp_path, validate=False)

    assert any("unknown completion filter" in failure for failure in failures)
    assert (config.output_dir / "_good").exists()
    assert not (config.output_dir / "_filtered").exists()


def test_validation_failure_drops_only_bad_file(tmp_path: Path) -> None:
    if not shutil.which("zsh"):
        pytest.skip("zsh is not available")

    config = make_config(tmp_path)
    config.output_dir.mkdir(parents=True, exist_ok=True)

    good = GeneratedCompletion(
        spec=make_spec("good", "_good", argv=("sh", "-c", "true")),
        content="#compdef good\n_good() {}\n",
    )
    bad = GeneratedCompletion(
        spec=make_spec("bad", "_bad", argv=("sh", "-c", "true")),
        content="if true; then\n",
    )
    for item in (good, bad):
        (config.output_dir / item.spec.output).write_text(item.content, encoding="utf-8")

    valid, failures = validate_zsh_files(config, [good, bad])

    assert [item.spec.output for item in valid] == ["_good"]
    assert any("_bad" in failure and "syntax validation failed" in failure for failure in failures)
    assert (config.output_dir / "_good").exists()
    assert not (config.output_dir / "_bad").exists()


def test_cli_exits_zero_while_skipping_failing_tool(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    good = bin_dir / "fake-good"
    good.write_text("#!/bin/sh\nprintf '#compdef fgood\\n_fgood() {}\\n'\n", encoding="utf-8")
    good.chmod(0o755)
    bad = bin_dir / "fake-bad"
    bad.write_text("#!/bin/sh\necho boom >&2\nexit 3\n", encoding="utf-8")
    bad.chmod(0o755)

    manifest = tmp_path / "manifest.toml"
    manifest.write_text(
        textwrap.dedent(
            """
            version = 1

            [zsh]
            output_dir = "out"
            stamp = ".autogen-stamp"
            prune = true
            validate = false

            [[tools]]
            key = "goodtool"
            binary = "fake-good"

            [[tools.zsh]]
            output = "_fgood"
            provides = ["fgood"]
            argv = ["fake-good"]

            [[tools]]
            key = "badtool"
            binary = "fake-bad"

            [[tools.zsh]]
            output = "_fbad"
            provides = ["fbad"]
            argv = ["fake-bad"]
            """
        ).lstrip(),
        encoding="utf-8",
    )

    env = os.environ.copy()
    env["PATH"] = f"{bin_dir}{os.pathsep}{env.get('PATH', '')}"
    result = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts/generate/generate_tool_completions.py"),
            "--repo-root",
            str(tmp_path),
            "--manifest",
            str(manifest),
        ],
        capture_output=True,
        text=True,
        env=env,
    )

    assert result.returncode == 0, result.stderr
    assert "warning:" in result.stderr
    assert "badtool" in result.stderr
    assert (tmp_path / "out" / "_fgood").exists()
    assert not (tmp_path / "out" / "_fbad").exists()
