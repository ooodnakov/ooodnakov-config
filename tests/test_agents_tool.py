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
    assert claude["env"]["ANTHROPIC_AUTH_TOKEN"] == "{MINIMAX_API_KEY}"

    opencode = json.loads((home / ".config/opencode/opencode.json").read_text(encoding="utf-8"))
    assert opencode["model"] == "minimax/MiniMax-M2.7"
    assert opencode["provider"]["minimax"]["options"]["baseURL"] == "https://api.minimax.io/anthropic/v1"
    assert "apiKey" not in opencode["provider"]["minimax"]["options"]

    codex = (home / ".codex/config.toml").read_text(encoding="utf-8")
    assert "[model_providers.minimax]" in codex
    assert 'env_key = "MINIMAX_API_KEY"' in codex
    assert "[profiles.minimax]" in codex
