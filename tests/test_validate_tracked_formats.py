"""Tests for scripts/validation/validate_tracked_formats.py, especially KDL lexing."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.validation import validate_tracked_formats as vtf  # noqa: E402


def _write_kdl(tmp_path: Path, name: str, content: str) -> Path:
    path = tmp_path / name
    path.write_text(content, encoding="utf-8")
    return path


def test_kdl_allows_quotes_and_braces_in_comments_and_raw_strings(tmp_path: Path) -> None:
    content = """
// Single-line comment with unmatched " quote and { { } and /*
node "quoted \\"value\\" with { braces } and \\\\ slash" {
    /* Outer block comment with "unmatched quote and { brace
       /* Nested block comment with } and " */
       still inside outer comment } "
    */
    raw_v1 r#"contains "quotes" and { unmatched } and /* //"#
    raw_v1_plain r"simple raw { with } quotes"
    raw_v2 #"kdl v2 "raw" { string } /* "#
    raw_multi r##"multi "# inner } { "##
    multiline \"\"\"hello " { } \\" world\"\"\"
    bar "identifier ending in r before space"
}
"""
    path = _write_kdl(tmp_path, "valid.kdl", content)
    vtf.validate(path)


@pytest.mark.parametrize(
    ("name", "content", "match"),
    [
        ("unmatched_close.kdl", "node {\n}\n}\n", "unmatched closing brace"),
        ("unterminated_block.kdl", "node {\n  child 1\n", "unterminated string or brace block"),
        ("unterminated_string.kdl", 'node "unterminated\n', "unterminated string or brace block"),
        ("trailing_escape.kdl", 'node "abc\\', "unterminated string or brace block"),
        ("unterminated_raw.kdl", 'node r#"missing closing hash"', "unterminated raw string"),
        ("unterminated_v2_raw.kdl", 'node #"missing closing hash', "unterminated raw string"),
        ("unterminated_nested_comment.kdl", "/* outer /* inner */", "unterminated block comment"),
        ("merge_marker.kdl", "<<<<<<< HEAD\nnode 1\n", "unresolved merge markers"),
    ],
)
def test_kdl_rejects_malformed_constructs(tmp_path: Path, name: str, content: str, match: str) -> None:
    path = _write_kdl(tmp_path, name, content)
    with pytest.raises(ValueError, match=match):
        vtf.validate(path)


def test_validate_tracked_formats_main_succeeds_on_repo() -> None:
    assert vtf.main() == 0
