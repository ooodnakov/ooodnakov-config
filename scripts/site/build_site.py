#!/usr/bin/env python3
"""Build the static GitHub Pages site for ooodnakov-config."""

from __future__ import annotations

import argparse
import contextlib
import functools
import html
import http.server
import json
import shutil
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = Path(__file__).resolve().parents[1]
SCRIPTS_CLI_DIR = SCRIPTS_DIR / "cli"
for _path in (REPO_ROOT, SCRIPTS_DIR, SCRIPTS_CLI_DIR):
    if str(_path) not in sys.path:
        sys.path.insert(0, str(_path))

import link_manager  # noqa: E402
import oooconf_cli_spec  # noqa: E402
import profile_manager  # noqa: E402

from scripts.site.markdown_render import RenderedDoc, render_markdown  # noqa: E402

SITE_URL = "https://ooodnakov.github.io/ooodnakov-config"
GITHUB_URL = "https://github.com/ooodnakov/ooodnakov-config"
PLATFORMS: tuple[str, ...] = ("linux", "macos", "windows")
PROFILE_ORDER: tuple[str, ...] = ("minimal", "terminal", "developer", "workstation")

DOC_SECTIONS: tuple[tuple[str, tuple[tuple[str, str, str], ...]], ...] = (
    (
        "Getting Started",
        (
            ("docs/install.md", "install", "Installation"),
            ("docs/profiles.md", "profiles", "Portable Profiles"),
            ("docs/environment.md", "environment", "Environment & Secrets"),
            ("docs/docker-install.md", "docker-install", "Docker Engine Setup"),
        ),
    ),
    (
        "CLI & Workflows",
        (
            ("docs/cli-usage.md", "cli-usage", "CLI Usage"),
            ("docs/cli-reference.md", "cli-reference", "CLI Reference"),
            ("docs/agents.md", "agents", "Agent Policy & MCP"),
            ("docs/fleet-automation.md", "fleet-automation", "SSH Fleet Sync"),
            ("docs/snapshots-and-diagnostics.md", "snapshots-and-diagnostics", "Snapshots & Diagnostics"),
            ("docs/troubleshooting.md", "troubleshooting", "Troubleshooting"),
        ),
    ),
    (
        "Terminals & Desktop",
        (
            ("docs/terminals.md", "terminals", "WezTerm & Ghostty"),
            ("docs/herdr-app.md", "herdr-app", "Herdr App"),
        ),
    ),
    (
        "Architecture & Supply Chain",
        (
            ("docs/architecture.md", "architecture", "Architecture"),
            ("docs/symlink-manifest.md", "symlink-manifest", "Symlink Manifest"),
            ("docs/reproducibility.md", "reproducibility", "Reproducibility"),
            ("docs/dependency-decisions.md", "dependency-decisions", "Dependency Decisions"),
            ("docs/dependency-lock.md", "dependency-lock", "Dependency Lock"),
            ("docs/agents-config-research.md", "agents-config-research", "Agent Config Research"),
            ("docs/imports/upstream-audit.md", "upstream-audit", "Upstream Audit"),
        ),
    ),
    (
        "Contributing & CI",
        (
            ("docs/contributing.md", "contributing", "Contributing"),
            ("docs/cli-extension-guide.md", "cli-extension-guide", "CLI Extension Guide"),
            ("docs/ci-smoke-checks-terminal.md", "ci-smoke-checks-terminal", "Terminal Smoke Checks"),
        ),
    ),
)

COMMAND_FAMILY_MAP = {
    "bootstrap": "core",
    "install": "core",
    "deps": "core",
    "update": "core",
    "upgrade": "core",
    "minimal": "core",
    "plan": "lifecycle",
    "apply": "lifecycle",
    "rollback": "lifecycle",
    "dry-run": "lifecycle",
    "preview": "lifecycle",
    "doctor": "lifecycle",
    "check": "lifecycle",
    "status": "lifecycle",
    "snapshot": "lifecycle",
    "link": "lifecycle",
    "delete": "lifecycle",
    "remove": "lifecycle",
    "lock": "lifecycle",
    "update-pins": "lifecycle",
    "completions": "lifecycle",
    "delta": "lifecycle",
    "agents": "agents",
    "secrets": "secrets",
    "env": "secrets",
    "shell": "shell",
    "color": "shell",
    "help": "shell",
    "version": "shell",
    "wm": "wm",
    "komorebi": "wm",
    "fleet": "fleet",
}

THEME_CHOICES: tuple[tuple[str, str], ...] = (
    ("gruvbox", "Gruvbox"),
    ("noctalia", "Noctalia"),
    ("catppuccin", "Catppuccin"),
    ("nord", "Nord"),
    ("tokyonight", "TokyoNight"),
)


@dataclass(frozen=True)
class DocEntry:
    """One published documentation page."""

    section: str
    source_rel_path: str
    slug: str
    nav_label: str
    rendered: RenderedDoc


@dataclass(frozen=True)
class BuildSummary:
    """Summary of generated site artifacts."""

    output_dir: Path
    doc_count: int
    command_count: int
    dep_count: int


def normalize_base_url(raw: str) -> str:
    """Normalize a GitHub Pages base path into '' or '/subpath'."""
    cleaned = raw.strip().rstrip("/")
    if not cleaned or cleaned == "/":
        return ""
    if not cleaned.startswith("/"):
        cleaned = f"/{cleaned}"
    return cleaned


def url_for(base_url: str, path: str) -> str:
    """Build an internal root-relative URL honoring base_url."""
    suffix = path if path.startswith("/") else f"/{path}"
    return f"{base_url}{suffix}"


def _esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def load_adaptive_banner_svg(repo_root: Path) -> str:
    """Load the tracked ASCII banner SVG with CSS theme variable bindings."""
    svg_path = repo_root / "assets" / "dotfiles-banner-transparent.svg"
    svg = svg_path.read_text(encoding="utf-8").strip()
    svg = svg.replace('width="1390" height="490" ', "")
    svg = svg.replace('aria-labelledby="title desc"', 'class="hero-banner-svg" aria-labelledby="hero-title hero-desc"')
    svg = svg.replace('<title id="title">', '<title id="hero-title">')
    svg = svg.replace('<desc id="desc">', '<desc id="hero-desc">')
    svg = svg.replace('fill="#e9d7ac"', 'fill="var(--banner-fg, #e9d7ac)"')
    svg = svg.replace('stroke="#605947"', 'stroke="var(--banner-rule, #605947)"')
    svg = svg.replace('fill="#ff765b"', 'fill="var(--banner-accent, #ff765b)"')
    return svg


def _flatten_cli_commands(
    commands: dict[str, oooconf_cli_spec.Command],
    prefix: tuple[str, ...] = (),
) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for name, command in commands.items():
        path = (*prefix, name)
        root_name = path[0]
        family = COMMAND_FAMILY_MAP.get(root_name, "core")
        items.append(
            {
                "command": "oooconf " + " ".join(path),
                "name": " ".join(path),
                "family": family,
                "description": command.description,
                "handler_id": command.handler_id,
                "platforms": list(command.platforms),
                "options": list(command.options.keys()),
                "alias_for": command.alias_for,
            }
        )
        if command.subcommands:
            items.extend(_flatten_cli_commands(command.subcommands, path))
    return items


def _resolve_tracked_profile(
    repo_root: Path,
    profile_name: str,
    platform: str,
    capabilities: dict[str, profile_manager.Capability],
) -> dict[str, Any]:
    """Resolve a tracked profile without reading machine-local files or env vars."""
    selected = profile_manager._expand_profile(repo_root, profile_name, capabilities)
    active = tuple(
        cap for cap in selected if not capabilities[cap].platforms or platform in capabilities[cap].platforms
    )
    skipped = tuple(cap for cap in selected if cap not in active)
    links = sorted({link for cap in active for link in capabilities[cap].links})
    deps = list(dict.fromkeys(dep for cap in active for dep in capabilities[cap].dependencies))
    return {
        "capabilities": list(selected),
        "active_capabilities": list(active),
        "skipped_capabilities": list(skipped),
        "links": links,
        "dependencies": deps,
    }


def _collect_tracked_links(repo_root: Path) -> dict[str, dict[str, Any]]:
    """Collect deterministic manifest + auto-discovered links per platform (no local overrides)."""
    all_explicit = link_manager.read_links_manifest(repo_root, None)
    manifest_path = repo_root / "scripts" / "links.toml"
    with manifest_path.open("rb") as stream:
        manifest = tomllib.load(stream)

    by_platform: dict[str, dict[str, Any]] = {}
    for platform in PLATFORMS:
        explicit = link_manager.read_links_manifest(repo_root, platform)
        explicit_keys = {entry["key"] for entry in explicit if entry.get("key")}
        discovered = [
            entry
            for entry in link_manager.discover_links(repo_root, manifest, platform, all_explicit)
            if entry["key"] not in explicit_keys
        ]
        all_keys = [entry.get("key") or Path(entry["target"]).name for entry in (*explicit, *discovered)]
        by_platform[platform] = {
            "explicit_count": len(explicit),
            "discovered_count": len(discovered),
            "total_count": len(explicit) + len(discovered),
            "keys": all_keys,
        }
    return by_platform


def collect_repo_data(repo_root: Path) -> dict[str, Any]:
    """Extract live, reproducible repository metadata for the site."""
    cli_spec = oooconf_cli_spec.load_cli_spec(repo_root / "scripts/cli/oooconf-cli-spec.toml")
    cli_commands = _flatten_cli_commands(cli_spec.commands)

    capabilities = profile_manager.load_capabilities(repo_root)
    profile_descriptions = cli_spec.definitions.get("profiles", {})
    profiles_data: dict[str, Any] = {}
    for profile_name in PROFILE_ORDER:
        profile_path = repo_root / "home/.config/ooodnakov/profiles" / f"{profile_name}.toml"
        with profile_path.open("rb") as stream:
            raw_profile = tomllib.load(stream).get("profile", {})
        profiles_data[profile_name] = {
            "name": profile_name,
            "extends": raw_profile.get("extends"),
            "description": profile_descriptions.get(profile_name, ""),
            "platforms": {
                platform: _resolve_tracked_profile(repo_root, profile_name, platform, capabilities)
                for platform in PLATFORMS
            },
        }

    with (repo_root / "scripts/optional-deps.toml").open("rb") as stream:
        deps_doc = tomllib.load(stream)

    managed_tools = deps_doc.get("managed-tools", {})
    minimal_section = deps_doc.get("minimal", {})
    minimal_global = set(minimal_section.get("keys", []))
    minimal_windows = set(minimal_section.get("windows", {}).get("keys", []))
    optional_deps: list[dict[str, Any]] = []
    for entry in deps_doc.get("deps", []):
        key = str(entry.get("key", ""))
        dep_platforms = [plat for plat in PLATFORMS if plat in entry]
        optional_deps.append(
            {
                "key": key,
                "display": str(entry.get("display", key)),
                "description": str(entry.get("description", "")),
                "version": str(entry["ver"]) if entry.get("ver") is not None else "",
                "minimal": key in minimal_global or key in minimal_windows,
                "platforms": dep_platforms,
            }
        )

    agents_common = json.loads(
        (repo_root / "home/.config/ooodnakov/agents/common-data.json").read_text(encoding="utf-8")
    )
    agent_keys = cli_spec.definitions.get("agent_keys", {})
    links_by_platform = _collect_tracked_links(repo_root)

    return {
        "stats": {
            "platforms": len(PLATFORMS),
            "profiles": len(profiles_data),
            "cli_commands": len(cli_commands),
            "optional_deps": len(optional_deps),
            "managed_zsh_tools": len(managed_tools),
            "mcp_servers": len(agents_common.get("mcp_servers", {})),
            "agent_targets": len(agent_keys),
            "links_by_platform": {p: links_by_platform[p]["total_count"] for p in PLATFORMS},
        },
        "profiles": profiles_data,
        "cli_commands": cli_commands,
        "optional_deps": optional_deps,
        "links": links_by_platform,
        "agents": {
            "targets": agent_keys,
            "mcp_servers": list(agents_common.get("mcp_servers", {}).keys()),
            "skills": agents_common.get("skills", []),
        },
    }


def _render_head(*, title: str, description: str, canonical_path: str, base_url: str) -> str:
    canonical = f"{SITE_URL}{canonical_path}"
    og_image = f"{SITE_URL}/assets/dotfiles-banner-transparent.svg"
    favicon = url_for(base_url, "/assets/favicon.svg")
    css_href = url_for(base_url, "/assets/style.css")
    js_src = url_for(base_url, "/assets/app.js")
    return f"""<!doctype html>
<html lang="en" data-theme="gruvbox" data-mode="dark">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{_esc(title)}</title>
  <meta name="description" content="{_esc(description)}">
  <meta name="site-base" content="{_esc(base_url)}">
  <link rel="canonical" href="{_esc(canonical)}">
  <link rel="icon" type="image/svg+xml" href="{_esc(favicon)}">
  <meta property="og:type" content="website">
  <meta property="og:title" content="{_esc(title)}">
  <meta property="og:description" content="{_esc(description)}">
  <meta property="og:url" content="{_esc(canonical)}">
  <meta property="og:image" content="{_esc(og_image)}">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600;700&family=Space+Grotesk:wght@400;500;600;700&display=swap">
  <link rel="stylesheet" href="{_esc(css_href)}">
  <script>
    (() => {{
      try {{
        const t = localStorage.getItem("oooconf-theme");
        const m = localStorage.getItem("oooconf-mode");
        const valid = ["gruvbox", "noctalia", "catppuccin", "nord", "tokyonight"];
        if (t && valid.includes(t)) document.documentElement.dataset.theme = t;
        if (m === "light" || m === "dark") document.documentElement.dataset.mode = m;
        else if (window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches) {{
          document.documentElement.dataset.mode = "light";
        }}
      }} catch {{}}
    }})();
  </script>
  <script defer src="{_esc(js_src)}"></script>
</head>"""


def _render_nav(base_url: str, *, active: str = "home") -> str:
    home_url = url_for(base_url, "/")
    docs_url = url_for(base_url, "/docs/")
    logo_url = url_for(base_url, "/assets/favicon.svg")
    options = "\n".join(f'          <option value="{_esc(key)}">{_esc(label)}</option>' for key, label in THEME_CHOICES)
    return f"""  <a class="skip-link" href="#main-content">Skip to content</a>
  <header class="site-nav">
    <div class="container nav-inner">
      <a class="nav-brand" href="{_esc(home_url)}">
        <img class="nav-logo" src="{_esc(logo_url)}" alt="" width="28" height="28">
        <span>ooodnakov-config</span>
      </a>
      <nav class="nav-links" aria-label="Primary">
        <a href="{_esc(home_url)}#quick-start">Quick Start</a>
        <a href="{_esc(home_url)}#profiles">Profiles</a>
        <a href="{_esc(home_url)}#cli">CLI</a>
        <a href="{_esc(home_url)}#stack">Stack</a>
        <a href="{_esc(docs_url)}" class="{"is-active" if active == "docs" else ""}">Docs</a>
      </nav>
      <div class="nav-actions">
        <button type="button" class="search-trigger" data-open-search aria-label="Search docs and CLI">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
          <span>Search</span>
          <kbd>Ctrl K</kbd>
        </button>
        <label class="sr-only" for="theme-select">Color theme</label>
        <select id="theme-select" class="theme-select" aria-label="Color theme">
{options}
        </select>
        <button type="button" id="mode-toggle" class="icon-btn" aria-label="Toggle color mode" title="Toggle dark/light mode">
          <svg data-icon="sun" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/></svg>
          <svg data-icon="moon" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true" style="display:none"><path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/></svg>
        </button>
        <a class="icon-btn" href="{_esc(GITHUB_URL)}" target="_blank" rel="noopener noreferrer" aria-label="GitHub repository">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 .5a12 12 0 0 0-3.79 23.39c.6.11.82-.26.82-.58v-2.02c-3.34.73-4.04-1.61-4.04-1.61a3.18 3.18 0 0 0-1.34-1.76c-1.1-.75.08-.73.08-.73a2.52 2.52 0 0 1 1.84 1.24 2.56 2.56 0 0 0 3.5 1 2.56 2.56 0 0 1 .76-1.61c-2.66-.3-5.47-1.33-5.47-5.93a4.64 4.64 0 0 1 1.24-3.22 4.3 4.3 0 0 1 .12-3.18s1.01-.32 3.3 1.23a11.38 11.38 0 0 1 6 0c2.29-1.55 3.3-1.23 3.3-1.23a4.3 4.3 0 0 1 .12 3.18 4.64 4.64 0 0 1 1.24 3.22c0 4.61-2.81 5.63-5.48 5.92a2.86 2.86 0 0 1 .82 2.22v3.29c0 .32.22.7.83.58A12 12 0 0 0 12 .5Z"/></svg>
        </a>
      </div>
    </div>
  </header>"""


def _render_search_modal() -> str:
    return """  <div id="search-modal" class="search-modal" hidden role="dialog" aria-modal="true" aria-labelledby="search-modal-label">
    <div class="search-dialog">
      <div class="search-dialog-head">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
        <label id="search-modal-label" class="sr-only" for="search-modal-input">Search documentation and CLI commands</label>
        <input id="search-modal-input" class="search-dialog-input" type="search" placeholder="Search docs, headings, or oooconf commands..." autocomplete="off">
        <kbd class="plat-tag">Esc</kbd>
      </div>
      <div id="search-results" class="search-results"></div>
    </div>
  </div>"""


def _render_footer(base_url: str, doc_count: int) -> str:
    docs_url = url_for(base_url, "/docs/")
    return f"""  <footer class="site-footer">
    <div class="container footer-inner">
      <div>
        <strong>ooodnakov-config</strong> · MIT License · Generated from live repo specs ({doc_count} guides)
      </div>
      <div class="footer-links">
        <a href="{_esc(docs_url)}">Documentation</a>
        <a href="{_esc(url_for(base_url, "/docs/cli-reference/"))}">CLI Reference</a>
        <a href="{_esc(url_for(base_url, "/docs/reproducibility/"))}">Reproducibility</a>
        <a href="{_esc(GITHUB_URL)}" target="_blank" rel="noopener noreferrer">GitHub</a>
      </div>
    </div>
  </footer>"""


def _render_hero_section(stats: dict[str, Any], banner_svg: str, base_url: str, doc_count: int) -> str:
    return f"""    <section class="hero">
      <div class="container hero-inner">
        <span class="hero-badge">
          <span class="hero-badge-dot" aria-hidden="true"></span>
          Linux · macOS · Windows · Transactional CLI (<code>oooconf</code> / <code>o</code>)
        </span>
        <div class="hero-banner-wrap">
          {banner_svg}
        </div>
        <h1 class="hero-title">Reproducible workstations, orchestrated by one CLI.</h1>
        <p class="hero-lead">
          Tracked base configs under <code>home/</code>, SHA-256 verified installs, dry-run operation plans with
          automatic rollback, Bitwarden secrets rendering, and synchronized AI agent policies — zero secrets in git.
        </p>
        <div class="hero-cta">
          <a class="btn btn-primary" href="#quick-start">Quick Start</a>
          <a class="btn btn-secondary" href="{_esc(url_for(base_url, "/docs/"))}">Browse {doc_count} Docs</a>
          <a class="btn btn-secondary" href="{_esc(GITHUB_URL)}" target="_blank" rel="noopener noreferrer">View on GitHub</a>
        </div>
        <div class="metrics-strip" aria-label="Repository overview metrics">
          <div class="metric-card">
            <span class="metric-value">{stats["cli_commands"]}</span>
            <span class="metric-label">oooconf commands &amp; subcommands</span>
          </div>
          <div class="metric-card">
            <span class="metric-value">{stats["optional_deps"]}</span>
            <span class="metric-label">Pinned optional dependencies</span>
          </div>
          <div class="metric-card">
            <span class="metric-value">{stats["profiles"]}</span>
            <span class="metric-label">Portable capability profiles</span>
          </div>
          <div class="metric-card">
            <span class="metric-value">{stats["agent_targets"]}</span>
            <span class="metric-label">Synced AI agent CLIs ({stats["mcp_servers"]} MCPs)</span>
          </div>
        </div>
      </div>
    </section>"""


def _render_quickstart_section(base_url: str) -> str:
    unix_install = (
        "git clone https://github.com/ooodnakov/ooodnakov-config.git ~/src/ooodnakov-config\n"
        "cd ~/src/ooodnakov-config\n"
        "./home/.config/ooodnakov/bin/oooconf install"
    )
    minimal_install = (
        'f=$(mktemp "${TMPDIR:-/tmp}/ooodnakov-bootstrap.XXXXXX")\n'
        'curl -fsSLo "$f" https://raw.githubusercontent.com/ooodnakov/ooodnakov-config/main/bootstrap.sh\n'
        'less "$f" && bash "$f" minimal --min-dep\n'
        'rm -f "$f"'
    )
    windows_install = (
        "git clone https://github.com/ooodnakov/ooodnakov-config.git $HOME\\src\\ooodnakov-config\n"
        "Set-Location $HOME\\src\\ooodnakov-config\n"
        "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass\n"
        ".\\home\\.config\\ooodnakov\\bin\\oooconf.ps1 install"
    )
    return f"""    <section id="quick-start" class="section">
      <div class="container">
        <div class="section-header">
          <div>
            <span class="section-kicker">01 · Quick Start</span>
            <h2 class="section-title">Inspect first, apply transactionally</h2>
            <p class="section-subtitle">
              Every installer avoids blind <code>curl | sh</code> piping and delegates link changes to the transactional
              <code>oooconf</code> planner with automatic backups and rollback.
            </p>
          </div>
          <a class="btn btn-secondary btn-sm" href="{_esc(url_for(base_url, "/docs/install/"))}">Full install guide →</a>
        </div>

        <div class="terminal-card">
          <div class="terminal-chrome">
            <div class="terminal-dots" aria-hidden="true">
              <span class="dot-red"></span><span class="dot-amber"></span><span class="dot-green"></span>
            </div>
            <div class="tab-group" role="tablist" aria-label="Install methods">
              <button type="button" class="tab-btn is-active" data-qs-tab="unix" role="tab">Linux / macOS</button>
              <button type="button" class="tab-btn" data-qs-tab="minimal" role="tab">Bootstrap Minimal</button>
              <button type="button" class="tab-btn" data-qs-tab="windows" role="tab">Windows PowerShell</button>
            </div>
          </div>
          <div class="terminal-body">
            <div class="terminal-panel is-active" data-qs-panel="unix">
              <div class="code-head">
                <span class="code-lang">bash · recommended clone &amp; inspect</span>
                <button type="button" class="copy-btn" data-copy-target="#qs-unix-code">Copy</button>
              </div>
              <pre id="qs-unix-code" class="terminal-pre"><code>{_esc(unix_install)}</code></pre>
              <p class="terminal-note">
                After install, <code>oooconf</code> and alias <code>o</code> are linked into <code>~/.local/bin</code>.
              </p>
            </div>
            <div class="terminal-panel" data-qs-panel="minimal">
              <div class="code-head">
                <span class="code-lang">bash · sparse checkout + minimal tools</span>
                <button type="button" class="copy-btn" data-copy-target="#qs-min-code">Copy</button>
              </div>
              <pre id="qs-min-code" class="terminal-pre"><code>{_esc(minimal_install)}</code></pre>
              <p class="terminal-note">
                Downloads <code>bootstrap.sh</code> for inspection first; applies only the <code>minimal</code> profile and core CLI set.
              </p>
            </div>
            <div class="terminal-panel" data-qs-panel="windows">
              <div class="code-head">
                <span class="code-lang">powershell · pwsh + Git Bash zsh</span>
                <button type="button" class="copy-btn" data-copy-target="#qs-win-code">Copy</button>
              </div>
              <pre id="qs-win-code" class="terminal-pre"><code>{_esc(windows_install)}</code></pre>
              <p class="terminal-note">
                Installs wrappers into <code>$HOME\\.local\\bin</code> and optionally provisions pinned MSYS2 zsh inside Git Bash.
              </p>
            </div>
          </div>
        </div>

        <div class="safety-row">
          <div class="safety-pill">Preview changes first: <code>oooconf dry-run</code></div>
          <div class="safety-pill">Verify machine health: <code>oooconf doctor</code></div>
          <div class="safety-pill">Undo last link batch: <code>oooconf rollback --last</code></div>
        </div>
      </div>
    </section>"""


def _render_pillars_section(stats: dict[str, Any], base_url: str) -> str:
    return f"""    <section class="section">
      <div class="container">
        <div class="section-header">
          <div>
            <span class="section-kicker">02 · Core Architecture</span>
            <h2 class="section-title">Designed for repeatability and safe recovery</h2>
          </div>
        </div>
        <div class="bento-grid">
          <article class="card">
            <div class="card-icon" aria-hidden="true">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>
            </div>
            <h3>Transactional Symlinks</h3>
            <p>Auto-discovery under <code>home/.config</code> + explicit platform manifest, staged via <code>plan</code> and reversible via journaled <code>rollback --last</code>.</p>
            <a class="card-footer-link" href="{_esc(url_for(base_url, "/docs/symlink-manifest/"))}">Symlink manifest →</a>
          </article>
          <article class="card">
            <div class="card-icon" aria-hidden="true">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
            </div>
            <h3>Supply-Chain Verified</h3>
            <p>Direct release archives check SHA-256 digests, extract without path traversal or symlinks, and lockfile drift is enforced in CI.</p>
            <a class="card-footer-link" href="{_esc(url_for(base_url, "/docs/dependency-lock/"))}">Dependency lock →</a>
          </article>
          <article class="card">
            <div class="card-icon" aria-hidden="true">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
            </div>
            <h3>Zero-Leak Secrets Sync</h3>
            <p>Bitwarden/Vaultwarden renders machine-local env files around preserved <code>LOCAL OVERRIDES</code> markers — tokens never touch git.</p>
            <a class="card-footer-link" href="{_esc(url_for(base_url, "/docs/environment/"))}">Environment &amp; secrets →</a>
          </article>
          <article class="card">
            <div class="card-icon" aria-hidden="true">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/></svg>
            </div>
            <h3>Unified Agent Policy</h3>
            <p>One source of truth syncs shared <code>AGENTS.md</code> rules, {stats["mcp_servers"]} MCP servers, providers, and skills across {stats["agent_targets"]} coding agents.</p>
            <a class="card-footer-link" href="{_esc(url_for(base_url, "/docs/agents/"))}">Agent policy →</a>
          </article>
          <article class="card">
            <div class="card-icon" aria-hidden="true">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8M12 17v4"/></svg>
            </div>
            <h3>Terminals &amp; WMs</h3>
            <p>Shared WezTerm &amp; Ghostty configs, Herdr layouts, PowerShell/zsh parity, and desktop presets for Niri, Hyprland, Komorebi, GlazeWM, and AeroSpace.</p>
            <a class="card-footer-link" href="{_esc(url_for(base_url, "/docs/terminals/"))}">Terminal guide →</a>
          </article>
          <article class="card">
            <div class="card-icon" aria-hidden="true">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 17l6-6-6-6M12 19h8"/></svg>
            </div>
            <h3>SSH Fleet &amp; Snapshots</h3>
            <p>Export portable capability snapshots or run <code>oooconf fleet sync --all</code> over persistent SSH sessions with automatic retries.</p>
            <a class="card-footer-link" href="{_esc(url_for(base_url, "/docs/fleet-automation/"))}">Fleet automation →</a>
          </article>
        </div>
      </div>
    </section>"""


def _render_profiles_section(repo_data: dict[str, Any], base_url: str) -> str:
    default_profile = repo_data["profiles"]["developer"]["platforms"]["linux"]
    caps_html = "".join(
        f'<span class="chip chip-active">{_esc(c)}</span>' for c in default_profile["active_capabilities"]
    )
    links_html = "".join(f'<span class="chip">{_esc(link)}</span>' for link in default_profile["links"])
    deps_html = "".join(f'<span class="chip">{_esc(dep)}</span>' for dep in default_profile["dependencies"])
    return f"""    <section id="profiles" class="section">
      <div class="container">
        <div class="section-header">
          <div>
            <span class="section-kicker">03 · Portable Profiles</span>
            <h2 class="section-title">Inspect what each profile installs per OS</h2>
            <p class="section-subtitle">
              Profiles compose capability bundles cleanly and skip OS-specific desktop links when targeting another platform.
            </p>
          </div>
          <a class="btn btn-secondary btn-sm" href="{_esc(url_for(base_url, "/docs/profiles/"))}">Profile spec →</a>
        </div>

        <div id="profile-explorer" class="explorer-panel">
          <div class="explorer-toolbar">
            <div class="pill-group" role="group" aria-label="Profile selector">
              <button type="button" class="pill-btn" data-profile-pick="minimal">minimal</button>
              <button type="button" class="pill-btn" data-profile-pick="terminal">terminal</button>
              <button type="button" class="pill-btn is-active" data-profile-pick="developer">developer</button>
              <button type="button" class="pill-btn" data-profile-pick="workstation">workstation</button>
            </div>
            <div class="pill-group" role="group" aria-label="Target OS selector">
              <button type="button" class="pill-btn is-active" data-profile-platform="linux">Linux</button>
              <button type="button" class="pill-btn" data-profile-platform="macos">macOS</button>
              <button type="button" class="pill-btn" data-profile-platform="windows">Windows</button>
            </div>
          </div>

          <div class="profile-summary-bar">
            <div id="profile-summary-desc">developer (extends terminal) — terminal plus development and agent tooling</div>
            <div class="profile-cmd">
              <code id="profile-command-text">oooconf install --profile developer</code>
              <button id="profile-command-copy" type="button" class="copy-btn" data-copy-text="oooconf install --profile developer">Copy</button>
            </div>
          </div>

          <div class="profile-columns">
            <div class="profile-box">
              <h4>Capabilities <span id="profile-caps-count">{len(default_profile["active_capabilities"])} active</span></h4>
              <div id="profile-caps-list" class="chip-list">{caps_html}</div>
            </div>
            <div class="profile-box">
              <h4>Managed Links <span id="profile-links-count">{len(default_profile["links"])} links</span></h4>
              <div id="profile-links-list" class="chip-list">{links_html}</div>
            </div>
            <div class="profile-box">
              <h4>Dependencies <span id="profile-deps-count">{len(default_profile["dependencies"])} deps</span></h4>
              <div id="profile-deps-list" class="chip-list">{deps_html}</div>
            </div>
          </div>
        </div>
      </div>
    </section>"""


def _render_themes_section() -> str:
    theme_buttons = "\n".join(
        f'          <button type="button" class="pill-btn {"is-active" if key == "gruvbox" else ""}" data-theme-pick="{_esc(key)}">{_esc(label)}</button>'
        for key, label in THEME_CHOICES
    )
    return f"""    <section id="themes" class="section">
      <div class="container">
        <div class="section-header">
          <div>
            <span class="section-kicker">04 · Unified Color System</span>
            <h2 class="section-title">Live preview of <code>oooconf color</code></h2>
            <p class="section-subtitle">
              Syncs WezTerm, Ghostty, Herdr, Komorebi, SketchyBar, Zebar, and CLI palettes together across dark &amp; light modes.
            </p>
          </div>
        </div>
        <div class="theme-bar">
          <div class="pill-group" role="group" aria-label="Color themes">
{theme_buttons}
          </div>
          <div class="pill-group" role="group" aria-label="Color mode">
            <button type="button" class="pill-btn is-active" data-mode-pick="dark">Dark</button>
            <button type="button" class="pill-btn" data-mode-pick="light">Light</button>
          </div>
          <div id="theme-swatches" class="swatch-row" aria-label="Active palette swatches"></div>
          <div class="profile-cmd">
            <code id="theme-command-text">oooconf color gruvbox dark</code>
            <button id="theme-command-copy" type="button" class="copy-btn" data-copy-text="oooconf color gruvbox dark">Copy</button>
          </div>
        </div>
      </div>
    </section>"""


def _render_cli_section(repo_data: dict[str, Any], base_url: str) -> str:
    stats = repo_data["stats"]
    initial_cli = repo_data["cli_commands"][:18]
    initial_cli_html = "\n".join(
        f"""          <article class="cli-item">
            <div class="cli-item-top">
              <code class="cli-cmd">{_esc(cmd["command"])}</code>
              <div class="cli-platforms">{"".join(f'<span class="plat-tag">{_esc(p)}</span>' for p in cmd["platforms"])}</div>
            </div>
            <p class="cli-desc">{_esc(cmd["description"])}</p>
            {f'<div class="cli-meta">{"".join(f'<span class="opt-tag">{_esc(opt)}</span>' for opt in cmd["options"][:6])}</div>' if cmd["options"] else ""}
          </article>"""
        for cmd in initial_cli
    )
    return f"""    <section id="cli" class="section">
      <div class="container">
        <div class="section-header">
          <div>
            <span class="section-kicker">05 · CLI Explorer</span>
            <h2 class="section-title">Every command parsed out of <code>oooconf-cli-spec.toml</code></h2>
            <p class="section-subtitle">
              Filter all {stats["cli_commands"]} commands across lifecycle, agents, secrets, shell preferences, window managers, and SSH fleet sync.
            </p>
          </div>
          <a class="btn btn-secondary btn-sm" href="{_esc(url_for(base_url, "/docs/cli-reference/"))}">Full matrix →</a>
        </div>

        <div class="filter-bar">
          <label class="sr-only" for="cli-search">Filter CLI commands</label>
          <input id="cli-search" class="search-input" type="search" placeholder="Search commands, flags, or descriptions (e.g. rollback, secrets, mcp, fleet)...">
          <div class="pill-group" role="group" aria-label="Command family filter">
            <button type="button" class="pill-btn is-active" data-cli-family="all">All</button>
            <button type="button" class="pill-btn" data-cli-family="core">Core</button>
            <button type="button" class="pill-btn" data-cli-family="lifecycle">Lifecycle</button>
            <button type="button" class="pill-btn" data-cli-family="agents">Agents</button>
            <button type="button" class="pill-btn" data-cli-family="secrets">Secrets</button>
            <button type="button" class="pill-btn" data-cli-family="shell">Shell</button>
            <button type="button" class="pill-btn" data-cli-family="wm">WM</button>
            <button type="button" class="pill-btn" data-cli-family="fleet">Fleet</button>
          </div>
          <div class="pill-group" role="group" aria-label="CLI platform filter">
            <button type="button" class="pill-btn is-active" data-cli-platform="all">All OS</button>
            <button type="button" class="pill-btn" data-cli-platform="linux">Linux</button>
            <button type="button" class="pill-btn" data-cli-platform="macos">macOS</button>
            <button type="button" class="pill-btn" data-cli-platform="windows">Windows</button>
          </div>
        </div>
        <p id="cli-status" class="explorer-status">Showing {len(initial_cli)} of {stats["cli_commands"]} commands</p>
        <div id="cli-list" class="cli-list">
{initial_cli_html}
        </div>
      </div>
    </section>"""


def _render_stack_section(repo_data: dict[str, Any], base_url: str) -> str:
    stats = repo_data["stats"]
    initial_deps = [dep for dep in repo_data["optional_deps"] if dep["minimal"]]
    initial_deps_html = "\n".join(
        f"""          <article class="dep-card">
            <div class="dep-head">
              <span class="dep-name">{_esc(dep["key"])}</span>
              {f'<span class="dep-ver">{_esc(dep["version"])}</span>' if dep["version"] else ""}
            </div>
            <p class="dep-desc">{_esc(dep["description"])}</p>
            <div class="chip-list">
              <span class="chip chip-minimal">minimal</span>
              {"".join(f'<span class="plat-tag">{_esc(p)}</span>' for p in dep["platforms"])}
            </div>
          </article>"""
        for dep in initial_deps
    )
    return f"""    <section id="stack" class="section">
      <div class="container">
        <div class="section-header">
          <div>
            <span class="section-kicker">06 · Managed Stack &amp; Dependencies</span>
            <h2 class="section-title">Cross-platform targets &amp; {stats["optional_deps"]} pinned tools</h2>
            <p class="section-subtitle">
              Includes {stats["managed_zsh_tools"]} commit-pinned zsh plugins/themes alongside deterministic per-OS symlink targets.
            </p>
          </div>
          <a class="btn btn-secondary btn-sm" href="{_esc(url_for(base_url, "/docs/dependency-decisions/"))}">Dependency matrix →</a>
        </div>

        <div class="platform-matrix">
          <article class="platform-card">
            <h3>Linux <span class="platform-count">{stats["links_by_platform"]["linux"]} links</span></h3>
            <p class="cli-desc">First-class Zsh + LazyVim + WezTerm/Ghostty + desktop integration.</p>
            <ul>
              <li>Window managers: <strong>Niri, Hyprland/Pyprland, Umbriel, Noctalia</strong></li>
              <li>Shell: modular <code>zsh</code>, Powerlevel10k, {stats["managed_zsh_tools"]} pinned plugins</li>
              <li>Audio/system: CAVA, btop, fastfetch, Docker guide</li>
            </ul>
          </article>
          <article class="platform-card">
            <h3>macOS <span class="platform-count">{stats["links_by_platform"]["macos"]} links</span></h3>
            <p class="cli-desc">Homebrew-backed CLI &amp; tiling desktop parity.</p>
            <ul>
              <li>Desktop: <strong>AeroSpace, OmniWM, SketchyBar, JankyBorders</strong></li>
              <li>Terminals: WezTerm, Ghostty, Meslo Nerd Font</li>
              <li>Full zsh, LazyVim, Yazi, and agent toolchain</li>
            </ul>
          </article>
          <article class="platform-card">
            <h3>Windows <span class="platform-count">{stats["links_by_platform"]["windows"]} links</span></h3>
            <p class="cli-desc">PowerShell Core + Noctty + Git Bash MSYS2 zsh stack.</p>
            <ul>
              <li>Desktop: <strong>Komorebi, GlazeWM, Zebar</strong>, whkdrc</li>
              <li>Shells: PowerShell + Oh My Posh + pinned MSYS2 zsh in Git Bash</li>
              <li>Native wrappers: <code>oooconf.ps1</code>, <code>o.cmd</code>, Herdr app</li>
            </ul>
          </article>
        </div>

        <div class="filter-bar">
          <label class="sr-only" for="deps-search">Search optional dependencies</label>
          <input id="deps-search" class="search-input" type="search" placeholder="Filter optional dependencies (e.g. fzf, neovim, uv, yazi)...">
          <div class="pill-group" role="group" aria-label="Dependency filter">
            <button type="button" class="pill-btn is-active" data-deps-filter="minimal">Minimal Set</button>
            <button type="button" class="pill-btn" data-deps-filter="all">All ({stats["optional_deps"]})</button>
            <button type="button" class="pill-btn" data-deps-filter="linux">Linux</button>
            <button type="button" class="pill-btn" data-deps-filter="macos">macOS</button>
            <button type="button" class="pill-btn" data-deps-filter="windows">Windows</button>
          </div>
        </div>
        <p id="deps-status" class="explorer-status">Showing {len(initial_deps)} minimal packages ({stats["optional_deps"]} total)</p>
        <div id="deps-grid" class="deps-grid">
{initial_deps_html}
        </div>
      </div>
    </section>"""


def _render_docs_section(docs: list[DocEntry], base_url: str) -> str:
    docs_cards_html = "\n".join(
        f"""          <div class="docs-group-card">
            <h3>{_esc(section_name)}</h3>
            <ul class="docs-group-list">
              {"".join(f'<li><a href="{_esc(url_for(base_url, f"/docs/{doc.slug}/"))}"><span class="doc-link-title">{_esc(doc.nav_label)}</span><span class="doc-link-desc">{_esc(doc.rendered.description)}</span></a></li>' for doc in docs if doc.section == section_name)}
            </ul>
          </div>"""
        for section_name, _ in DOC_SECTIONS
    )
    return f"""    <section id="docs-showcase" class="section">
      <div class="container">
        <div class="section-header">
          <div>
            <span class="section-kicker">07 · Documentation Portal</span>
            <h2 class="section-title">All {len(docs)} guides rendered with search &amp; deep anchors</h2>
            <p class="section-subtitle">
              Press <kbd class="plat-tag">Ctrl K</kbd> or <kbd class="plat-tag">/</kbd> anywhere to jump directly to a guide, heading, or command.
            </p>
          </div>
          <a class="btn btn-primary btn-sm" href="{_esc(url_for(base_url, "/docs/"))}">Open Docs Hub</a>
        </div>
        <div class="docs-hub-grid">
{docs_cards_html}
        </div>
      </div>
    </section>"""


def _render_home(
    repo_data: dict[str, Any],
    docs: list[DocEntry],
    banner_svg: str,
    base_url: str,
) -> str:
    stats = repo_data["stats"]
    head = _render_head(
        title="ooodnakov-config — Reproducible Cross-Platform Dotfiles",
        description=(
            "Opinionated, reproducible dotfiles for Linux, Windows, and macOS driven by the oooconf CLI "
            "with transactional links, portable profiles, pinned dependencies, and agent tooling."
        ),
        canonical_path="/",
        base_url=base_url,
    )
    sections = "\n".join(
        (
            _render_hero_section(stats, banner_svg, base_url, len(docs)),
            _render_quickstart_section(base_url),
            _render_pillars_section(stats, base_url),
            _render_profiles_section(repo_data, base_url),
            _render_themes_section(),
            _render_cli_section(repo_data, base_url),
            _render_stack_section(repo_data, base_url),
            _render_docs_section(docs, base_url),
        )
    )
    return (
        f"{head}\n<body>\n{_render_nav(base_url, active='home')}\n"
        f'  <main id="main-content">\n{sections}\n  </main>\n'
        f"{_render_search_modal()}\n{_render_footer(base_url, len(docs))}\n</body>\n</html>\n"
    )


def _render_docs_sidebar(docs: list[DocEntry], base_url: str, current_slug: str | None = None) -> str:
    groups: list[str] = []
    for section_name, _ in DOC_SECTIONS:
        section_docs = [doc for doc in docs if doc.section == section_name]
        items = "\n".join(
            f'            <li><a href="{_esc(url_for(base_url, f"/docs/{doc.slug}/"))}" '
            f'class="{"is-current" if doc.slug == current_slug else ""}">{_esc(doc.nav_label)}</a></li>'
            for doc in section_docs
        )
        groups.append(
            f'        <div class="docs-nav-group">\n'
            f'          <h2 class="docs-nav-heading">{_esc(section_name)}</h2>\n'
            f'          <ul class="docs-nav-items">\n{items}\n          </ul>\n'
            f"        </div>"
        )
    return "\n".join(groups)


def _render_docs_hub(docs: list[DocEntry], base_url: str) -> str:
    head = _render_head(
        title="Documentation — ooodnakov-config",
        description="Complete documentation hub for ooodnakov-config: installation, CLI reference, profiles, agents, and troubleshooting.",
        canonical_path="/docs/",
        base_url=base_url,
    )
    groups_html = "\n".join(
        f"""        <section class="docs-group-card">
          <h2>{_esc(section_name)}</h2>
          <ul class="docs-group-list">
            {"".join(f'<li><a href="{_esc(url_for(base_url, f"/docs/{doc.slug}/"))}"><span class="doc-link-title">{_esc(doc.rendered.title)}</span><span class="doc-link-desc">{_esc(doc.rendered.description)}</span></a></li>' for doc in docs if doc.section == section_name)}
          </ul>
        </section>"""
        for section_name, _ in DOC_SECTIONS
    )
    return f"""{head}
<body>
{_render_nav(base_url, active="docs")}
  <main id="main-content" class="container" style="padding-top: 36px; padding-bottom: 64px;">
    <div class="section-header">
      <div>
        <span class="section-kicker">Documentation Hub</span>
        <h1 class="section-title">Everything in <code>docs/</code> ({len(docs)} guides)</h1>
        <p class="section-subtitle">
          Built straight from the repository Markdown sources with preserved cross-links and search indexing.
        </p>
      </div>
      <button type="button" class="btn btn-secondary btn-sm" data-open-search>Search Docs (Ctrl K)</button>
    </div>
    <div class="docs-hub-grid">
{groups_html}
    </div>
  </main>
{_render_search_modal()}
{_render_footer(base_url, len(docs))}
</body>
</html>
"""


def _render_doc_page(doc: DocEntry, idx: int, docs: list[DocEntry], base_url: str) -> str:
    head = _render_head(
        title=f"{doc.rendered.title} — ooodnakov-config Docs",
        description=doc.rendered.description,
        canonical_path=f"/docs/{doc.slug}/",
        base_url=base_url,
    )
    sidebar_html = _render_docs_sidebar(docs, base_url, current_slug=doc.slug)

    toc_html = ""
    if doc.rendered.toc:
        toc_items = "\n".join(
            f'          <li class="toc-level-{item.level}"><a href="#{_esc(item.id)}">{_esc(item.title)}</a></li>'
            for item in doc.rendered.toc
        )
        toc_html = f"""      <aside class="docs-toc" aria-label="On this page">
        <p class="docs-toc-title">On This Page</p>
        <ul>
{toc_items}
        </ul>
      </aside>"""

    prev_doc = docs[idx - 1] if idx > 0 else None
    next_doc = docs[idx + 1] if idx + 1 < len(docs) else None
    prev_html = (
        f'<a class="page-link" href="{_esc(url_for(base_url, f"/docs/{prev_doc.slug}/"))}">'
        f'<span class="page-link-label">← Previous</span>'
        f'<span class="page-link-title">{_esc(prev_doc.nav_label)}</span></a>'
        if prev_doc
        else ""
    )
    next_html = (
        f'<a class="page-link page-link-next" href="{_esc(url_for(base_url, f"/docs/{next_doc.slug}/"))}">'
        f'<span class="page-link-label">Next →</span>'
        f'<span class="page-link-title">{_esc(next_doc.nav_label)}</span></a>'
        if next_doc
        else ""
    )

    source_github = f"{GITHUB_URL}/blob/main/{doc.source_rel_path}"

    return f"""{head}
<body>
{_render_nav(base_url, active="docs")}
  <div id="main-content" class="container docs-shell">
    <aside id="docs-sidebar" class="docs-sidebar" aria-label="Documentation navigation">
{sidebar_html}
    </aside>

    <main class="docs-main">
      <button id="docs-sidebar-toggle" type="button" class="btn btn-secondary btn-sm docs-mobile-toggle" aria-expanded="false" aria-controls="docs-sidebar">
        Docs Menu
      </button>
      <nav class="breadcrumbs" aria-label="Breadcrumb">
        <a href="{_esc(url_for(base_url, "/"))}">Home</a>
        <span aria-hidden="true">/</span>
        <a href="{_esc(url_for(base_url, "/docs/"))}">Docs</a>
        <span aria-hidden="true">/</span>
        <span>{_esc(doc.section)}</span>
      </nav>

      <article>
        <header class="doc-header">
          <h1>{_esc(doc.rendered.title)}</h1>
          <div class="doc-meta-bar">
            <span>{doc.rendered.reading_minutes} min read</span>
            <span>·</span>
            <code>{_esc(doc.source_rel_path)}</code>
            <span>·</span>
            <a href="{_esc(source_github)}" target="_blank" rel="noopener noreferrer">View source on GitHub ↗</a>
          </div>
        </header>
        <div class="prose">
{doc.rendered.html_body}
        </div>
      </article>

      <nav class="doc-pagination" aria-label="Documentation pages">
        {prev_html}
        {next_html}
      </nav>
    </main>

{toc_html}
  </div>
{_render_search_modal()}
{_render_footer(base_url, len(docs))}
</body>
</html>
"""


def _render_404(base_url: str, doc_count: int) -> str:
    head = _render_head(
        title="Page Not Found — ooodnakov-config",
        description="The requested page could not be found on ooodnakov-config.",
        canonical_path="/404.html",
        base_url=base_url,
    )
    return f"""{head}
<body>
{_render_nav(base_url, active="home")}
  <main id="main-content" class="container not-found">
    <div class="not-found-code">404</div>
    <h1>Page not found</h1>
    <p class="hero-lead">This route does not exist in the generated documentation tree.</p>
    <div class="hero-cta">
      <a class="btn btn-primary" href="{_esc(url_for(base_url, "/"))}">Back Home</a>
      <a class="btn btn-secondary" href="{_esc(url_for(base_url, "/docs/"))}">Browse Docs</a>
      <button type="button" class="btn btn-secondary" data-open-search>Search (Ctrl K)</button>
    </div>
  </main>
{_render_search_modal()}
{_render_footer(base_url, doc_count)}
</body>
</html>
"""


def _build_search_index(docs: list[DocEntry], repo_data: dict[str, Any], base_url: str) -> dict[str, Any]:
    items: list[dict[str, str]] = []
    for doc in docs:
        doc_url = url_for(base_url, f"/docs/{doc.slug}/")
        items.append(
            {
                "kind": "doc",
                "title": doc.rendered.title,
                "section": doc.section,
                "snippet": doc.rendered.description,
                "body": doc.rendered.plain_text[:4000],
                "url": doc_url,
            }
        )
        for heading in doc.rendered.toc:
            items.append(
                {
                    "kind": "heading",
                    "title": heading.title,
                    "section": f"{doc.nav_label} · section",
                    "snippet": f"Jump to #{heading.id} in {doc.nav_label}",
                    "body": f"{doc.rendered.title} {heading.title}",
                    "url": f"{doc_url}#{heading.id}",
                }
            )
    cli_ref_url = url_for(base_url, "/docs/cli-reference/")
    for cmd in repo_data["cli_commands"]:
        items.append(
            {
                "kind": "command",
                "title": cmd["command"],
                "section": f"CLI · {cmd['family']}",
                "snippet": cmd["description"],
                "body": f"{cmd['command']} {cmd['description']} {' '.join(cmd['options'])}",
                "url": f"{cli_ref_url}#commands",
            }
        )
    return {"items": items}


def build_site(repo_root: Path, output_dir: Path, base_url: str = "") -> BuildSummary:
    """Build the complete static site into output_dir."""
    norm_base = normalize_base_url(base_url)
    repo_root = repo_root.resolve()
    output_dir = output_dir.resolve()

    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / ".nojekyll").write_text("", encoding="utf-8")

    assets_out = output_dir / "assets"
    assets_out.mkdir(parents=True, exist_ok=True)
    static_dir = repo_root / "site" / "static"
    for asset in static_dir.iterdir():
        if asset.is_file():
            shutil.copy2(asset, assets_out / asset.name)
    shutil.copy2(
        repo_root / "assets" / "dotfiles-banner-transparent.svg", assets_out / "dotfiles-banner-transparent.svg"
    )

    doc_slug_by_rel_path: dict[str, str] = {
        rel_path: slug for _, entries in DOC_SECTIONS for rel_path, slug, _ in entries
    }

    docs: list[DocEntry] = []
    for section_name, entries in DOC_SECTIONS:
        for rel_path, slug, nav_label in entries:
            markdown_text = (repo_root / rel_path).read_text(encoding="utf-8")
            rendered = render_markdown(
                markdown_text,
                source_rel_path=rel_path,
                doc_slug_by_rel_path=doc_slug_by_rel_path,
                base_url=norm_base,
                repo_root=repo_root,
                github_url=GITHUB_URL,
            )
            docs.append(
                DocEntry(
                    section=section_name,
                    source_rel_path=rel_path,
                    slug=slug,
                    nav_label=nav_label,
                    rendered=rendered,
                )
            )

    repo_data = collect_repo_data(repo_root)
    banner_svg = load_adaptive_banner_svg(repo_root)

    (output_dir / "index.html").write_text(_render_home(repo_data, docs, banner_svg, norm_base), encoding="utf-8")
    (output_dir / "404.html").write_text(_render_404(norm_base, len(docs)), encoding="utf-8")

    docs_dir = output_dir / "docs"
    docs_dir.mkdir(parents=True, exist_ok=True)
    (docs_dir / "index.html").write_text(_render_docs_hub(docs, norm_base), encoding="utf-8")
    for idx, doc in enumerate(docs):
        page_dir = docs_dir / doc.slug
        page_dir.mkdir(parents=True, exist_ok=True)
        (page_dir / "index.html").write_text(_render_doc_page(doc, idx, docs, norm_base), encoding="utf-8")

    data_dir = output_dir / "data"
    data_dir.mkdir(parents=True, exist_ok=True)
    (data_dir / "site-data.json").write_text(json.dumps(repo_data, indent=2), encoding="utf-8")
    (data_dir / "search-index.json").write_text(
        json.dumps(_build_search_index(docs, repo_data, norm_base), indent=2),
        encoding="utf-8",
    )

    sitemap_urls = [f"{SITE_URL}/", f"{SITE_URL}/docs/", *(f"{SITE_URL}/docs/{doc.slug}/" for doc in docs)]
    sitemap_entries = "\n".join(f"  <url><loc>{_esc(url)}</loc></url>" for url in sitemap_urls)
    (output_dir / "sitemap.xml").write_text(
        f'<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n{sitemap_entries}\n</urlset>\n',
        encoding="utf-8",
    )
    (output_dir / "robots.txt").write_text(
        f"User-agent: *\nAllow: /\n\nSitemap: {SITE_URL}/sitemap.xml\n",
        encoding="utf-8",
    )

    return BuildSummary(
        output_dir=output_dir,
        doc_count=len(docs),
        command_count=len(repo_data["cli_commands"]),
        dep_count=len(repo_data["optional_deps"]),
    )


def _serve(directory: Path, port: int) -> None:
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(directory))
    with http.server.ThreadingHTTPServer(("127.0.0.1", port), handler) as server:
        print(f"Serving {directory} at http://127.0.0.1:{port}/ (Ctrl+C to stop)")
        with contextlib.suppress(KeyboardInterrupt):
            server.serve_forever()


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint for building and optionally serving the GitHub Pages site."""
    parser = argparse.ArgumentParser(description="Build the ooodnakov-config GitHub Pages static site.")
    parser.add_argument("--output", type=Path, default=Path("_site"), help="Output directory (default: _site)")
    parser.add_argument("--base-url", default="", help="Base path prefix (e.g. /ooodnakov-config)")
    parser.add_argument("--serve", action="store_true", help="Serve the built site locally on 127.0.0.1")
    parser.add_argument("--port", type=int, default=4173, help="Local preview port (default: 4173)")
    args = parser.parse_args(argv)

    repo_root = Path(__file__).resolve().parents[2]
    output_dir = args.output if args.output.is_absolute() else (repo_root / args.output)
    summary = build_site(repo_root, output_dir, base_url=args.base_url)
    print(
        f"Built GitHub Pages site in {summary.output_dir}: "
        f"{summary.doc_count} docs, {summary.command_count} CLI commands, {summary.dep_count} optional deps."
    )
    if args.serve:
        _serve(summary.output_dir, args.port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
