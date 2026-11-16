"""Markdown rendering used for streamed agent output."""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts/cli"))

import cli_ui  # noqa: E402

ANSI = re.compile(r"\x1b\[[0-9;]*m")


def render(lines: list[str], *, color: bool, nerd: bool = False) -> str:
    stream = cli_ui.MarkdownStream()
    out = [stream.feed(line) for line in lines]
    out.append(stream.flush())
    return "\n".join(part for part in out if part)


def test_headings_lists_quotes_and_rules(monkeypatch) -> None:
    monkeypatch.setattr(cli_ui, "supports_color_output", lambda: False)
    monkeypatch.setattr(cli_ui, "supports_nerd_font_output", lambda: False)
    text = render(
        [
            "# Release notes",
            "### Details",
            "- first",
            "  - nested",
            "1. ordered",
            "> quoted",
            "---",
        ],
        color=False,
    )
    assert "# Release notes" not in text
    assert "Release notes" in text
    assert "== Release notes" in text
    assert "- Details" in text
    assert "- first" in text
    assert "  - nested" in text
    assert "1. ordered" in text
    assert "| quoted" in text
    assert "-" * 40 in text
    assert "\x1b[" not in text


def test_inline_emphasis_links_and_code(monkeypatch) -> None:
    monkeypatch.setattr(cli_ui, "supports_color_output", lambda: True)
    text = render(["Use **bold**, *italic*, ~~gone~~, `code`, [docs](https://x.test)."], color=True)
    visible = ANSI.sub("", text)
    assert "Use bold, italic, gone, code, docs (https://x.test)." in visible
    assert "\x1b[1m" in text
    assert "\x1b[3m" in text
    assert "\x1b[9m" in text


def test_fenced_code_keeps_content_with_a_gutter(monkeypatch) -> None:
    monkeypatch.setattr(cli_ui, "supports_color_output", lambda: False)
    monkeypatch.setattr(cli_ui, "supports_nerd_font_output", lambda: False)
    text = render(["before", "```bash", "git status", "```", "after"], color=False)
    assert text.splitlines() == ["before", "| git status", "after"]


def test_unclosed_fence_is_flushed(monkeypatch) -> None:
    monkeypatch.setattr(cli_ui, "supports_color_output", lambda: False)
    stream = cli_ui.MarkdownStream()
    assert stream.feed("```") == ""
    assert stream.feed("echo hi") == "| echo hi"
    assert stream.flush() == ""


def test_tables_render_without_the_alignment_row(monkeypatch) -> None:
    monkeypatch.setattr(cli_ui, "supports_color_output", lambda: False)
    monkeypatch.setattr(cli_ui, "supports_nerd_font_output", lambda: False)
    text = render(["| host | status |", "| --- | --- |", "| a | ok |", "| b | fail |"], color=False)
    lines = text.splitlines()
    assert len(lines) == 3
    assert "host" in lines[0] and "status" in lines[0]
    assert "| a" in lines[1] and "ok" in lines[1]
    assert "--- |" not in text


def test_preformatted_agent_output_is_passed_through(monkeypatch) -> None:
    monkeypatch.setattr(cli_ui, "supports_color_output", lambda: True)
    line = "\x1b[32mgreen\x1b[0m"
    assert cli_ui.MarkdownStream().feed(line) == line


def test_plain_paragraph_text_is_untouched(monkeypatch) -> None:
    monkeypatch.setattr(cli_ui, "supports_color_output", lambda: False)
    assert render(["Resolved 2 conflicts in a.txt."], color=False) == "Resolved 2 conflicts in a.txt."


def test_blank_lines_are_preserved_once(monkeypatch) -> None:
    monkeypatch.setattr(cli_ui, "supports_color_output", lambda: False)
    monkeypatch.setattr(cli_ui, "supports_nerd_font_output", lambda: False)
    stream = cli_ui.MarkdownStream()

    out = [stream.feed(line) for line in ("first", "", "", "second")]

    assert out == ["first", "\n", "", "second"]
