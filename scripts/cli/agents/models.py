from __future__ import annotations

import importlib
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

SCRIPTS_CLI_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT_DEFAULT = Path(__file__).resolve().parents[3]
if str(SCRIPTS_CLI_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_CLI_DIR))

_tui = importlib.import_module("tui")
is_interactive = _tui.is_interactive
interactive_select = _tui.interactive_select

from cli_ui import bullet as print_bullet  # noqa: E402,F401
from cli_ui import error as print_error_line  # noqa: E402,F401
from cli_ui import path as print_path  # noqa: E402,F401
from cli_ui import section as print_section  # noqa: E402,F401
from cli_ui import spacer as print_spacer  # noqa: E402,F401
from cli_ui import status as print_status_line  # noqa: E402,F401
from cli_ui import supports_nerd_font_output  # noqa: E402,F401

MANAGED_BEGIN = "<!-- oooconf:agents-common:start -->"
MANAGED_END = "<!-- oooconf:agents-common:end -->"
AGENT_EXTRA_HEADING = "## Agent-specific instructions"
RTK_BEGIN = "<!-- oooconf:rtk:start -->"
RTK_END = "<!-- oooconf:rtk:end -->"
DEFAULT_CONFIG_PATH = Path("home/.config/ooodnakov/agents/config.json")
ENV_PLACEHOLDER_PATTERN = re.compile(r"\{([A-Za-z_][A-Za-z0-9_]*)\}")
ENV_REFERENCE_PATTERN = re.compile(
    r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)|\{([A-Za-z_][A-Za-z0-9_]*)\}"
)
_JSON_TRAILING_COMMA_PATTERN = re.compile(r",\s*([}\]])")
TOML_BARE_KEY_PATTERN = re.compile(r"^[A-Za-z0-9_-]+$")

AGENTS_EPILOG = """\
Examples:
  oooconf agents detect                 list configured agent CLIs
  oooconf agents sync                   sync global AGENTS.md and MCP configs
  oooconf agents sync --check           fail if global configs are stale
  oooconf agents sync --agents claude   sync only one agent (config + instructions)
  oooconf agents doctor                 validate agent configs
  oooconf agents mcp sync --servers context7
  oooconf agents provider sync minimax --agents codex
  oooconf agents skills view --json
"""


@dataclass(frozen=True)
class AgentCli:
    """Configured agent CLI executable definition."""

    name: str
    command: str


@dataclass(frozen=True)
class AgentConfigTarget:
    """Global config target for an AI agent."""

    name: str
    format: str
    default_paths: list[str]
    docs_url: str = ""
    mcp_paths: list[str] | None = None
    mcp_skip: bool = False
    agents: tuple[str, ...] = ()
    extra_text_file: str = ""
    extra_only: bool = False
    create_if_dir_exists: str = ""
    frontmatter: dict[str, str] | None = None


@dataclass(frozen=True)
class DoctorConfigResult:
    """Inspection result for a single agent config target."""

    target: AgentConfigTarget
    existing_path: Path | None
    missing_mcp: list[str]
    missing_skills: list[str]
    parse_error: str = ""
    shape_issues: list[str] | None = None
    mcp_file_path: Path | None = None


@dataclass(frozen=True)
class AgentUpdateSpec:
    """Install and update specification for an agent CLI."""

    name: str
    command: str
    preferred: str
    package: str
    install_script: str | None = None
    install_script_ps: str | None = None


def resolve_collab(name: str, default: Any) -> Any:
    """Resolve a collaborator via the ``agents_tool`` facade when monkeypatched."""
    for mod_name in ("agents_tool", "scripts.cli.agents_tool"):
        facade = sys.modules.get(mod_name)
        if facade is not None and name in facade.__dict__:
            return facade.__dict__[name]
    return default
