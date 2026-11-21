"""Tests for the GitHub Pages static site generator."""

from __future__ import annotations

import json
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.site.build_site import DOC_SECTIONS, build_site, collect_repo_data, normalize_base_url  # noqa: E402
from scripts.site.markdown_render import github_slugify  # noqa: E402


class _HtmlInspector(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.ids: set[str] = set()
        self.refs: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        for name, value in attrs:
            if name == "id" and value:
                self.ids.add(value)
            if name in {"href", "src"} and value:
                self.refs.append(value)


def test_normalize_base_url() -> None:
    assert normalize_base_url("") == ""
    assert normalize_base_url("/") == ""
    assert normalize_base_url("ooodnakov-config") == "/ooodnakov-config"
    assert normalize_base_url("/ooodnakov-config/") == "/ooodnakov-config"


def test_github_slugify_matches_documented_anchors() -> None:
    assert github_slugify("Platform Support Matrix") == "platform-support-matrix"
    assert github_slugify("Transaction journal retention and cleanup") == "transaction-journal-retention-and-cleanup"
    assert github_slugify("OMP File and Content Links") == "omp-file-and-content-links"
    assert github_slugify("oooconf link Command") == "oooconf-link-command"


def test_build_site_outputs_and_internal_link_integrity(tmp_path: Path) -> None:
    out_dir = tmp_path / "site-out"
    base = "/ooodnakov-config"
    summary = build_site(REPO_ROOT, out_dir, base_url=base)

    expected_slugs = [slug for _, entries in DOC_SECTIONS for _, slug, _ in entries]
    assert summary.doc_count == len(expected_slugs) == 22
    assert summary.command_count > 50
    assert summary.dep_count > 50

    required_files = [
        out_dir / ".nojekyll",
        out_dir / "index.html",
        out_dir / "404.html",
        out_dir / "docs" / "index.html",
        out_dir / "robots.txt",
        out_dir / "sitemap.xml",
        out_dir / "assets" / "style.css",
        out_dir / "assets" / "app.js",
        out_dir / "assets" / "favicon.svg",
        out_dir / "assets" / "dotfiles-banner-transparent.svg",
        out_dir / "data" / "site-data.json",
        out_dir / "data" / "search-index.json",
    ]
    for path in required_files:
        assert path.is_file(), f"Missing generated artifact: {path}"
        if path.name != ".nojekyll":
            assert path.stat().st_size > 0, f"Empty generated artifact: {path}"

    for slug in expected_slugs:
        assert (out_dir / "docs" / slug / "index.html").is_file(), f"Missing doc page for {slug}"
    assert not (out_dir / "docs" / "codex-project-improvement-task").exists()

    site_data = json.loads((out_dir / "data" / "site-data.json").read_text(encoding="utf-8"))
    assert set(site_data["profiles"].keys()) == {"minimal", "terminal", "developer", "workstation"}
    for profile in site_data["profiles"].values():
        assert set(profile["platforms"].keys()) == {"linux", "macos", "windows"}
    assert len(site_data["cli_commands"]) > 50
    assert len(site_data["optional_deps"]) > 50

    search_index = json.loads((out_dir / "data" / "search-index.json").read_text(encoding="utf-8"))
    items = search_index["items"]
    assert any(item["kind"] == "doc" for item in items)
    assert any(item["kind"] == "heading" for item in items)
    assert any(item["kind"] == "command" for item in items)
    assert all(item["url"].startswith(f"{base}/") for item in items)
    assert not any("codex-project-improvement-task" in item["url"] for item in items)

    html_files = sorted(out_dir.rglob("*.html"))
    parsed_pages: dict[Path, _HtmlInspector] = {}
    for html_file in html_files:
        inspector = _HtmlInspector()
        inspector.feed(html_file.read_text(encoding="utf-8"))
        inspector.close()
        parsed_pages[html_file] = inspector

    for html_file, inspector in parsed_pages.items():
        for ref in inspector.refs:
            if ref.startswith("#"):
                fragment = unquote(ref[1:])
                assert fragment in inspector.ids, f"Broken self-anchor {ref} in {html_file}"
                continue
            if not ref.startswith(f"{base}/"):
                continue
            rel, _, fragment = ref.removeprefix(f"{base}/").partition("#")
            rel_no_query = rel.split("?", 1)[0]
            target = out_dir / (
                f"{rel_no_query}index.html" if not rel_no_query or rel_no_query.endswith("/") else rel_no_query
            )
            assert target.is_file(), f"Broken internal ref {ref} in {html_file} -> {target}"
            if fragment and target in parsed_pages:
                decoded_frag = unquote(fragment)
                assert decoded_frag in parsed_pages[target].ids, (
                    f"Broken cross-page anchor {ref} in {html_file} (missing #{decoded_frag} in {target})"
                )


def test_collect_repo_data_ignores_local_profile_env(monkeypatch) -> None:
    monkeypatch.setenv("OOODNAKOV_PROFILE", "nonexistent-local-profile")
    data = collect_repo_data(REPO_ROOT)
    assert set(data["profiles"].keys()) == {"minimal", "terminal", "developer", "workstation"}
    assert data["stats"]["cli_commands"] == len(data["cli_commands"])
