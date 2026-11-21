"""Markdown rendering and HTML post-processing for GitHub Pages docs."""

from __future__ import annotations

import html
import posixpath
import re
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath

import markdown

VOID_ELEMENTS = frozenset(
    {
        "area",
        "base",
        "br",
        "col",
        "embed",
        "hr",
        "img",
        "input",
        "link",
        "meta",
        "param",
        "source",
        "track",
        "wbr",
    }
)


@dataclass(frozen=True)
class TocItem:
    """One heading entry for the page's On This Page navigation."""

    level: int
    id: str
    title: str


@dataclass(frozen=True)
class RenderedDoc:
    """Rendered HTML body and extracted metadata for one Markdown page."""

    title: str
    description: str
    html_body: str
    toc: tuple[TocItem, ...]
    plain_text: str
    reading_minutes: int


def github_slugify(value: str, separator: str = "-") -> str:
    """Generate GitHub-style heading anchor slugs."""
    cleaned = re.sub(r"[^\w\s-]", "", value.strip().lower(), flags=re.UNICODE)
    return re.sub(r"\s", separator, cleaned)


def _flatten_toc(tokens: list[dict[str, object]]) -> list[TocItem]:
    items: list[TocItem] = []
    for token in tokens:
        level = int(token.get("level", 0))
        item_id = str(token.get("id", ""))
        name = str(token.get("name", ""))
        if level in (2, 3) and item_id and name:
            items.append(TocItem(level=level, id=item_id, title=name))
        children = token.get("children")
        if isinstance(children, list) and children:
            items.extend(_flatten_toc(children))
    return items


def _rewrite_href(
    href: str,
    *,
    source_rel_path: str,
    doc_slug_by_rel_path: dict[str, str],
    base_url: str,
    repo_root: Path,
    github_url: str,
) -> str:
    if not href or href.startswith(("#", "http://", "https://", "mailto:", "tel:")):
        return href

    path_part, _, fragment = href.partition("#")
    if not path_part:
        return href

    source_dir = PurePosixPath(source_rel_path).parent.as_posix()
    joined = posixpath.join("" if source_dir == "." else source_dir, path_part)
    norm_path = posixpath.normpath(joined).lstrip("./")
    if norm_path.startswith("../"):
        return href

    frag_suffix = f"#{fragment}" if fragment else ""
    if norm_path in doc_slug_by_rel_path:
        slug = doc_slug_by_rel_path[norm_path]
        return f"{base_url}/docs/{slug}/{frag_suffix}"

    target = repo_root / norm_path
    ref_kind = "tree" if target.is_dir() else "blob"
    return f"{github_url}/{ref_kind}/main/{norm_path}{frag_suffix}"


class _HtmlPostProcessor(HTMLParser):
    """Safely rewrite relative links, wrap tables, and add code block headers."""

    def __init__(
        self,
        *,
        source_rel_path: str,
        doc_slug_by_rel_path: dict[str, str],
        base_url: str,
        repo_root: Path,
        github_url: str,
    ) -> None:
        super().__init__(convert_charrefs=False)
        self._source_rel_path = source_rel_path
        self._doc_slug_by_rel_path = doc_slug_by_rel_path
        self._base_url = base_url
        self._repo_root = repo_root
        self._github_url = github_url
        self._out: list[str] = []
        self._stripped_first_h1 = False
        self._skipping_first_h1 = False
        self._pending_pre = False
        self._in_code_block = False

    def result(self) -> str:
        if self._pending_pre:
            self._emit_code_block_open("text")
            self._pending_pre = False
        return "".join(self._out)

    def _emit_code_block_open(self, lang: str) -> None:
        safe_lang = html.escape(lang or "text", quote=True)
        self._out.append(
            '<div class="code-block">'
            '<div class="code-block-bar">'
            f'<span class="code-lang">{safe_lang}</span>'
            '<button type="button" class="copy-btn">Copy</button>'
            "</div>"
            "<pre>"
        )
        self._in_code_block = True

    def _format_attrs(self, tag: str, attrs: list[tuple[str, str | None]]) -> str:
        parts: list[str] = []
        for name, value in attrs:
            if tag == "a" and name == "href" and value is not None:
                value = _rewrite_href(
                    value,
                    source_rel_path=self._source_rel_path,
                    doc_slug_by_rel_path=self._doc_slug_by_rel_path,
                    base_url=self._base_url,
                    repo_root=self._repo_root,
                    github_url=self._github_url,
                )
            if value is None:
                parts.append(name)
            else:
                parts.append(f'{name}="{html.escape(value, quote=True)}"')
        return (" " + " ".join(parts)) if parts else ""

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if self._skipping_first_h1:
            return
        if not self._stripped_first_h1 and tag == "h1":
            self._skipping_first_h1 = True
            return

        if self._pending_pre:
            lang = "text"
            if tag == "code":
                for name, value in attrs:
                    if name == "class" and value:
                        for cls in value.split():
                            if cls.startswith("language-"):
                                lang = cls.removeprefix("language-") or "text"
                                break
            self._emit_code_block_open(lang)
            self._pending_pre = False

        if tag == "pre" and not self._in_code_block:
            self._pending_pre = True
            return

        if tag == "table":
            self._out.append('<div class="table-wrap">')

        self._out.append(f"<{tag}{self._format_attrs(tag, attrs)}>")

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if self._skipping_first_h1:
            return
        if self._pending_pre:
            self._emit_code_block_open("text")
            self._pending_pre = False
        self._out.append(f"<{tag}{self._format_attrs(tag, attrs)} />")

    def handle_endtag(self, tag: str) -> None:
        if self._skipping_first_h1:
            if tag == "h1":
                self._skipping_first_h1 = False
                self._stripped_first_h1 = True
            return
        if tag in VOID_ELEMENTS:
            return
        if self._pending_pre:
            self._emit_code_block_open("text")
            self._pending_pre = False
        self._out.append(f"</{tag}>")
        if tag == "table":
            self._out.append("</div>")
        elif tag == "pre" and self._in_code_block:
            self._out.append("</div>")
            self._in_code_block = False

    def handle_data(self, data: str) -> None:
        if self._skipping_first_h1:
            return
        if self._pending_pre:
            if not data.strip():
                return
            self._emit_code_block_open("text")
            self._pending_pre = False
        self._out.append(data)

    def handle_entityref(self, name: str) -> None:
        if not self._skipping_first_h1:
            if self._pending_pre:
                self._emit_code_block_open("text")
                self._pending_pre = False
            self._out.append(f"&{name};")

    def handle_charref(self, name: str) -> None:
        if not self._skipping_first_h1:
            if self._pending_pre:
                self._emit_code_block_open("text")
                self._pending_pre = False
            self._out.append(f"&#{name};")

    def handle_comment(self, data: str) -> None:
        if not self._skipping_first_h1:
            self._out.append(f"<!--{data}-->")


class _TextExtractor(HTMLParser):
    """Extract clean plain text from HTML for excerpts and search snippets."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._chunks: list[str] = []
        self._skip_anchor = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        for name, value in attrs:
            if tag == "a" and name == "class" and value and "heading-anchor" in value.split():
                self._skip_anchor = True

    def handle_endtag(self, tag: str) -> None:
        if tag == "a" and self._skip_anchor:
            self._skip_anchor = False
        if tag in {"p", "li", "h1", "h2", "h3", "h4", "td", "th", "pre", "blockquote"}:
            self._chunks.append(" ")

    def handle_data(self, data: str) -> None:
        if not self._skip_anchor:
            self._chunks.append(data)

    def text(self) -> str:
        return re.sub(r"\s+", " ", "".join(self._chunks)).strip()


def _extract_excerpt(raw_body_html: str) -> tuple[str, str]:
    extractor = _TextExtractor()
    extractor.feed(raw_body_html)
    extractor.close()
    plain = extractor.text()

    match = re.search(r"<p>(.*?)</p>", raw_body_html, flags=re.DOTALL)
    if match:
        para = _TextExtractor()
        para.feed(match.group(1))
        para.close()
        candidate = para.text()
    else:
        candidate = plain

    if len(candidate) > 190:
        candidate = candidate[:187].rsplit(" ", 1)[0] + "..."
    return candidate, plain


def render_markdown(
    markdown_text: str,
    *,
    source_rel_path: str,
    doc_slug_by_rel_path: dict[str, str],
    base_url: str,
    repo_root: Path,
    github_url: str,
) -> RenderedDoc:
    """Render one Markdown document into site-ready HTML and TOC metadata."""
    md = markdown.Markdown(
        extensions=["fenced_code", "tables", "toc", "sane_lists", "def_list"],
        extension_configs={
            "toc": {
                "slugify": github_slugify,
                "permalink": "#",
                "permalink_class": "heading-anchor",
                "permalink_title": "Permalink",
            }
        },
    )
    raw_html = md.convert(markdown_text)
    toc_tokens = getattr(md, "toc_tokens", [])

    title = ""
    if toc_tokens and int(toc_tokens[0].get("level", 0)) == 1:
        title = str(toc_tokens[0].get("name", "")).strip()
    if not title:
        heading_match = re.search(r"^#\s+(.+)$", markdown_text, flags=re.MULTILINE)
        title = heading_match.group(1).strip() if heading_match else PurePosixPath(source_rel_path).stem

    toc_items = tuple(_flatten_toc(toc_tokens))

    processor = _HtmlPostProcessor(
        source_rel_path=source_rel_path,
        doc_slug_by_rel_path=doc_slug_by_rel_path,
        base_url=base_url,
        repo_root=repo_root,
        github_url=github_url,
    )
    processor.feed(raw_html)
    processor.close()
    processed_html = processor.result()

    description, plain_text = _extract_excerpt(processed_html)
    word_count = len(plain_text.split())
    reading_minutes = max(1, round(word_count / 210))

    return RenderedDoc(
        title=title,
        description=description or title,
        html_body=processed_html,
        toc=toc_items,
        plain_text=plain_text,
        reading_minutes=reading_minutes,
    )
