import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("agents_tool", ROOT / "scripts/agents_tool.py")
agents_tool = importlib.util.module_from_spec(spec)
assert spec is not None and spec.loader is not None
sys.modules["agents_tool"] = agents_tool
spec.loader.exec_module(agents_tool)


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
    gemini = agents_tool.AgentConfigTarget("Gemini CLI", "json", [], "")
    codex = agents_tool.AgentConfigTarget("OpenAI Codex CLI", "toml", [], "")

    assert agents_tool.check_config_shape(opencode, '{"mcp": {}}') == []
    assert agents_tool.check_config_shape(gemini, '{"mcpServers": {}}') == []
    assert agents_tool.check_config_shape(codex, "[mcp_servers.test]\ncommand='x'") == []

    assert agents_tool.check_config_shape(opencode, '{"mcpServers": {}}')
    assert agents_tool.check_config_shape(gemini, '{"mcp": {}}')


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
    rc = agents_tool.cmd_skills_add(repo, cfg, "vercel-labs/agent-skills", "gemini", check_only=True, sync_now=False)
    assert rc == 0
    data = common_data.read_text(encoding="utf-8")
    assert "vercel-labs/agent-skills" not in data


def test_parse_mcp_json_inputs_multi():
    payload = '{"one":{"command":"pnpm","args":["dlx","a"]},"two":{"command":"pnpm","args":["dlx","b"]}}'
    result = agents_tool.parse_mcp_json_inputs(payload, allow_multi=True)
    assert set(result.keys()) == {"one", "two"}


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
        agents_tool.AgentUpdateSpec("Gemini CLI", "gemini", "npm", "@google/gemini-cli"),
    ]
    monkeypatch.setattr(agents_tool.shutil, "which", lambda cmd: "/bin/codex" if cmd == "codex" else None)

    selected, errors = agents_tool.select_install_specs(specs, [], install_all=False, missing_only=False)

    assert errors == []
    assert [spec.command for spec in selected] == ["gemini"]


def test_select_install_specs_supports_multiple_explicit_agents():
    specs = [
        agents_tool.AgentUpdateSpec("OpenAI Codex CLI", "codex", "npm", "@openai/codex"),
        agents_tool.AgentUpdateSpec("Gemini CLI", "gemini", "npm", "@google/gemini-cli"),
    ]

    selected, errors = agents_tool.select_install_specs(
        specs, ["codex", "Gemini CLI"], install_all=False, missing_only=False
    )

    assert errors == []
    assert [spec.command for spec in selected] == ["codex", "gemini"]


def test_cmd_install_check_mode_can_plan_selected_agents(tmp_path, capsys):
    cfg = {
        "agent_updates": [
            {"name": "OpenAI Codex CLI", "command": "codex", "preferred": "npm", "package": "@openai/codex"},
            {"name": "Gemini CLI", "command": "gemini", "preferred": "npm", "package": "@google/gemini-cli"},
        ]
    }

    rc = agents_tool.cmd_install(
        tmp_path,
        cfg,
        ["codex", "gemini"],
        check_only=True,
        install_all=False,
        missing_only=False,
    )

    out = capsys.readouterr().out
    assert rc == 0
    assert "Plan: install OpenAI Codex CLI via pnpm" in out
    assert "Plan: install Gemini CLI via pnpm" in out
