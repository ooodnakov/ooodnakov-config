#!/usr/bin/env python3
"""Generate oooconf completion scripts from tracked command/dependency catalogs."""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
COMMANDS_FILE = REPO_ROOT / "scripts" / "oooconf-commands.txt"
OPTIONAL_DEPS_FILE = REPO_ROOT / "scripts" / "optional-deps.toml"
ZSH_OUTPUT = REPO_ROOT / "home/.config/ooodnakov/zsh/completions/_oooconf"
POWERSHELL_OUTPUT = REPO_ROOT / "home/.config/ooodnakov/completions/oooconf-completions.ps1"

COMMAND_DESCRIPTIONS = {
    "bootstrap": "clone or update the repo, then run install",
    "install": "apply managed config",
    "deps": "install optional dependencies only",
    "update": "update the repo, then re-run install",
    "upgrade": "alias for update",
    "doctor": "validate managed links and tools",
    "check": "alias for doctor",
    "dry-run": "preview install without changes",
    "preview": "alias for dry-run",
    "delete": "remove managed links and restore backups",
    "remove": "remove managed links only",
    "lock": "regenerate dependency lock artifacts",
    "update-pins": "check or update pinned refs",
    "completions": "regenerate tracked completion files",
    "agents": "detect/sync/doctor/update AGENTS.md policy blocks",
    "shell": "manage local shell preferences",
    "secrets": "sync or validate local secret env files",
    "help": "show help",
    "version": "show version information",
}

SECRETS_SUBCOMMANDS = [
    "login",
    "unlock",
    "sync",
    "doctor",
    "list",
    "ls",
    "status",
    "logout",
    "add",
    "remove",
    "rm",
    "del",
]

SHELL_SUBCOMMANDS = [
    "status",
    "forgit-aliases",
    "typo-handling",
    "psfzf-tab",
    "psfzf-git",
    "auto-uv-env",
]

SHELL_FORGIT_ALIAS_MODES = ["plain", "forgit", "status"]
SHELL_TYPO_MODES = ["silent", "suggest", "help", "status"]
SHELL_PSFZF_MODES = ["enabled", "disabled", "status"]
SHELL_AUTO_UV_MODES = ["enabled", "quiet", "status"]


def parse_optional_deps(path: Path) -> list[tuple[str, str]]:
    deps: list[tuple[str, str]] = []
    current_key: str | None = None
    current_desc = ""

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        if line == "[[deps]]":
            if current_key:
                deps.append((current_key, current_desc))
            current_key = None
            current_desc = ""
            continue

        if "=" not in line:
            continue

        dotted_key, _, value = line.partition("=")
        dotted_key = dotted_key.strip()
        value = value.strip().strip('"')

        if dotted_key == "key":
            current_key = value
        elif dotted_key == "description":
            current_desc = value

    if current_key:
        deps.append((current_key, current_desc))

    return deps


def load_commands(path: Path) -> list[str]:
    commands: list[str] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        commands.append(line)

    if "help" not in commands:
        commands.append("help")

    return commands


def unique_preserving_order(items: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        result.append(item)
    return result


def quote_zsh(value: str) -> str:
    return value.replace("'", "'\\''")


def quote_ps(value: str) -> str:
    return value.replace("'", "''")


def render_zsh(commands: list[str], deps: list[tuple[str, str]]) -> str:
    commands = unique_preserving_order(commands)
    command_pattern = "|".join(commands)

    lines: list[str] = []
    lines.append("#compdef oooconf o")
    lines.append("")
    lines.append(
        "local -a oooconf_commands global_opts setup_opts deps_keys agents_subcommands agents_opts secrets_subcommands shell_subcommands shell_forgit_alias_modes shell_typo_modes shell_psfzf_modes shell_auto_uv_modes"
    )
    lines.append("local command_name secrets_command shell_command")
    lines.append("local i")
    lines.append("")
    lines.append("oooconf_commands=(")
    for command in commands:
        description = COMMAND_DESCRIPTIONS.get(command, "command")
        lines.append(f"  '{quote_zsh(command)}:{quote_zsh(description)}'")
    lines.append(")")
    lines.append("")
    lines.append("global_opts=(")
    lines.append("  '-C:run against a specific repo checkout:_files -/'")
    lines.append("  '--repo-root:run against a specific repo checkout:_files -/'")
    lines.append("  '--print-repo-root:print the resolved repo root'")
    lines.append("  '-h:show help'")
    lines.append("  '--help:show help'")
    lines.append("  '-n:add --dry-run to install or update'")
    lines.append("  '--dry-run:add --dry-run to install or update'")
    lines.append("  '--yes-optional:auto-accept optional dependency installs'")
    lines.append("  '-V:show version information'")
    lines.append("  '--version:show version information'")
    lines.append(")")
    lines.append("")
    lines.append("setup_opts=(")
    lines.append("  '--dry-run:preview actions without changing the filesystem'")
    lines.append("  '--yes-optional:auto-accept optional dependency installs'")
    lines.append("  '-h:show setup help'")
    lines.append("  '--help:show setup help'")
    lines.append(")")
    lines.append("")
    lines.append("deps_keys=(")
    for key, description in deps:
        desc = description if description else key
        lines.append(f"  '{quote_zsh(key)}:{quote_zsh(desc)}'")
    lines.append(")")
    lines.append("")
    lines.append("agents_subcommands=(")
    lines.append("  'detect:detect configured agent CLIs on PATH'")
    lines.append("  'sync:append or update shared AGENTS.md block'")
    lines.append("  'doctor:verify AGENTS.md shared block is current'")
    lines.append("  'update:update installed agent CLIs'")
    lines.append(")")
    lines.append("")
    lines.append("agents_opts=(")
    lines.append("  '--repo-root:repo root containing oooconf agent config:_files -/'")
    lines.append("  '--config:override agent config JSON path:_files'")
    lines.append(")")
    lines.append("")
    lines.append("secrets_subcommands=(")
    for command in SECRETS_SUBCOMMANDS:
        lines.append(f"  '{command}:{command}'")
    lines.append(")")
    lines.append("")
    lines.append("shell_subcommands=(")
    for command in SHELL_SUBCOMMANDS:
        lines.append(f"  '{command}:{command}'")
    lines.append(")")
    lines.append("")
    lines.append("shell_forgit_alias_modes=(")
    for mode in SHELL_FORGIT_ALIAS_MODES:
        lines.append(f"  '{mode}:{mode}'")
    lines.append(")")
    lines.append("shell_typo_modes=(")
    for mode in SHELL_TYPO_MODES:
        lines.append(f"  '{mode}:{mode}'")
    lines.append(")")
    lines.append("shell_psfzf_modes=(")
    for mode in SHELL_PSFZF_MODES:
        lines.append(f"  '{mode}:{mode}'")
    lines.append(")")
    lines.append("shell_auto_uv_modes=(")
    for mode in SHELL_AUTO_UV_MODES:
        lines.append(f"  '{mode}:{mode}'")
    lines.append(")")
    lines.append("")
    lines.append("command_name=")
    lines.append("for (( i = 2; i < CURRENT; i++ )); do")
    lines.append("  case \"$words[i]\" in")
    lines.append("    -C|--repo-root)")
    lines.append("      (( i++ ))")
    lines.append("      ;;")
    lines.append("    -*)")
    lines.append("      ;;")
    lines.append(f"    {command_pattern})")
    lines.append("      command_name=\"$words[i]\"")
    lines.append("      break")
    lines.append("      ;;")
    lines.append("  esac")
    lines.append("done")
    lines.append("")
    lines.append("if [[ -z \"$command_name\" ]]; then")
    lines.append("  _describe -t commands 'oooconf command' oooconf_commands && return 0")
    lines.append("  _describe -t options 'oooconf option' global_opts && return 0")
    lines.append("  return 0")
    lines.append("fi")
    lines.append("")
    lines.append("case \"$command_name\" in")
    lines.append("  upgrade)")
    lines.append("    command_name=update")
    lines.append("    ;;")
    lines.append("  check)")
    lines.append("    command_name=doctor")
    lines.append("    ;;")
    lines.append("  preview)")
    lines.append("    command_name=dry-run")
    lines.append("    ;;")
    lines.append("esac")
    lines.append("")
    lines.append("case \"$command_name\" in")
    lines.append("  help)")
    lines.append("    _describe -t commands 'oooconf command' oooconf_commands && return 0")
    lines.append("    ;;")
    lines.append("  install|update|deps)")
    lines.append("    _describe -t options 'oooconf option' setup_opts")
    lines.append("    _describe -t dependencies 'dependency key' deps_keys")
    lines.append("    return 0")
    lines.append("    ;;")
    lines.append("  completions)")
    lines.append("    _describe -t options 'oooconf completions option' '--dry-run:preview generation actions'")
    lines.append("    return 0")
    lines.append("    ;;")
    lines.append("  update-pins)")
    lines.append("    _describe -t options 'oooconf update-pins option' '--apply:write updated pins and lock artifacts'")
    lines.append("    return 0")
    lines.append("    ;;")
    lines.append("  agents)")
    lines.append("    local agents_command")
    lines.append("    agents_command=")
    lines.append("    for (( i = 3; i < CURRENT; i++ )); do")
    lines.append("      case \"$words[i]\" in")
    lines.append("        detect|sync|doctor|update)")
    lines.append("          agents_command=\"$words[i]\"")
    lines.append("          break")
    lines.append("          ;;")
    lines.append("      esac")
    lines.append("    done")
    lines.append("")
    lines.append("    if [[ -z \"$agents_command\" ]]; then")
    lines.append("      _describe -t agents-subcommands 'oooconf agents command' agents_subcommands && return 0")
    lines.append("      return 0")
    lines.append("    fi")
    lines.append("")
    lines.append("    case \"$agents_command\" in")
    lines.append("      detect)")
    lines.append("        _describe -t options 'oooconf agents detect option' $agents_opts '--json:emit machine-readable JSON output'")
    lines.append("        ;;")
    lines.append("      sync|update)")
    lines.append("        _describe -t options \"oooconf agents $agents_command option\" $agents_opts '--check:validate only; do not write files'")
    lines.append("        ;;")
    lines.append("      doctor)")
    lines.append("        _describe -t options 'oooconf agents doctor option' $agents_opts '--strict-config-paths:fail if no default config path exists for a target'")
    lines.append("        ;;")
    lines.append("    esac")
    lines.append("    return 0")
    lines.append("    ;;")
    lines.append("  shell)")
    lines.append("    shell_command=")
    lines.append("    for (( i = 3; i < CURRENT; i++ )); do")
    lines.append("      case \"$words[i]\" in")
    lines.append("        status|forgit-aliases|typo-handling|psfzf-tab|psfzf-git|auto-uv-env)")
    lines.append("          shell_command=\"$words[i]\"")
    lines.append("          break")
    lines.append("          ;;")
    lines.append("      esac")
    lines.append("    done")
    lines.append("")
    lines.append("    if [[ -z \"$shell_command\" ]]; then")
    lines.append("      _describe -t shell-subcommands 'oooconf shell command' shell_subcommands && return 0")
    lines.append("      return 0")
    lines.append("    fi")
    lines.append("")
    lines.append("    case \"$shell_command\" in")
    lines.append("      forgit-aliases)")
    lines.append("        _describe -t modes 'forgit alias mode' shell_forgit_alias_modes")
    lines.append("        ;;")
    lines.append("      typo-handling)")
    lines.append("        _describe -t modes 'typo handling mode' shell_typo_modes")
    lines.append("        ;;")
    lines.append("      psfzf-tab|psfzf-git)")
    lines.append("        _describe -t modes 'PSFzf mode' shell_psfzf_modes")
    lines.append("        ;;")
    lines.append("      auto-uv-env)")
    lines.append("        _describe -t modes 'auto-uv-env mode' shell_auto_uv_modes")
    lines.append("        ;;")
    lines.append("      status)")
    lines.append("        return 0")
    lines.append("        ;;")
    lines.append("    esac")
    lines.append("    return 0")
    lines.append("    ;;")
    lines.append("  secrets)")
    lines.append("    secrets_command=")
    lines.append("    for (( i = 3; i < CURRENT; i++ )); do")
    lines.append("      case \"$words[i]\" in")
    lines.append("        login|unlock|sync|doctor|list|ls|status|logout|add|remove|rm|del)")
    lines.append("          secrets_command=\"$words[i]\"")
    lines.append("          break")
    lines.append("          ;;")
    lines.append("      esac")
    lines.append("    done")
    lines.append("")
    lines.append("    if [[ -z \"$secrets_command\" ]]; then")
    lines.append("      _describe -t secrets-subcommands 'oooconf secrets command' secrets_subcommands && return 0")
    lines.append("      return 0")
    lines.append("    fi")
    lines.append("")
    lines.append("    case \"$secrets_command\" in")
    lines.append("      ls)")
    lines.append("        secrets_command=list")
    lines.append("        ;;")
    lines.append("      rm|del)")
    lines.append("        secrets_command=remove")
    lines.append("        ;;")
    lines.append("    esac")
    lines.append("")
    lines.append("    case \"$secrets_command\" in")
    lines.append("      sync)")
    lines.append("        _describe -t options 'oooconf secrets sync option' '--backend:secret backend to use:(bw)' '--template:override the tracked template path:_files' '--dry-run:preview the sync without writing files' '--force:rewrite generated files even when unchanged'")
    lines.append("        ;;")
    lines.append("      doctor)")
    lines.append("        _describe -t options 'oooconf secrets doctor option' '--backend:secret backend to use:(bw)' '--template:override the tracked template path:_files'")
    lines.append("        ;;")
    lines.append("      list)")
    lines.append("        _describe -t options 'oooconf secrets list option' '--template:override the tracked template path:_files' '--resolved:resolve bw:// references (requires unlocked BW_SESSION)' '--backend:secret backend to use:(bw)'")
    lines.append("        ;;")
    lines.append("      status)")
    lines.append("        _describe -t options 'oooconf secrets status option' '--template:override the tracked template path:_files'")
    lines.append("        ;;")
    lines.append("      login)")
    lines.append("        _describe -t options 'oooconf secrets login option' '--server:Bitwarden or Vaultwarden server URL:'")
    lines.append("        ;;")
    lines.append("      unlock)")
    lines.append("        _describe -t options 'oooconf secrets unlock option' '--shell:shell syntax to emit:(sh zsh bash pwsh)' '--raw:print only the unlocked session token'")
    lines.append("        ;;")
    lines.append("      add|remove)")
    lines.append("        _describe -t options \"oooconf secrets $secrets_command option\" '--template:override the tracked template path:_files'")
    lines.append("        ;;")
    lines.append("      logout)")
    lines.append("        return 0")
    lines.append("        ;;")
    lines.append("    esac")
    lines.append("    return 0")
    lines.append("    ;;")
    lines.append("  dry-run|doctor|delete|remove|lock|version|bootstrap)")
    lines.append("    return 0")
    lines.append("    ;;")
    lines.append("esac")
    lines.append("")
    lines.append("return 0")

    return "\n".join(lines) + "\n"


def format_ps_array(values: list[str], indent: str = "        ") -> list[str]:
    lines: list[str] = []
    total = len(values)
    for index, value in enumerate(values):
        suffix = "," if index < total - 1 else ""
        lines.append(f"{indent}'{quote_ps(value)}'{suffix}")
    return lines


def render_powershell(commands: list[str], deps: list[tuple[str, str]]) -> str:
    commands = unique_preserving_order(commands)
    dep_keys = [key for key, _ in deps]

    lines: list[str] = []
    lines.append("# PowerShell argument completions for oooconf")
    lines.append("# This file is automatically loaded by the managed PowerShell profile via common.ps1")
    lines.append("")
    lines.append("function Get-OooconfCompletions {")
    lines.append("    param($wordToComplete, $commandAst, $cursorPosition)")
    lines.append("")
    lines.append("    $OooconfCommands = @(")
    lines.extend(format_ps_array(commands))
    lines.append("    )")
    lines.append("")
    lines.append("    $OooconfGlobalOptions = @(")
    lines.append("        '-C', '--repo-root', '-h', '--help', '-n', '--dry-run',")
    lines.append("        '--yes-optional', '-V', '--version', '--print-repo-root'")
    lines.append("    )")
    lines.append("")
    lines.append("    $OooconfSecretsSubcommands = @(")
    lines.extend(format_ps_array(SECRETS_SUBCOMMANDS))
    lines.append("    )")
    lines.append("")
    lines.append("    $OooconfShellSubcommands = @('status', 'forgit-aliases', 'typo-handling', 'psfzf-tab', 'psfzf-git', 'auto-uv-env')")
    lines.append("    $OooconfForgitAliasModes = @('plain', 'forgit', 'status')")
    lines.append("    $OooconfTypoHandlingModes = @('silent', 'suggest', 'help', 'status')")
    lines.append("    $OooconfPsfzfModes = @('enabled', 'disabled', 'status')")
    lines.append("    $ShellValues = @('zsh', 'pwsh', 'bash', 'fish')")
    lines.append("")
    lines.append("    $OooconfDepsKeys = @(")
    lines.extend(format_ps_array(dep_keys))
    lines.append("    )")
    lines.append("")
    lines.append("    # Simple AST parsing to find the command and subcommands")
    lines.append("    $elements = $commandAst.CommandElements")
    lines.append("    $tokens = @()")
    lines.append("    for ($i = 0; $i -lt $elements.Count; $i++) {")
    lines.append("        $element = $elements[$i]")
    lines.append("        if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {")
    lines.append("            $val = $element.Value")
    lines.append("            if ($val -eq $wordToComplete -and $i -eq ($elements.Count - 1)) { break }")
    lines.append("            $tokens += $val")
    lines.append("        }")
    lines.append("    }")
    lines.append("")
    lines.append("    # Find the main oooconf command position (it might be oooconf/o, .ps1/.cmd variants, or a path)")
    lines.append("    $commandIndex = -1")
    lines.append("    for ($i = 0; $i -lt $tokens.Length; $i++) {")
    lines.append("        if ($tokens[$i] -match '(^|[\\\\/])(oooconf|o)(\\.ps1|\\.cmd)?$') {")
    lines.append("            $commandIndex = $i")
    lines.append("            break")
    lines.append("        }")
    lines.append("    }")
    lines.append("")
    lines.append("    if ($commandIndex -eq -1) { return @() }")
    lines.append("")
    lines.append("    # Find the first subcommand after oooconf that isn't a global option")
    lines.append("    $subcommand = $null")
    lines.append("    $subcommandIndex = -1")
    lines.append("    for ($i = $commandIndex + 1; $i -lt $tokens.Length; $i++) {")
    lines.append("        $t = $tokens[$i]")
    lines.append("        if ($t -in $OooconfCommands) {")
    lines.append("            $subcommand = $t")
    lines.append("            $subcommandIndex = $i")
    lines.append("            break")
    lines.append("        }")
    lines.append("    }")
    lines.append("")
    lines.append("    $completions = @()")
    lines.append("")
    lines.append("    if ($null -eq $subcommand) {")
    lines.append("        # Complete subcommands and global options")
    lines.append("        $completions = $OooconfCommands + $OooconfGlobalOptions")
    lines.append("    }")
    lines.append("    elseif ($subcommand -eq 'secrets') {")
    lines.append("        # Secrets sub-subcommands")
    lines.append("        $secSub = $null")
    lines.append("        for ($i = $subcommandIndex + 1; $i -lt $tokens.Length; $i++) {")
    lines.append("            if ($tokens[$i] -in $OooconfSecretsSubcommands) {")
    lines.append("                $secSub = $tokens[$i]")
    lines.append("                break")
    lines.append("            }")
    lines.append("        }")
    lines.append("")
    lines.append("        if ($null -eq $secSub) {")
    lines.append("            $completions = $OooconfSecretsSubcommands + @('--dry-run', '--resolved', '--shell')")
    lines.append("        } else {")
    lines.append("            # Sub-subcommand options")
    lines.append("            if ($tokens[-1] -eq '--shell') {")
    lines.append("                $completions = $ShellValues")
    lines.append("            } else {")
    lines.append("                switch ($secSub) {")
    lines.append("                    'unlock' { $completions = @('--shell', '--raw') }")
    lines.append("                    'sync'   { $completions = @('--dry-run', '--force', '--template', '--backend') }")
    lines.append("                    'list'   { $completions = @('--resolved', '--template', '--backend') }")
    lines.append("                    'ls'     { $completions = @('--resolved', '--template', '--backend') }")
    lines.append("                    'login'  { $completions = @('--server') }")
    lines.append("                    default  { $completions = @('--template') }")
    lines.append("                }")
    lines.append("            }")
    lines.append("        }")
    lines.append("    }")
    lines.append("    elseif ($subcommand -eq 'shell') {")
    lines.append("        $shellSub = $null")
    lines.append("        for ($i = $subcommandIndex + 1; $i -lt $tokens.Length; $i++) {")
    lines.append("            if ($tokens[$i] -in $OooconfShellSubcommands) {")
    lines.append("                $shellSub = $tokens[$i]")
    lines.append("                break")
    lines.append("            }")
    lines.append("        }")
    lines.append("        if ($null -eq $shellSub) {")
    lines.append("            $completions = $OooconfShellSubcommands")
    lines.append("        } else {")
    lines.append("            switch ($shellSub) {")
    lines.append("                'forgit-aliases' { $completions = $OooconfForgitAliasModes }")
    lines.append("                'typo-handling'  { $completions = $OooconfTypoHandlingModes }")
    lines.append("                'psfzf-tab'      { $completions = $OooconfPsfzfModes }")
    lines.append("                'psfzf-git'      { $completions = $OooconfPsfzfModes }")
    lines.append("                'auto-uv-env'    { $completions = @('enabled', 'quiet', 'status') }")
    lines.append("            }")
    lines.append("        }")
    lines.append("    }")
    lines.append("    elseif ($subcommand -in @('install', 'deps', 'update', 'upgrade')) {")
    lines.append("        $completions = @('--dry-run', '--yes-optional') + $OooconfDepsKeys")
    lines.append("    }")
    lines.append("    elseif ($subcommand -eq 'agents') {")
    lines.append("        $completions = @('detect', 'sync', 'doctor', 'update', '--json', '--check', '--strict-config-paths')")
    lines.append("    }")
    lines.append("    elseif ($subcommand -eq 'update-pins') {")
    lines.append("        $completions = @('--apply')")
    lines.append("    }")
    lines.append("    elseif ($subcommand -eq 'completions') {")
    lines.append("        $completions = @('--dry-run')")
    lines.append("    }")
    lines.append("")
    lines.append("    return $completions | Where-Object { $_ -like \"$wordToComplete*\" } | ForEach-Object {")
    lines.append("        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    lines.append("# Register for all possible names")
    lines.append("@('oooconf', 'oooconf.ps1', 'oooconf.cmd', 'o', 'o.ps1', 'o.cmd') | ForEach-Object {")
    lines.append("    Register-ArgumentCompleter -Native -CommandName $_ -ScriptBlock {")
    lines.append("        param($wordToComplete, $commandAst, $cursorPosition)")
    lines.append("        Get-OooconfCompletions -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition")
    lines.append("    }")
    lines.append("}")

    return "\n".join(lines) + "\n"


def main() -> int:
    commands = load_commands(COMMANDS_FILE)
    deps = parse_optional_deps(OPTIONAL_DEPS_FILE)

    ZSH_OUTPUT.write_text(render_zsh(commands, deps), encoding="utf-8", newline="\n")
    POWERSHELL_OUTPUT.write_text(render_powershell(commands, deps), encoding="utf-8", newline="\n")

    print(f"updated: {ZSH_OUTPUT.relative_to(REPO_ROOT)}")
    print(f"updated: {POWERSHELL_OUTPUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
