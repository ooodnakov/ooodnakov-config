import importlib.util
import json
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
if "agents_tool" in sys.modules:
    agents_tool = sys.modules["agents_tool"]
else:
    spec = importlib.util.spec_from_file_location("agents_tool", ROOT / "scripts/cli/agents_tool.py")
    assert spec is not None
    assert spec.loader is not None
    agents_tool = importlib.util.module_from_spec(spec)
    sys.modules["agents_tool"] = agents_tool
    spec.loader.exec_module(agents_tool)

if "cli_ui" in sys.modules:
    cli_ui = sys.modules["cli_ui"]
else:
    cli_ui_spec = importlib.util.spec_from_file_location("cli_ui", ROOT / "scripts/cli/cli_ui.py")
    assert cli_ui_spec is not None
    assert cli_ui_spec.loader is not None
    cli_ui = importlib.util.module_from_spec(cli_ui_spec)
    sys.modules["cli_ui"] = cli_ui
    cli_ui_spec.loader.exec_module(cli_ui)


def test_render_opencode_entry_shape_and_env_materialization(monkeypatch):
    monkeypatch.setenv("CTX_KEY", "secret-123")
    target = agents_tool.AgentConfigTarget("OpenCode", "json", [], "")
    cfg = {
        "command": "pnpm",
        "args": ["dlx", "@upstash/context7-mcp", "--api-key", "{CTX_KEY}"],
        "env_vars": ["CTX_KEY"],
    }
    entry = agents_tool.render_opencode_mcp_entry(target, "context7", cfg, Path("/tmp/repo"), materialize_secrets=True)
    assert entry["type"] == "local"
    assert entry["enabled"] is True
    assert entry["command"][0] == "pnpm"
    assert entry["environment"]["CTX_KEY"] == "secret-123"


def test_render_mcp_env_uses_placeholder_without_materialize(monkeypatch):
    monkeypatch.setenv("CTX_KEY", "secret-123")
    env = agents_tool.build_mcp_env(
        {"env_vars": ["CTX_KEY"]},
        mcp_dir=Path("/tmp/mcp"),
        repo_root=Path("/tmp/repo"),
        materialize_secrets=False,
    )
    assert env["CTX_KEY"] == "{CTX_KEY}"


def test_check_config_shape_rules():
    opencode = agents_tool.AgentConfigTarget("OpenCode", "json", [], "")
    antigravity = agents_tool.AgentConfigTarget("Antigravity", "json", [], "")
    codex = agents_tool.AgentConfigTarget("OpenAI Codex CLI", "toml", [], "")

    assert agents_tool.check_config_shape(opencode, '{"mcp": {}}') == []
    assert agents_tool.check_config_shape(antigravity, '{"mcpServers": {}}') == []
    assert agents_tool.check_config_shape(codex, "[mcp_servers.test]\ncommand='x'") == []

    assert agents_tool.check_config_shape(opencode, '{"mcpServers": {}}')
    assert agents_tool.check_config_shape(antigravity, '{"mcp": {}}')


def test_parse_and_normalize_mcp_json():
    name, cfg = agents_tool.parse_mcp_json_input(
        '{"doomscrollr":{"command":"npx","args":["-y","@doomscrollr/mcp-server"],"env":{"DOOM":"x"}}}'
    )
    assert name == "doomscrollr"
    normalized = agents_tool.normalize_mcp_command(cfg)
    assert normalized["command"] == "pnpm"
    assert normalized["args"][:2] == ["dlx", "@doomscrollr/mcp-server"]


def test_parse_mcp_json_input_heuristics_missing_outer_braces():
    name, cfg = agents_tool.parse_mcp_json_input(
        '"doomscrollr":{"command":"npx","args":["-y","@doomscrollr/mcp-server"]}'
    )
    assert name == "doomscrollr"
    assert cfg["command"] == "npx"


def test_parse_mcp_json_input_heuristics_single_quotes():
    name, cfg = agents_tool.parse_mcp_json_input(
        "'doomscrollr':{'command':'npx','args':['-y','@doomscrollr/mcp-server']}"
    )
    assert name == "doomscrollr"
    assert cfg["args"][0] == "-y"


def test_skills_add_check_mode(tmp_path):
    repo = tmp_path / "repo"
    repo.mkdir()
    common_data = repo / "common.json"
    common_data.write_text('{"mcp_servers":{},"skills":[],"skill_specs":[]}', encoding="utf-8")
    cfg = {"common_data_file": "common.json"}
    rc = agents_tool.cmd_skills_add(repo, cfg, "vercel-labs/agent-skills", check_only=True, sync_now=False)
    assert rc == 0
    data = common_data.read_text(encoding="utf-8")
    assert "vercel-labs/agent-skills" not in data


def test_skills_sync_installs_skills_cli_specs(tmp_path, monkeypatch):
    repo = tmp_path / "repo"
    repo.mkdir()
    (repo / "common.json").write_text(
        json.dumps(
            {
                "skills": [],
                "skill_specs": [
                    {
                        "installer": "skills",
                        "name": "worktrunk",
                        "source": "https://github.com/max-sixty/worktrunk",
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    monkeypatch.setenv("USERPROFILE", str(tmp_path / "home"))
    config = {
        "common_data_file": "common.json",
        "agent_clis": [
            {"name": "Claude Code", "command": "claude"},
            {"name": "OpenAI Codex CLI", "command": "codex"},
        ],
    }
    calls: list[list[str]] = []

    def fake_which(command: str) -> str | None:
        return f"/usr/bin/{command}" if command in {"claude", "codex", "pnpm"} else None

    def fake_run(command: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
        calls.append(command)
        return subprocess.CompletedProcess(command, 0)

    monkeypatch.setattr(agents_tool.shutil, "which", fake_which)
    monkeypatch.setattr(agents_tool.subprocess, "run", fake_run)

    rc = agents_tool.cmd_skills_sync(repo, config, check_only=False)

    assert rc == 0
    assert calls == [
        [
            "pnpm",
            "dlx",
            "skills",
            "add",
            "https://github.com/max-sixty/worktrunk",
            "--skill",
            "worktrunk",
            "-g",
            "-y",
            "-a",
            "claude-code",
            "-a",
            "codex",
        ]
    ]


def test_skills_view_check_mode_uses_global_ls(capsys):
    rc = agents_tool.cmd_skills_view(json_output=True, check_only=True)

    assert rc == 0
    output = capsys.readouterr().out
    assert "pnpm dlx skills ls -g --json" in output
    assert "skills view" not in output


def test_windows_launcher_prefers_pathext_variant(monkeypatch):
    # pnpm ships an extensionless POSIX shim that CreateProcess cannot launch.
    paths = {"pnpm": "C:\\pnpm\\pnpm", "pnpm.CMD": "C:\\pnpm\\pnpm.CMD"}
    monkeypatch.setattr(agents_tool.os, "name", "nt")
    monkeypatch.setenv("PATHEXT", ".COM;.EXE;.BAT;.CMD")

    assert agents_tool.windows_launcher("pnpm", paths.get) == "C:\\pnpm\\pnpm.CMD"


def test_windows_launcher_keeps_name_without_executable_variant(monkeypatch):
    monkeypatch.setattr(agents_tool.os, "name", "nt")
    monkeypatch.setenv("PATHEXT", ".COM;.EXE;.BAT;.CMD")

    which = lambda command: "C:\\pnpm\\pnpm" if command == "pnpm" else None  # noqa: E731
    assert agents_tool.windows_launcher("pnpm", which) == "pnpm"


def test_windows_launcher_is_identity_off_windows(monkeypatch):
    monkeypatch.setattr(agents_tool.os, "name", "posix")

    assert agents_tool.windows_launcher("pnpm", lambda _command: "/usr/bin/pnpm") == "pnpm"


def test_parse_mcp_json_inputs_multi():
    payload = '{"one":{"command":"pnpm","args":["dlx","a"]},"two":{"command":"pnpm","args":["dlx","b"]}}'
    result = agents_tool.parse_mcp_json_inputs(payload, allow_multi=True)
    assert set(result.keys()) == {"one", "two"}


def test_parse_and_validate_url_mcp_entry():
    name, cfg = agents_tool.parse_mcp_json_input('{"dynadot":{"type":"http","url":"https://mcp.dynadot.com/mcp"}}')
    assert name == "dynadot"
    agents_tool.validate_mcp_entry(name, cfg)

    with pytest.raises(ValueError, match=r"http\(s\) URL"):
        agents_tool.validate_mcp_entry("bad", {"url": "ftp://example.com"})
    with pytest.raises(ValueError, match="cannot combine"):
        agents_tool.validate_mcp_entry("bad", {"url": "https://example.com", "command": "x"})


def test_render_remote_mcp_entries_use_native_shapes(monkeypatch):
    monkeypatch.setenv("CTX_KEY", "secret-123")
    cfg = {
        "type": "http",
        "url": "https://mcp.context7.com/mcp",
        "headers": {"Authorization": "Bearer {CTX_KEY}"},
    }
    repo = Path("/tmp/repo")

    claude = agents_tool.render_mcp_server_entry(
        agents_tool.AgentConfigTarget("Claude Code", "json", [], ""),
        "context7",
        cfg,
        repo,
        materialize_secrets=True,
    )
    assert claude == {
        "type": "http",
        "url": "https://mcp.context7.com/mcp",
        "headers": {"Authorization": "Bearer secret-123"},
    }

    verbatim = agents_tool.render_mcp_server_entry(
        agents_tool.AgentConfigTarget("Claude Code", "json", [], ""), "context7", cfg, repo
    )
    assert verbatim["headers"]["Authorization"] == "Bearer {CTX_KEY}"

    antigravity = agents_tool.render_mcp_server_entry(
        agents_tool.AgentConfigTarget("Antigravity", "json", [], ""), "context7", cfg, repo
    )
    assert antigravity["serverUrl"] == "https://mcp.context7.com/mcp"
    assert "url" not in antigravity

    pi = agents_tool.render_mcp_server_entry(
        agents_tool.AgentConfigTarget("Pi Agent", "json", [], ""), "context7", cfg, repo
    )
    assert pi == {"url": "https://mcp.context7.com/mcp", "headers": {"Authorization": "Bearer ${CTX_KEY}"}}

    opencode = agents_tool.render_opencode_mcp_entry(
        agents_tool.AgentConfigTarget("OpenCode", "json", [], ""),
        "dynadot",
        {"type": "http", "url": "https://mcp.dynadot.com/mcp"},
        repo,
    )
    assert opencode == {"type": "remote", "url": "https://mcp.dynadot.com/mcp", "enabled": True}


def test_render_remote_mcp_pi_keeps_runtime_interpolation(monkeypatch):
    monkeypatch.delenv("CTX_KEY", raising=False)
    pi = agents_tool.render_mcp_server_entry(
        agents_tool.AgentConfigTarget("Pi Agent", "json", [], ""),
        "context7",
        {
            "type": "http",
            "url": "https://mcp.context7.com/mcp",
            "headers": {"Authorization": "Bearer {CTX_KEY}"},
        },
        Path("/tmp/repo"),
    )
    assert pi["headers"]["Authorization"] == "Bearer ${CTX_KEY}"


def test_sync_global_configs_writes_remote_mcp_entries(tmp_path, monkeypatch):
    home = tmp_path / "home"
    (home / ".codex").mkdir(parents=True)
    codex_path = home / ".codex/config.toml"
    codex_path.write_text('[projects."/x"]\ntrust_level = "trusted"\n', encoding="utf-8")
    (home / ".claude").mkdir()
    claude_path = home / ".claude/settings.json"
    claude_path.write_text('{"mcpServers": {}}', encoding="utf-8")
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("USERPROFILE", str(home))

    config = {
        "agent_configs": [
            {"name": "OpenAI Codex CLI", "format": "toml", "default_paths": ["~/.codex/config.toml"]},
            {"name": "Claude Code", "format": "json", "default_paths": ["~/.claude/settings.json"]},
        ]
    }
    targets = agents_tool.parse_agent_targets(config["agent_configs"])
    common_data = {
        "mcp_servers": {
            "context7": {
                "type": "http",
                "url": "https://mcp.context7.com/mcp",
                "headers": {"Authorization": "Bearer {CTX_KEY}"},
            },
            "dynadot": {"type": "http", "url": "https://mcp.dynadot.com/mcp"},
        },
        "skills": [],
    }

    changed, _ = agents_tool.sync_global_configs(tmp_path, targets, common_data, "", check_only=False)
    assert changed

    codex = codex_path.read_text(encoding="utf-8")
    parsed = tomllib.loads(codex)
    context7 = parsed["mcp_servers"]["context7"]
    assert context7["type"] == "http"
    assert context7["url"] == "https://mcp.context7.com/mcp"
    assert context7["http_headers"]["Authorization"] == "Bearer {CTX_KEY}"
    assert parsed["mcp_servers"]["dynadot"]["url"] == "https://mcp.dynadot.com/mcp"
    assert "command" not in context7

    claude = json.loads(claude_path.read_text(encoding="utf-8"))
    assert claude["mcpServers"]["context7"]["type"] == "http"
    assert claude["mcpServers"]["context7"]["url"] == "https://mcp.context7.com/mcp"
    assert claude["mcpServers"]["dynadot"]["url"] == "https://mcp.dynadot.com/mcp"


def test_canonicalize_skill_source():
    assert (
        agents_tool.canonicalize_skill_source("https://github.com/vercel-labs/agent-skills/")
        == "https://github.com/vercel-labs/agent-skills"
    )
    assert (
        agents_tool.canonicalize_skill_source("vercel-labs/agent-skills")
        == "https://github.com/vercel-labs/agent-skills"
    )


def test_cmd_mcp_add_rejects_name_with_multi(tmp_path):
    repo = tmp_path / "repo"
    repo.mkdir()
    common_data = repo / "common.json"
    common_data.write_text('{"mcp_servers":{}}', encoding="utf-8")
    cfg = {"common_data_file": "common.json"}
    rc = agents_tool.cmd_mcp_add(
        repo,
        cfg,
        name="x",
        json_payload='{"a":{"command":"pnpm","args":["dlx","a"]}}',
        check_only=False,
        sync_now=False,
        allow_multi=True,
        preview=False,
    )
    assert rc == 1


def test_cmd_mcp_add_multi_writes_entries(tmp_path, monkeypatch):
    monkeypatch.setattr(agents_tool, "prompt_yes_no", lambda _q: False)
    repo = tmp_path / "repo"
    repo.mkdir()
    common_data = repo / "common.json"
    common_data.write_text('{"mcp_servers":{}}', encoding="utf-8")
    cfg = {"common_data_file": "common.json"}
    rc = agents_tool.cmd_mcp_add(
        repo,
        cfg,
        name=None,
        json_payload='{"a":{"command":"npx","args":["-y","pkg-a"]},"b":{"command":"pnpm","args":["dlx","pkg-b"]}}',
        check_only=False,
        sync_now=False,
        allow_multi=True,
        preview=False,
    )
    assert rc == 0
    data = json.loads(common_data.read_text(encoding="utf-8"))
    assert set(data["mcp_servers"].keys()) == {"a", "b"}
    assert data["mcp_servers"]["a"]["command"] == "pnpm"
    assert data["mcp_servers"]["a"]["args"][0] == "dlx"


def test_provider_sync_minimax_writes_supported_configs(tmp_path, monkeypatch):
    home = tmp_path / "home"
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("USERPROFILE", str(home))
    cfg = {
        "agent_configs": [
            {"name": "Claude Code", "format": "json", "default_paths": ["~/.claude/settings.json"]},
            {"name": "OpenCode", "format": "json", "default_paths": ["~/.config/opencode/opencode.json"]},
            {"name": "OpenAI Codex CLI", "format": "toml", "default_paths": ["~/.codex/config.toml"]},
        ]
    }

    rc = agents_tool.cmd_provider_sync(cfg, "minimax", check_only=False, materialize_secrets=False, region="global")

    assert rc == 0
    claude = json.loads((home / ".claude/settings.json").read_text(encoding="utf-8"))
    assert claude["env"]["ANTHROPIC_BASE_URL"] == "https://api.minimax.io/anthropic"
    assert "ANTHROPIC_AUTH_TOKEN" not in claude["env"]

    opencode = json.loads((home / ".config/opencode/opencode.json").read_text(encoding="utf-8"))
    assert opencode["model"] == "minimax/MiniMax-M2.7"
    assert opencode["provider"]["minimax"]["options"]["baseURL"] == "https://api.minimax.io/anthropic/v1"
    assert "apiKey" not in opencode["provider"]["minimax"]["options"]

    codex = (home / ".codex/config.toml").read_text(encoding="utf-8")
    assert "[model_providers.minimax]" in codex
    assert 'env_key = "MINIMAX_API_KEY"' in codex
    assert "[profiles.minimax]" in codex


def test_provider_sync_minimax_handles_empty_json_and_updates_existing_codex(tmp_path, monkeypatch):
    home = tmp_path / "home"
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("USERPROFILE", str(home))
    claude_path = home / ".claude/settings.json"
    opencode_path = home / ".config/opencode/opencode.json"
    codex_path = home / ".config/codex/config.toml"
    claude_path.parent.mkdir(parents=True)
    opencode_path.parent.mkdir(parents=True)
    codex_path.parent.mkdir(parents=True)
    claude_path.write_text("", encoding="utf-8")
    opencode_path.write_text("{}", encoding="utf-8")
    codex_path.write_text(
        "  [ model_providers.minimax ]\n"
        'name = "MiniMax Chat Completions API"\n'
        'base_url = "https://api.minimax.io/v1"\n'
        'env_key = "MINIMAX_API_KEY"\n'
        'env_key_instructions = "Export MINIMAX_API_KEY before starting Codex."\n'
        'wire_api = "chat"\n'
        "requires_openai_auth = false\n"
        "request_max_retries = 4\n"
        "stream_max_retries = 10\n"
        "stream_idle_timeout_ms = 300000\n\n"
        "[profiles.minimax]\n"
        'model = "codex-MiniMax-M2.7"\n'
        'model_provider = "minimax"\n',
        encoding="utf-8",
    )
    cfg = {
        "agent_configs": [
            {"name": "Claude Code", "format": "json", "default_paths": ["~/.claude/settings.json"]},
            {"name": "OpenCode", "format": "json", "default_paths": ["~/.config/opencode/opencode.json"]},
            {
                "name": "OpenAI Codex CLI",
                "format": "toml",
                "default_paths": ["~/.codex/config.toml", "~/.config/codex/config.toml"],
            },
        ]
    }

    rc = agents_tool.cmd_provider_sync(cfg, "minimax", check_only=False, materialize_secrets=False, region="china")

    assert rc == 0
    claude = json.loads(claude_path.read_text(encoding="utf-8"))
    assert claude["env"]["ANTHROPIC_BASE_URL"] == "https://api.minimaxi.com/anthropic"
    codex = codex_path.read_text(encoding="utf-8")
    assert codex.count("model_providers.minimax") == 1
    assert 'base_url = "https://api.minimaxi.com/v1"' in codex
    assert not (home / ".codex/config.toml").exists()


def test_select_install_specs_defaults_to_missing(monkeypatch):
    specs = [
        agents_tool.AgentUpdateSpec("OpenAI Codex CLI", "codex", "npm", "@openai/codex"),
        agents_tool.AgentUpdateSpec("Qwen Code", "qwen", "npm", "@qwen-code/qwen-code"),
    ]
    monkeypatch.setattr(agents_tool.shutil, "which", lambda cmd: "/bin/codex" if cmd == "codex" else None)

    selected, errors = agents_tool.select_install_specs(specs, [], install_all=False, missing_only=False)

    assert errors == []
    assert [spec.command for spec in selected] == ["qwen"]


def test_select_install_specs_supports_multiple_explicit_agents():
    specs = [
        agents_tool.AgentUpdateSpec("OpenAI Codex CLI", "codex", "npm", "@openai/codex"),
        agents_tool.AgentUpdateSpec("Qwen Code", "qwen", "npm", "@qwen-code/qwen-code"),
    ]

    selected, errors = agents_tool.select_install_specs(
        specs, ["codex", "Qwen Code"], install_all=False, missing_only=False
    )

    assert errors == []
    assert [spec.command for spec in selected] == ["codex", "qwen"]


def test_cmd_install_check_mode_can_plan_selected_agents(tmp_path, capsys):
    cfg = {
        "agent_updates": [
            {"name": "OpenAI Codex CLI", "command": "codex", "preferred": "npm", "package": "@openai/codex"},
            {"name": "Qwen Code", "command": "qwen", "preferred": "npm", "package": "@qwen-code/qwen-code"},
        ]
    }

    rc = agents_tool.cmd_install(
        tmp_path,
        cfg,
        ["codex", "qwen"],
        check_only=True,
        install_all=False,
        missing_only=False,
    )

    out = capsys.readouterr().out
    assert rc == 0
    assert "Plan: install OpenAI Codex CLI via pnpm" in out
    assert "Plan: install Qwen Code via pnpm" in out


def test_supports_nerd_font_output(monkeypatch):
    class MockStdout:
        def __init__(self, tty=True, encoding="utf-8"):
            self._tty = tty
            self.encoding = encoding

        def isatty(self):
            return self._tty

    # Test OOOCONF_ASCII=1
    monkeypatch.setenv("OOOCONF_ASCII", "1")
    assert agents_tool.supports_nerd_font_output() is False
    monkeypatch.delenv("OOOCONF_ASCII")

    # Test not a TTY
    monkeypatch.setattr(sys, "stdout", MockStdout(tty=False))
    assert agents_tool.supports_nerd_font_output() is False

    # Test is a TTY but not UTF
    monkeypatch.setattr(sys, "stdout", MockStdout(tty=True, encoding="ascii"))
    assert agents_tool.supports_nerd_font_output() is False

    # Test is a TTY and UTF
    monkeypatch.setattr(sys, "stdout", MockStdout(tty=True, encoding="utf-8"))
    assert agents_tool.supports_nerd_font_output() is True


def test_supports_color_output(monkeypatch):
    class MockStdout:
        def __init__(self, tty=True):
            self._tty = tty

        def isatty(self):
            return self._tty

    # Test OOOCONF_COLOR=0/false/never
    for val in ["0", "false", "never"]:
        monkeypatch.setenv("OOOCONF_COLOR", val)
        assert cli_ui.supports_color_output() is False

    # Test NO_COLOR
    monkeypatch.delenv("OOOCONF_COLOR", raising=False)
    monkeypatch.setenv("NO_COLOR", "1")
    assert cli_ui.supports_color_output() is False
    monkeypatch.delenv("NO_COLOR")

    # Test OOOCONF_COLOR=1/true/always
    for val in ["1", "true", "always"]:
        monkeypatch.setenv("OOOCONF_COLOR", val)
        assert cli_ui.supports_color_output() is True

    # Test FORCE_COLOR
    monkeypatch.delenv("OOOCONF_COLOR", raising=False)
    monkeypatch.setenv("FORCE_COLOR", "1")
    assert cli_ui.supports_color_output() is True
    monkeypatch.delenv("FORCE_COLOR")

    # Test TTY fallback
    monkeypatch.setattr(sys, "stdout", MockStdout(tty=True))
    assert cli_ui.supports_color_output() is True
    monkeypatch.setattr(sys, "stdout", MockStdout(tty=False))
    assert cli_ui.supports_color_output() is False


def test_run_install_spec_post_install_safe_execution(monkeypatch, capsys):
    from agents_tool import AgentUpdateSpec, run_install_spec

    monkeypatch.setattr(shutil, "which", lambda x: f"/mock/bin/{x}" if x in ("npm", "pnpm", "uv") else None)

    executed_commands = []

    def mock_run(args, **kwargs):
        executed_commands.append(args)

        class MockSubprocessResult:
            stdout = ""

        return MockSubprocessResult()

    monkeypatch.setattr(subprocess, "run", mock_run)

    spec = AgentUpdateSpec(
        name="Test Agent",
        command="testcmd",
        preferred="npm",
        package="test-pkg",
        install_script="node mock_install.cjs; rm -rf /",
    )

    result = run_install_spec(spec, check_only=False)

    assert result == (True, True)
    assert executed_commands[0] == ["/mock/bin/pnpm", "add", "-g", "test-pkg@latest"]
    assert executed_commands[1] == ["node", "mock_install.cjs;", "rm", "-rf", "/"]


def test_run_install_spec_post_install_catches_shlex_value_error(monkeypatch, capsys):
    from agents_tool import AgentUpdateSpec, run_install_spec

    monkeypatch.setattr(shutil, "which", lambda x: f"/mock/bin/{x}" if x in ("npm", "pnpm", "uv") else None)

    def mock_run(args, **kwargs):
        class MockSubprocessResult:
            stdout = ""

        return MockSubprocessResult()

    monkeypatch.setattr(subprocess, "run", mock_run)

    spec = AgentUpdateSpec(
        name="Test Agent",
        command="testcmd",
        preferred="npm",
        package="test-pkg",
        install_script='node "unclosed quote',
    )

    result = run_install_spec(spec, check_only=False)
    assert result == (False, False)


class _FakeWindow:
    def __init__(self, keys):
        self._keys = list(keys)
        self.keypad_calls: list[bool] = []
        self.timeout_calls: list[int] = []

    def keypad(self, enabled):
        self.keypad_calls.append(enabled)

    def timeout(self, delay):
        self.timeout_calls.append(delay)

    def getch(self):
        return self._keys.pop(0) if self._keys else -1

    def clear(self):
        pass

    def border(self):
        pass

    def addstr(self, *args, **kwargs):
        pass

    def refresh(self):
        pass


def _fake_curses(window):
    curses = pytest.importorskip("curses", reason="curses is unavailable on this platform")
    real_curses = curses

    class _Stub:
        error = real_curses.error
        LINES = 24
        COLS = 80
        A_REVERSE = real_curses.A_REVERSE
        A_NORMAL = real_curses.A_NORMAL
        A_DIM = real_curses.A_DIM
        KEY_UP = real_curses.KEY_UP
        KEY_DOWN = real_curses.KEY_DOWN
        KEY_LEFT = real_curses.KEY_LEFT
        KEY_RIGHT = real_curses.KEY_RIGHT

        @staticmethod
        def initscr():
            return _FakeWindow([])

        @staticmethod
        def newwin(*args):
            return window

        @staticmethod
        def noecho():
            pass

        @staticmethod
        def echo():
            pass

        @staticmethod
        def cbreak():
            pass

        @staticmethod
        def nocbreak():
            pass

        @staticmethod
        def start_color():
            pass

        @staticmethod
        def endwin():
            pass

    return _Stub


def test_tui_read_key_decodes_csi_and_ss3_arrows():
    curses = pytest.importorskip("curses", reason="curses is unavailable on this platform")
    tui = agents_tool._tui

    assert tui._read_key(_FakeWindow([27, ord("["), ord("A")])) == curses.KEY_UP
    assert tui._read_key(_FakeWindow([27, ord("["), ord("B")])) == curses.KEY_DOWN
    assert tui._read_key(_FakeWindow([27, ord("O"), ord("C")])) == curses.KEY_RIGHT
    assert tui._read_key(_FakeWindow([27, ord("O"), ord("D")])) == curses.KEY_LEFT
    # A bare ESC (no sequence tail within the timeout) still cancels.
    assert tui._read_key(_FakeWindow([27, -1])) == 27
    assert tui._read_key(_FakeWindow([ord("a")])) == ord("a")


def test_tui_select_enables_window_keypad_and_navigates_with_arrows(monkeypatch):
    curses = pytest.importorskip("curses", reason="curses is unavailable on this platform")
    tui = agents_tool._tui
    window = _FakeWindow([curses.KEY_DOWN, ord(" "), ord("\n")])
    monkeypatch.setattr(tui, "_CURSES_AVAILABLE", True)
    monkeypatch.setattr(tui, "curses", _fake_curses(window))

    assert tui._curses_select(["Claude Code", "Qwen Code", "OpenCode"], "Select agents", "hint") == ["Qwen Code"]
    assert window.keypad_calls == [True]
    assert 100 in window.timeout_calls


def test_tui_select_cancels_on_escape(monkeypatch):
    pytest.importorskip("curses", reason="curses is unavailable on this platform")
    tui = agents_tool._tui
    window = _FakeWindow([27, -1])
    monkeypatch.setattr(tui, "_CURSES_AVAILABLE", True)
    monkeypatch.setattr(tui, "curses", _fake_curses(window))

    assert tui._curses_select(["Claude Code"], "Select agents", "hint") is None


def test_agent_target_aliases_accept_command_keys():
    specs = [
        agents_tool.AgentUpdateSpec("Claude Code", "claude", "npm", "@anthropic-ai/claude-code"),
        agents_tool.AgentUpdateSpec("OpenAI Codex CLI", "codex", "npm", "@openai/codex"),
        agents_tool.AgentUpdateSpec("Oh My Pi", "omp", "npm", "@oh-my-pi/pi-coding-agent"),
    ]
    targets = [
        agents_tool.AgentConfigTarget("Claude Code", "json", [], agents=("claude",)),
        agents_tool.AgentConfigTarget("Claude Global Instructions", "markdown", [], agents=("claude",)),
        agents_tool.AgentConfigTarget("OpenAI Codex CLI", "toml", [], agents=("codex",)),
        agents_tool.AgentConfigTarget("Codex Global Instructions", "markdown", [], agents=("codex",)),
        agents_tool.AgentConfigTarget("Oh My Pi", "yaml", [], agents=("omp",)),
    ]

    selected, unmatched = agents_tool.select_agent_targets(targets, specs, ["claude", "codex"])

    assert unmatched == []
    assert [target.name for target in selected] == [
        "Claude Code",
        "Claude Global Instructions",
        "OpenAI Codex CLI",
        "Codex Global Instructions",
    ]


def test_resolve_repo_root_defaults_to_repository_root(monkeypatch):
    monkeypatch.delenv("OOODNAKOV_REPO_ROOT", raising=False)
    assert agents_tool.resolve_repo_root(None) == ROOT


def test_parse_mcp_json_input_accepts_trailing_comma():
    for payload in (
        '{"demo":{"command":"npx","args":["-y","pkg"],},}',
        '"demo":{"command":"npx","args":["-y","pkg"],},',
    ):
        name, cfg = agents_tool.parse_mcp_json_input(payload)
        assert name == "demo"
        assert cfg["command"] == "npx"


def test_render_mcp_entry_keeps_env_placeholders_without_materialize(monkeypatch):
    monkeypatch.setenv("CTX_KEY", "secret-123")
    target = agents_tool.AgentConfigTarget("Claude Code", "json", [], agents=("claude",))
    cfg = {
        "command": "pnpm",
        "args": ["dlx", "@upstash/context7-mcp", "--api-key", "{CTX_KEY}"],
        "env_vars": ["CTX_KEY"],
    }

    plain = agents_tool.render_mcp_server_entry(target, "context7", cfg, Path("/tmp/repo"), materialize_secrets=False)
    materialized = agents_tool.render_mcp_server_entry(
        target, "context7", cfg, Path("/tmp/repo"), materialize_secrets=True
    )

    assert plain["args"][-1] == "{CTX_KEY}"
    assert plain["env"]["CTX_KEY"] == "{CTX_KEY}"
    assert materialized["args"][-1] == "secret-123"
    assert materialized["env"]["CTX_KEY"] == "secret-123"


def test_provider_sync_dry_run_does_not_write_and_accepts_agent_keys(tmp_path, monkeypatch):
    home = tmp_path / "home"
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("USERPROFILE", str(home))
    cfg = {
        "agent_configs": [
            {
                "name": "Claude Code",
                "agents": ["claude"],
                "format": "json",
                "default_paths": ["~/.claude/settings.json"],
            },
            {
                "name": "OpenAI Codex CLI",
                "agents": ["codex"],
                "format": "toml",
                "default_paths": ["~/.codex/config.toml"],
            },
            {
                "name": "OpenCode",
                "agents": ["opencode"],
                "format": "json",
                "default_paths": ["~/.config/opencode/opencode.json"],
            },
        ]
    }

    rc = agents_tool.cmd_provider_sync(
        cfg,
        "minimax",
        check_only=False,
        materialize_secrets=False,
        region="global",
        agents=["claude", "codex"],
        dry_run=True,
    )

    assert rc == 0
    assert not (home / ".claude/settings.json").exists()
    assert not (home / ".codex/config.toml").exists()
    assert not (home / ".config/opencode/opencode.json").exists()


def test_install_dry_run_never_executes_installers(tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr(
        agents_tool,
        "run_install_spec",
        lambda spec, check_only: calls.append((spec.command, check_only)) or (True, False),
    )
    cfg = {
        "agent_updates": [
            {"name": "OpenAI Codex CLI", "command": "codex", "preferred": "npm", "package": "@openai/codex"}
        ]
    }

    rc = agents_tool.cmd_install(
        tmp_path,
        cfg,
        ["codex"],
        check_only=False,
        install_all=False,
        missing_only=False,
        dry_run=True,
    )

    assert rc == 0
    assert calls == [("codex", True)]


def test_update_dry_run_does_not_rebuild_install_scripts(tmp_path, monkeypatch):
    rebuilt = []
    monkeypatch.setattr(
        agents_tool,
        "cmd_install_scripts_build",
        lambda *args: rebuilt.append(True) or 0,
    )
    monkeypatch.setattr(agents_tool.shutil, "which", lambda _command: None)
    cfg = {
        "agent_updates": [
            {"name": "OpenAI Codex CLI", "command": "codex", "preferred": "npm", "package": "@openai/codex"}
        ]
    }

    rc = agents_tool.cmd_update(tmp_path, cfg, check_only=False, dry_run=True)

    assert rc == 0
    assert rebuilt == []


def test_sync_check_defaults_to_global_targets(tmp_path, monkeypatch):
    home = tmp_path / "home"
    (home / ".claude").mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("USERPROFILE", str(home))
    repo = tmp_path / "repo"
    repo.mkdir()
    (repo / "common.md").write_text("# Policy\n", encoding="utf-8")
    (repo / "common.json").write_text('{"mcp_servers":{},"skills":[]}', encoding="utf-8")
    cfg = {
        "common_text_file": "common.md",
        "common_data_file": "common.json",
        "agent_configs": [
            {
                "name": "Claude Global Instructions",
                "agents": ["claude"],
                "format": "markdown",
                "default_paths": ["~/.claude/CLAUDE.md"],
            }
        ],
    }

    assert agents_tool.cmd_sync(repo, cfg, check_only=True, agents=["claude"]) == 1
    assert agents_tool.cmd_sync(repo, cfg, check_only=False, agents=["claude"]) == 0
    assert agents_tool.cmd_sync(repo, cfg, check_only=True, agents=["claude"]) == 0
    assert "oooconf shared agent policy" in (home / ".claude/CLAUDE.md").read_text(encoding="utf-8")


def test_render_markdown_block_inserts_agent_extra_before_end_marker():
    common_data = {"mcp_servers": {}, "skills": []}

    block = agents_tool.render_markdown_block("# Policy\n", common_data, extra_text="Use tabs.\n\nBe brief.")

    assert f"\n\n{agents_tool.AGENT_EXTRA_HEADING}\n\nUse tabs.\n\nBe brief.\n\n{agents_tool.MANAGED_END}\n" in block
    assert block.index("Use tabs.") < block.index(agents_tool.MANAGED_END)
    assert block.rstrip().endswith(agents_tool.MANAGED_END)

    plain = agents_tool.render_markdown_block("# Policy\n", common_data)
    assert agents_tool.AGENT_EXTRA_HEADING not in plain
    assert agents_tool.render_markdown_block("# Policy\n", common_data, extra_text="   \n") == plain


def test_sync_global_configs_applies_extras_per_target(tmp_path, monkeypatch):
    home = tmp_path / "home"
    (home / ".claude").mkdir(parents=True)
    (home / ".gemini").mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("USERPROFILE", str(home))

    targets = [
        agents_tool.AgentConfigTarget("Claude Global", "markdown", ["~/.claude/CLAUDE.md"]),
        agents_tool.AgentConfigTarget("Antigravity Global", "markdown", ["~/.gemini/AGENTS.md"]),
    ]
    common_data = {"mcp_servers": {}, "skills": []}
    block = agents_tool.render_markdown_block("# Policy\n", common_data)
    extras = {"Claude Global": "Claude only.\n"}

    count, changed = agents_tool.sync_global_configs(tmp_path, targets, common_data, block, False, extras=extras)

    assert count == 2
    assert set(changed) == {home / ".claude/CLAUDE.md", home / ".gemini/AGENTS.md"}
    claude_text = (home / ".claude/CLAUDE.md").read_text(encoding="utf-8")
    antigravity_text = (home / ".gemini/AGENTS.md").read_text(encoding="utf-8")
    assert agents_tool.AGENT_EXTRA_HEADING in claude_text
    assert "Claude only." in claude_text
    assert agents_tool.AGENT_EXTRA_HEADING not in antigravity_text
    assert antigravity_text == block

    count, changed = agents_tool.sync_global_configs(tmp_path, targets, common_data, block, False, extras=extras)
    assert count == 0
    assert changed == []


def _extra_text_config(repo: Path, extra_text_file: str) -> dict:
    return {
        "common_text_file": "common.md",
        "common_data_file": "common.json",
        "agent_configs": [
            {
                "name": "Claude Global Instructions",
                "agents": ["claude"],
                "format": "markdown",
                "default_paths": ["~/.claude/CLAUDE.md"],
                "extra_text_file": extra_text_file,
            }
        ],
    }


def test_cmd_sync_writes_extra_text_file_and_reports_missing(tmp_path, monkeypatch, capsys):
    home = tmp_path / "home"
    (home / ".claude").mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("USERPROFILE", str(home))
    repo = tmp_path / "repo"
    repo.mkdir()
    (repo / "common.md").write_text("# Policy\n", encoding="utf-8")
    (repo / "common.json").write_text('{"mcp_servers":{},"skills":[]}', encoding="utf-8")
    (repo / "claude-extra.md").write_text("Use CLAUDE.md specific rules.\n", encoding="utf-8")
    cfg = _extra_text_config(repo, "claude-extra.md")
    target_file = home / ".claude/CLAUDE.md"

    assert agents_tool.cmd_sync(repo, cfg, check_only=False) == 0
    text = target_file.read_text(encoding="utf-8")
    assert agents_tool.AGENT_EXTRA_HEADING in text
    assert "Use CLAUDE.md specific rules." in text
    assert agents_tool.cmd_sync(repo, cfg, check_only=True) == 0

    target_file.unlink()
    (repo / "claude-extra.md").unlink()
    capsys.readouterr()

    assert agents_tool.cmd_sync(repo, cfg, check_only=False) == 0

    assert "failed to read extra text for Claude Global Instructions" in capsys.readouterr().err
    text = target_file.read_text(encoding="utf-8")
    assert "oooconf shared agent policy" in text
    assert agents_tool.AGENT_EXTRA_HEADING not in text


def test_check_config_shape_requires_extra_section_for_markdown():
    target = agents_tool.AgentConfigTarget("Claude Global", "markdown", [], extra_text_file="claude-extra.md")

    assert agents_tool.check_config_shape(target, "# Policy\n") == ["missing agent-specific instructions section"]
    content = f"# Policy\n\n{agents_tool.AGENT_EXTRA_HEADING}\n\nUse tabs.\n"
    assert agents_tool.check_config_shape(target, content) == []


def test_render_mcp_server_entry_antigravity_remote_and_stdio(monkeypatch):
    monkeypatch.setenv("CTX_KEY", "secret-123")
    target = agents_tool.AgentConfigTarget("Antigravity", "json", [], "")
    remote = agents_tool.render_mcp_server_entry(
        target,
        "context7",
        {
            "type": "http",
            "url": "https://mcp.context7.com/mcp",
            "headers": {"Authorization": "Bearer {CTX_KEY}"},
        },
        Path("/tmp/repo"),
        materialize_secrets=True,
    )
    assert remote == {
        "serverUrl": "https://mcp.context7.com/mcp",
        "headers": {"Authorization": "Bearer secret-123"},
    }
    assert "type" not in remote
    assert "httpUrl" not in remote

    stdio = agents_tool.render_mcp_server_entry(
        target,
        "example-stdio",
        {"command": "pnpm", "args": ["dlx", "example-mcp"]},
        Path("/tmp/repo"),
    )
    assert stdio == {"command": "pnpm", "args": ["dlx", "example-mcp"]}


def test_sync_global_configs_antigravity_mcp_preserves_existing(tmp_path, monkeypatch):
    home = tmp_path / "home"
    cfg_dir = home / ".gemini/config"
    cfg_dir.mkdir(parents=True)
    (cfg_dir / "config.json").write_text('{"plugins": {}}', encoding="utf-8")
    mcp_path = cfg_dir / "mcp_config.json"
    mcp_path.write_text(
        json.dumps({"mcpServers": {"blender": {"command": "uvx", "args": ["mcp-for-blender"]}}}),
        encoding="utf-8",
    )
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("USERPROFILE", str(home))

    targets = agents_tool.parse_agent_targets(
        [
            {
                "name": "Antigravity",
                "agents": ["antigravity", "agy"],
                "format": "json",
                "default_paths": [
                    "~/.gemini/config/config.json",
                    "~/.gemini/antigravity-cli/settings.json",
                    "~/.gemini/config/mcp_config.json",
                ],
                "mcp_paths": ["~/.gemini/config/mcp_config.json"],
            }
        ]
    )
    common_data = {
        "mcp_servers": {
            "context7": {
                "type": "http",
                "url": "https://mcp.context7.com/mcp",
                "headers": {"Authorization": "Bearer {CTX_KEY}"},
            },
            "blender": {"command": "other", "args": []},
        },
        "skills": [],
    }

    count, changed = agents_tool.sync_global_configs(tmp_path, targets, common_data, "", check_only=False)
    assert count == 1
    assert changed == [mcp_path]

    data = json.loads(mcp_path.read_text(encoding="utf-8"))
    assert data["mcpServers"]["blender"] == {"command": "uvx", "args": ["mcp-for-blender"]}
    assert data["mcpServers"]["context7"] == {
        "serverUrl": "https://mcp.context7.com/mcp",
        "headers": {"Authorization": "Bearer {CTX_KEY}"},
    }

    # Idempotent on re-run
    assert agents_tool.sync_global_configs(tmp_path, targets, common_data, "", check_only=False) == (0, [])


def test_sync_global_configs_extra_only_with_frontmatter_and_anchor(tmp_path, monkeypatch):
    home = tmp_path / "home"
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("USERPROFILE", str(home))

    repo = tmp_path / "repo"
    repo.mkdir()
    (repo / "common.md").write_text("# Shared Policy\n", encoding="utf-8")
    (repo / "common.json").write_text(
        '{"mcp_servers":{"context7":{"type":"http","url":"https://x"}},"skills":["worktrunk"]}', encoding="utf-8"
    )
    (repo / "agy-extra.md").write_text("### Antigravity (agy)\n\n- Search narrowly.\n", encoding="utf-8")

    target_spec = {
        "name": "Antigravity Global Instructions",
        "agents": ["antigravity", "agy"],
        "format": "markdown",
        "default_paths": ["~/.gemini/config/rules/antigravity.md"],
        "extra_text_file": "agy-extra.md",
        "extra_only": True,
        "create_if_dir_exists": "~/.gemini/config",
        "frontmatter": {
            "trigger": "always_on",
            "description": "Antigravity extra guidelines.",
        },
    }
    cfg = {
        "common_text_file": "common.md",
        "common_data_file": "common.json",
        "agent_configs": [target_spec],
        "agent_clis": [],
    }
    rule_path = home / ".gemini/config/rules/antigravity.md"

    # Skips creation when anchor directory (~/.gemini/config) does not exist
    assert agents_tool.cmd_sync(repo, cfg, check_only=False) == 0
    assert not rule_path.exists()

    # Creates rule file when anchor dir exists even if rules/ subdir does not yet exist
    (home / ".gemini/config").mkdir(parents=True)
    assert agents_tool.cmd_sync(repo, cfg, check_only=True) == 1
    assert agents_tool.cmd_sync(repo, cfg, check_only=False) == 0
    assert rule_path.exists()

    text = rule_path.read_text(encoding="utf-8")
    assert text.startswith('---\ntrigger: always_on\ndescription: "Antigravity extra guidelines."\n---\n')
    assert agents_tool.AGENT_EXTRA_HEADING in text
    assert "### Antigravity (agy)" in text
    assert "# Shared Policy" not in text
    assert agents_tool.MANAGED_BEGIN in text
    assert agents_tool.MANAGED_END in text

    # Idempotent
    assert agents_tool.cmd_sync(repo, cfg, check_only=True) == 0

    # Preserves user notes outside markers & restores missing frontmatter
    body_without_fm = text.split("---\n\n", 1)[1] + "\n# User Note\nKeep me.\n"
    rule_path.write_text(body_without_fm, encoding="utf-8")
    assert agents_tool.cmd_sync(repo, cfg, check_only=False) == 0
    restored = rule_path.read_text(encoding="utf-8")
    assert restored.startswith("---\ntrigger: always_on\n")
    assert "# User Note\nKeep me." in restored

    # Skips writing when extra_only target has empty/missing extra text
    rule_path.unlink()
    (repo / "agy-extra.md").write_text("   \n", encoding="utf-8")
    assert agents_tool.cmd_sync(repo, cfg, check_only=False) == 0
    assert not rule_path.exists()


def test_inspect_agent_configs_and_shape_for_extra_only_frontmatter(tmp_path, monkeypatch):
    home = tmp_path / "home"
    rules_dir = home / ".gemini/config/rules"
    rules_dir.mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("USERPROFILE", str(home))

    target = agents_tool.AgentConfigTarget(
        name="Antigravity Global Instructions",
        format="markdown",
        default_paths=["~/.gemini/config/rules/antigravity.md"],
        extra_text_file="agy-extra.md",
        extra_only=True,
        frontmatter={"trigger": "always_on", "description": "desc"},
    )
    common_data = {"mcp_servers": {"context7": {"type": "http", "url": "https://x"}}, "skills": ["worktrunk"]}
    rule_path = rules_dir / "antigravity.md"

    # Valid rule passes without MCP/skills markers
    rule_path.write_text(
        f'---\ntrigger: always_on\ndescription: "desc"\n---\n\n{agents_tool.AGENT_EXTRA_HEADING}\n\nBody.\n',
        encoding="utf-8",
    )
    results, failed = agents_tool.inspect_agent_configs([target], common_data)
    assert not failed
    assert results[0].missing_mcp == []
    assert results[0].missing_skills == []
    assert results[0].shape_issues == []

    # Missing frontmatter / trigger fails shape check
    assert "missing YAML frontmatter with trigger" in agents_tool.check_config_shape(
        target, f"{agents_tool.AGENT_EXTRA_HEADING}\n\nBody.\n"
    )
    assert "missing YAML frontmatter with trigger" in agents_tool.check_config_shape(
        target, f'---\ndescription: "no trigger"\n---\n\n{agents_tool.AGENT_EXTRA_HEADING}\n'
    )


def test_skills_cli_agent_targets_maps_agy(monkeypatch):
    monkeypatch.setattr(agents_tool.shutil, "which", lambda cmd: f"/bin/{cmd}" if cmd in {"agy", "claude"} else None)
    cfg = {
        "agent_clis": [
            {"name": "Claude Code", "command": "claude"},
            {"name": "Antigravity", "command": "agy"},
        ]
    }
    assert agents_tool.skills_cli_agent_targets(cfg) == ["claude-code", "antigravity"]


def test_repo_config_includes_antigravity_targets():
    cfg = agents_tool.load_config(ROOT / "home/.config/ooodnakov/agents/config.json")
    assert any(cli["command"] == "agy" for cli in cfg["agent_clis"])

    targets = agents_tool.parse_agent_targets(cfg["agent_configs"])
    updates = agents_tool.parse_agent_update_specs(cfg.get("agent_updates", []))
    for query in ("antigravity", "agy"):
        selected, unmatched = agents_tool.select_agent_targets(targets, updates, [query])
        assert unmatched == []
        assert [t.name for t in selected] == [
            "Antigravity Shared Instructions",
            "Antigravity",
            "Antigravity Global Instructions",
        ]

    agy_instr = next(t for t in targets if t.name == "Antigravity Global Instructions")
    assert agy_instr.extra_only is True
    assert agy_instr.frontmatter == {
        "trigger": "always_on",
        "description": "Antigravity-specific context control and tool execution guidelines managed by oooconf.",
    }
    assert (ROOT / agy_instr.extra_text_file).is_file()


@pytest.mark.parametrize(
    "bad_name",
    ["", "   ", ".", "..", "../evil", "..\\evil", "a/b", "a\\b", "bad\x00name"],
)
def test_resolve_mcp_path_rejects_traversal(tmp_path, monkeypatch, bad_name):
    home = tmp_path / "home"
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("USERPROFILE", str(home))

    with pytest.raises(ValueError, match="invalid MCP server name"):
        agents_tool.resolve_mcp_path(tmp_path, bad_name)


def test_resolve_mcp_path_accepts_valid_name(tmp_path, monkeypatch):
    home = tmp_path / "home"
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("USERPROFILE", str(home))

    resolved = agents_tool.resolve_mcp_path(tmp_path, "context7")
    assert resolved == (home / ".local/share/ooodnakov-config/mcp/context7").resolve()


def test_render_codex_minimax_provider_always_uses_env_var_name():
    rendered = agents_tool.render_codex_minimax_provider("global", materialize_secrets=True, api_key="secret")

    assert 'env_key = "MINIMAX_API_KEY"' in rendered
    assert "secret" not in rendered


def test_cmd_mcp_sync_rejects_dash_source_and_uses_end_of_options(tmp_path, monkeypatch):
    home = tmp_path / "home"
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("USERPROFILE", str(home))

    repo = tmp_path / "repo"
    repo.mkdir()
    calls: list[list[str]] = []

    def fake_run(command, check=True, **kwargs):
        calls.append(list(command))
        return subprocess.CompletedProcess(command, 0)

    monkeypatch.setattr(agents_tool.subprocess, "run", fake_run)

    (repo / "common.json").write_text(
        json.dumps({"mcp_servers": {"evil": {"source": "--upload-pack=touch /tmp/pwned"}}}),
        encoding="utf-8",
    )
    rc_bad = agents_tool.cmd_mcp_sync(repo, {"common_data_file": "common.json"}, check_only=False)
    assert rc_bad == 1
    assert calls == []

    (repo / "common.json").write_text(
        json.dumps({"mcp_servers": {"good": {"source": "https://example.com/mcp.git"}}}),
        encoding="utf-8",
    )
    rc_good = agents_tool.cmd_mcp_sync(repo, {"common_data_file": "common.json"}, check_only=False)
    expected_dir = agents_tool.resolve_mcp_path(repo, "good")
    assert rc_good == 0
    assert calls == [["git", "clone", "--", "https://example.com/mcp.git", str(expected_dir)]]


@pytest.mark.parametrize("bad_command", ["../evil", "a/b", "a\\b", "bad..cmd", ""])
def test_cmd_install_scripts_build_rejects_unsafe_command(tmp_path, bad_command):
    cfg = {
        "agent_updates": [
            {"name": "Bad Agent", "command": bad_command, "preferred": "npm", "package": "pkg"},
        ]
    }
    with pytest.raises(ValueError, match="invalid agent command name"):
        agents_tool.cmd_install_scripts_build(tmp_path, cfg)


def test_cmd_install_scripts_build_escapes_sh_and_ps1_messages(tmp_path):
    cfg = {
        "agent_updates": [
            {
                "name": "O'Reilly\u2019s Agent $(whoami)",
                "command": "oreilly-agent",
                "preferred": "npm",
                "package": "oreilly-pkg",
            }
        ]
    }

    assert agents_tool.cmd_install_scripts_build(tmp_path, cfg) == 0

    install_dir = tmp_path / "home" / ".config" / "ooodnakov" / "agents" / "install"
    sh_text = (install_dir / "install-oreilly-agent.sh").read_text(encoding="utf-8")
    ps1_text = (install_dir / "install-oreilly-agent.ps1").read_text(encoding="utf-8")

    assert "printf '%s\\n' 'Installing O'\"'\"'Reilly\u2019s Agent $(whoami) via pnpm...'" in sh_text
    assert "Write-Host 'Installing O''Reilly\u2019\u2019s Agent $(whoami) via pnpm...'" in ps1_text
    assert 'Write-Host "' not in ps1_text
