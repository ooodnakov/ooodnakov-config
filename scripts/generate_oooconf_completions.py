#!/usr/bin/env python3
"""Generate oooconf completion scripts from tracked command/dependency catalogs."""

from __future__ import annotations

import re
from pathlib import Path

from oooconf_cli_spec import CliSpec, CommandSpec, load_cli_spec
from read_optional_deps import load_deps

REPO_ROOT = Path(__file__).resolve().parent.parent
COMMANDS_FILE = REPO_ROOT / "scripts" / "oooconf-commands.txt"
CLI_SPEC_FILE = REPO_ROOT / "scripts" / "oooconf-cli-spec.toml"
ZSH_OUTPUT = REPO_ROOT / "home/.config/ooodnakov/zsh/completions/_oooconf"
POWERSHELL_OUTPUT = REPO_ROOT / "home/.config/ooodnakov/completions/oooconf-completions.ps1"
PATH_OPTIONS = {"-C", "--repo-root", "--template", "--config"}


def is_path_option(option: str) -> bool:
    if option in PATH_OPTIONS:
        return True
    return option.endswith("-path")


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


def command_spec(spec: CliSpec, name: str) -> CommandSpec | None:
    return spec.commands.get(name)


def zsh_safe_name(value: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9_]", "_", value)
    if not safe:
        safe = "item"
    if safe[0].isdigit():
        safe = f"_{safe}"
    return safe


def subcommand_desc(command: CommandSpec, subcommand: str) -> str:
    return command.subcommand_descriptions.get(subcommand, subcommand)


def _render_zsh_command_metadata(lines: list[str], command: str, spec: CommandSpec) -> None:
    safe_command = zsh_safe_name(command)

    lines.append(f"cmd_{safe_command}_options=(")
    for option in spec.options:
        label = option[2:] if option.startswith("--") else option
        file_suffix = ":_files -/" if is_path_option(option) else ""
        lines.append(f"  '{quote_zsh(option)}:{quote_zsh(label)}{file_suffix}'")
    lines.append(")")

    lines.append(f"cmd_{safe_command}_subcommands=(")
    for subcommand in spec.subcommands:
        lines.append(f"  '{quote_zsh(subcommand)}:{quote_zsh(subcommand_desc(spec, subcommand))}'")
    lines.append(")")

    for subcommand in spec.subcommands:
        safe_sub = zsh_safe_name(subcommand)
        options = list(spec.subcommand_options.get(subcommand, ()))
        values = list(spec.subcommand_values.get(subcommand, ()))

        lines.append(f"cmd_{safe_command}_{safe_sub}_options=(")
        for option in options:
            label = option[2:] if option.startswith("--") else option
            file_suffix = ":_files -/" if is_path_option(option) else ""
            lines.append(f"  '{quote_zsh(option)}:{quote_zsh(label)}{file_suffix}'")
        lines.append(")")

        lines.append(f"cmd_{safe_command}_{safe_sub}_values=(")
        for value in values:
            lines.append(f"  '{quote_zsh(value)}:{quote_zsh(value)}'")
        lines.append(")")

        subsubs = list(spec.subsubcommands.get(subcommand, ()))
        subsub_desc = spec.subsubcommand_descriptions.get(subcommand, {})
        lines.append(f"cmd_{safe_command}_{safe_sub}_subsubcommands=(")
        for subsub in subsubs:
            lines.append(f"  '{quote_zsh(subsub)}:{quote_zsh(subsub_desc.get(subsub, subsub))}'")
        lines.append(")")

        nested_opts = spec.subsubcommand_options.get(subcommand, {})
        for subsub in subsubs:
            safe_subsub = zsh_safe_name(subsub)
            lines.append(f"cmd_{safe_command}_{safe_sub}_{safe_subsub}_options=(")
            for option in nested_opts.get(subsub, ()):
                label = option[2:] if option.startswith("--") else option
                lines.append(f"  '{quote_zsh(option)}:{quote_zsh(label)}'")
            lines.append(")")

    lines.append(f"cmd_{safe_command}_option_values=(")
    for key, values in spec.value_sets.items():
        option = f"--{key}"
        joined = " ".join(quote_zsh(value) for value in values)
        lines.append(f"  '{quote_zsh(option)}:{joined}'")
    lines.append(")")


def render_zsh(commands: list[str], deps: list[tuple[str, str]], spec: CliSpec) -> str:
    commands = unique_preserving_order(commands)
    command_pattern = "|".join(commands)

    alias_map = {name: command.alias_for for name, command in spec.commands.items() if command.alias_for}

    lines: list[str] = []
    lines.append("#compdef oooconf o")
    lines.append("")
    lines.append("local -a oooconf_commands global_opts deps_keys")
    lines.append("local command_name subcommand_name subsubcommand_name previous_token")
    lines.append("local safe_command safe_subcommand safe_subsubcommand")
    lines.append("local i")
    lines.append("typeset -A oooconf_aliases")
    lines.append("")

    lines.append("oooconf_commands=(")
    for command in commands:
        description = spec.commands.get(command).description if command in spec.commands else "command"
        lines.append(f"  '{quote_zsh(command)}:{quote_zsh(description)}'")
    lines.append(")")
    lines.append("")

    lines.append("global_opts=(")
    for option in spec.global_options:
        label = option[2:] if option.startswith("--") else option
        file_suffix = ":_files -/" if is_path_option(option) else ""
        lines.append(f"  '{quote_zsh(option)}:{quote_zsh(label)}{file_suffix}'")
    lines.append(")")
    lines.append("")

    lines.append("deps_keys=(")
    for key, description in deps:
        desc = description if description else key
        lines.append(f"  '{quote_zsh(key)}:{quote_zsh(desc)}'")
    lines.append(")")
    lines.append("")

    for alias, target in alias_map.items():
        lines.append(f"oooconf_aliases['{quote_zsh(alias)}']='{quote_zsh(target)}'")
    lines.append("")

    for command in commands:
        if command in spec.commands:
            _render_zsh_command_metadata(lines, command, spec.commands[command])
            lines.append("")

    lines.append("command_name=")
    lines.append("for (( i = 2; i < CURRENT; i++ )); do")
    lines.append('  case "$words[i]" in')
    lines.append("    -C|--repo-root)")
    lines.append("      (( i++ ))")
    lines.append("      ;;")
    lines.append("    -*)")
    lines.append("      ;;")
    lines.append(f"    {command_pattern})")
    lines.append('      command_name="$words[i]"')
    lines.append("      break")
    lines.append("      ;;")
    lines.append("  esac")
    lines.append("done")
    lines.append("")

    lines.append('if [[ -z "$command_name" ]]; then')
    lines.append("  _describe -t commands 'oooconf command' oooconf_commands && return 0")
    lines.append("  _describe -t options 'oooconf option' global_opts && return 0")
    lines.append("  return 0")
    lines.append("fi")
    lines.append("")

    lines.append('if [[ -n "${oooconf_aliases[$command_name]:-}" ]]; then')
    lines.append('  command_name="${oooconf_aliases[$command_name]}"')
    lines.append("fi")
    lines.append("")

    lines.append('safe_command="${command_name//[^A-Za-z0-9_]/_}"')
    lines.append('if [[ "$safe_command" =~ ^[0-9] ]]; then safe_command="_$safe_command"; fi')
    lines.append('eval "local -a command_options=("${cmd_${safe_command}_options[@]}")"')
    lines.append('eval "local -a command_subcommands=("${cmd_${safe_command}_subcommands[@]}")"')
    lines.append("")

    lines.append("subcommand_name=")
    lines.append("for (( i = 3; i < CURRENT; i++ )); do")
    lines.append('  case "$words[i]" in')
    lines.append("    -*) ;;")
    lines.append("    *)")
    lines.append('      local candidate="$words[i]"')
    lines.append("      if (( ${command_subcommands[(Ie)$candidate]} )); then")
    lines.append('        subcommand_name="$candidate"')
    lines.append("        break")
    lines.append("      fi")
    lines.append("      ;;")
    lines.append("  esac")
    lines.append("done")
    lines.append("")

    lines.append("previous_token=")
    lines.append('if (( CURRENT > 2 )); then previous_token="$words[CURRENT-1]"; fi')
    lines.append("")

    lines.append('if [[ -z "$subcommand_name" ]]; then')
    lines.append('  if [[ "$command_name" == help ]]; then')
    lines.append("    _describe -t commands 'oooconf command' oooconf_commands")
    lines.append("    return 0")
    lines.append("  fi")
    lines.append("  _describe -t subcommands 'oooconf subcommand' command_subcommands")
    lines.append("  _describe -t options 'oooconf option' command_options")
    lines.append('  if [[ "$command_name" == install || "$command_name" == deps || "$command_name" == update ]]; then')
    lines.append("    _describe -t dependencies 'dependency key' deps_keys")
    lines.append("  fi")
    lines.append("  return 0")
    lines.append("fi")
    lines.append("")

    lines.append('safe_subcommand="${subcommand_name//[^A-Za-z0-9_]/_}"')
    lines.append('if [[ "$safe_subcommand" =~ ^[0-9] ]]; then safe_subcommand="_$safe_subcommand"; fi')
    lines.append('eval "local -a sub_options=("${cmd_${safe_command}_${safe_subcommand}_options[@]}")"')
    lines.append('eval "local -a sub_values=("${cmd_${safe_command}_${safe_subcommand}_values[@]}")"')
    lines.append('eval "local -a sub_subcommands=("${cmd_${safe_command}_${safe_subcommand}_subsubcommands[@]}")"')
    lines.append('eval "local -a option_value_entries=("${cmd_${safe_command}_option_values[@]}")"')
    lines.append("")

    lines.append("subsubcommand_name=")
    lines.append("for (( i = 4; i < CURRENT; i++ )); do")
    lines.append('  case "$words[i]" in')
    lines.append("    -*) ;;")
    lines.append("    *)")
    lines.append('      local candidate="$words[i]"')
    lines.append("      if (( ${sub_subcommands[(Ie)$candidate]} )); then")
    lines.append('        subsubcommand_name="$candidate"')
    lines.append("        break")
    lines.append("      fi")
    lines.append("      ;;")
    lines.append("  esac")
    lines.append("done")
    lines.append("")

    lines.append("local option_entry")
    lines.append('for option_entry in "${option_value_entries[@]}"; do')
    lines.append('  local opt_name="${option_entry%%:*}"')
    lines.append('  local opt_values="${option_entry#*:}"')
    lines.append('  if [[ "$previous_token" == "$opt_name" ]]; then')
    lines.append('    _values "$opt_name value" ${(z)opt_values}')
    lines.append("    return 0")
    lines.append("  fi")
    lines.append("done")
    lines.append("")

    lines.append('if [[ -z "$subsubcommand_name" ]]; then')
    lines.append("  _describe -t options 'oooconf subcommand option' sub_options")
    lines.append("  _describe -t values 'oooconf subcommand value' sub_values")
    lines.append("  _describe -t subsubcommands 'oooconf subsubcommand' sub_subcommands")
    lines.append("  return 0")
    lines.append("fi")
    lines.append("")

    lines.append('safe_subsubcommand="${subsubcommand_name//[^A-Za-z0-9_]/_}"')
    lines.append('if [[ "$safe_subsubcommand" =~ ^[0-9] ]]; then safe_subsubcommand="_$safe_subsubcommand"; fi')
    lines.append(
        'eval "local -a subsub_options=("${cmd_${safe_command}_${safe_subcommand}_${safe_subsubcommand}_options[@]}")"'
    )
    lines.append("_describe -t options 'oooconf subsubcommand option' subsub_options")
    lines.append("return 0")

    return "\n".join(lines) + "\n"


def format_ps_array(values: list[str], indent: str = "        ") -> list[str]:
    lines: list[str] = []
    total = len(values)
    for index, value in enumerate(values):
        suffix = "," if index < total - 1 else ""
        lines.append(f"{indent}'{quote_ps(value)}'{suffix}")
    return lines


def format_ps_hashtable(mapping: dict[str, list[str]], indent: str = "    ") -> list[str]:
    lines: list[str] = [f"{indent}@{{"]
    for key in sorted(mapping.keys()):
        values = mapping[key]
        rendered = ", ".join(f"'{quote_ps(value)}'" for value in values)
        lines.append(f"{indent}    '{quote_ps(key)}' = @({rendered})")
    lines.append(f"{indent}}}")
    return lines


def render_powershell(commands: list[str], deps: list[tuple[str, str]], spec: CliSpec) -> str:
    commands = unique_preserving_order(commands)

    aliases: dict[str, list[str]] = {}
    command_options: dict[str, list[str]] = {}
    command_subcommands: dict[str, list[str]] = {}
    subcommand_options: dict[str, list[str]] = {}
    subcommand_values: dict[str, list[str]] = {}
    subsubcommands: dict[str, list[str]] = {}
    subsubcommand_options: dict[str, list[str]] = {}
    option_values: dict[str, list[str]] = {}

    for name, command in spec.commands.items():
        if command.alias_for:
            aliases[name] = [command.alias_for]
        command_options[name] = list(command.options)
        command_subcommands[name] = list(command.subcommands)
        for subcommand, options in command.subcommand_options.items():
            subcommand_options[f"{name}:{subcommand}"] = list(options)
        for subcommand, values in command.subcommand_values.items():
            subcommand_values[f"{name}:{subcommand}"] = list(values)
        for subcommand, values in command.subsubcommands.items():
            subsubcommands[f"{name}:{subcommand}"] = list(values)
        for subcommand, mapping in command.subsubcommand_options.items():
            for subsubcommand, options in mapping.items():
                subsubcommand_options[f"{name}:{subcommand}:{subsubcommand}"] = list(options)
        for key, values in command.value_sets.items():
            option_values[f"{name}:--{key}"] = list(values)

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
    lines.extend(format_ps_array(list(spec.global_options)))
    lines.append("    )")
    lines.append("")

    lines.append("    $OooconfDepsKeys = @(")
    lines.extend(format_ps_array([key for key, _ in deps]))
    lines.append("    )")
    lines.append("")

    lines.append("    $OooconfAliases =")
    lines.extend(format_ps_hashtable(aliases))
    lines.append("")

    lines.append("    $OooconfCommandOptions =")
    lines.extend(format_ps_hashtable(command_options))
    lines.append("")

    lines.append("    $OooconfCommandSubcommands =")
    lines.extend(format_ps_hashtable(command_subcommands))
    lines.append("")

    lines.append("    $OooconfSubcommandOptions =")
    lines.extend(format_ps_hashtable(subcommand_options))
    lines.append("")

    lines.append("    $OooconfSubcommandValues =")
    lines.extend(format_ps_hashtable(subcommand_values))
    lines.append("")

    lines.append("    $OooconfSubsubcommands =")
    lines.extend(format_ps_hashtable(subsubcommands))
    lines.append("")

    lines.append("    $OooconfSubsubcommandOptions =")
    lines.extend(format_ps_hashtable(subsubcommand_options))
    lines.append("")

    lines.append("    $OooconfOptionValues =")
    lines.extend(format_ps_hashtable(option_values))
    lines.append("")

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

    lines.append("    $commandIndex = -1")
    lines.append("    for ($i = 0; $i -lt $tokens.Length; $i++) {")
    lines.append("        if ($tokens[$i] -match '(^|[\\\\/])(oooconf|o)(\\.ps1|\\.cmd)?$') {")
    lines.append("            $commandIndex = $i")
    lines.append("            break")
    lines.append("        }")
    lines.append("    }")
    lines.append("    if ($commandIndex -eq -1) { return @() }")
    lines.append("")

    lines.append("    $commandName = $null")
    lines.append("    $commandPos = -1")
    lines.append("    for ($i = $commandIndex + 1; $i -lt $tokens.Length; $i++) {")
    lines.append("        $token = $tokens[$i]")
    lines.append("        if ($token -in $OooconfCommands) { $commandName = $token; $commandPos = $i; break }")
    lines.append("    }")
    lines.append("")

    lines.append("    $completions = @()")
    lines.append("    if ($null -eq $commandName) {")
    lines.append("        $completions = $OooconfCommands + $OooconfGlobalOptions")
    lines.append("    } else {")
    lines.append(
        "        if ($OooconfAliases.ContainsKey($commandName)) { $commandName = $OooconfAliases[$commandName][0] }"
    )
    lines.append(
        "        $commandOpts = if ($OooconfCommandOptions.ContainsKey($commandName)) { $OooconfCommandOptions[$commandName] } else { @() }"
    )
    lines.append(
        "        $subcommands = if ($OooconfCommandSubcommands.ContainsKey($commandName)) { $OooconfCommandSubcommands[$commandName] } else { @() }"
    )
    lines.append("")
    lines.append("        $subcommandName = $null")
    lines.append("        for ($i = $commandPos + 1; $i -lt $tokens.Length; $i++) {")
    lines.append("            if ($tokens[$i] -in $subcommands) { $subcommandName = $tokens[$i]; break }")
    lines.append("        }")
    lines.append("")
    lines.append("        if ($null -eq $subcommandName) {")
    lines.append("            $completions = $commandOpts + $subcommands")
    lines.append(
        "            if ($commandName -in @('install', 'deps', 'update')) { $completions += $OooconfDepsKeys }"
    )
    lines.append("        } else {")
    lines.append("            $lastToken = if ($tokens.Length -gt 0) { $tokens[-1] } else { '' }")
    lines.append('            $valueKey = "$commandName:$lastToken"')
    lines.append("            if ($OooconfOptionValues.ContainsKey($valueKey)) {")
    lines.append("                $completions = $OooconfOptionValues[$valueKey]")
    lines.append("            } else {")
    lines.append('                $optKey = "$commandName:$subcommandName"')
    lines.append('                $subsubKey = "$commandName:$subcommandName"')
    lines.append(
        "                $subsubCommands = if ($OooconfSubsubcommands.ContainsKey($subsubKey)) { $OooconfSubsubcommands[$subsubKey] } else { @() }"
    )
    lines.append("                $subsubcommandName = $null")
    lines.append("                for ($j = $commandPos + 2; $j -lt $tokens.Length; $j++) {")
    lines.append("                    if ($tokens[$j] -in $subsubCommands) { $subsubcommandName = $tokens[$j]; break }")
    lines.append("                }")
    lines.append("")
    lines.append("                if ($null -eq $subsubcommandName) {")
    lines.append(
        "                    if ($OooconfSubcommandOptions.ContainsKey($optKey)) { $completions += $OooconfSubcommandOptions[$optKey] }"
    )
    lines.append(
        "                    if ($OooconfSubcommandValues.ContainsKey($optKey)) { $completions += $OooconfSubcommandValues[$optKey] }"
    )
    lines.append("                    $completions += $subsubCommands")
    lines.append("                } else {")
    lines.append('                    $subsubOptKey = "$commandName:$subcommandName:$subsubcommandName"')
    lines.append(
        "                    if ($OooconfSubsubcommandOptions.ContainsKey($subsubOptKey)) { $completions += $OooconfSubsubcommandOptions[$subsubOptKey] }"
    )
    lines.append("                }")
    lines.append("            }")
    lines.append("        }")
    lines.append("    }")
    lines.append("")

    lines.append('    return $completions | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {')
    lines.append("        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    lines.append("@('oooconf', 'oooconf.ps1', 'oooconf.cmd', 'o', 'o.ps1', 'o.cmd') | ForEach-Object {")
    lines.append("    Register-ArgumentCompleter -Native -CommandName $_ -ScriptBlock {")
    lines.append("        param($wordToComplete, $commandAst, $cursorPosition)")
    lines.append(
        "        Get-OooconfCompletions -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition"
    )
    lines.append("    }")
    lines.append("}")

    return "\n".join(lines) + "\n"


def main() -> int:
    spec = load_cli_spec(CLI_SPEC_FILE)
    commands = load_commands(COMMANDS_FILE)
    deps_data = load_deps()["deps"]
    deps = [(dep.get("key", ""), dep.get("description", "")) for dep in deps_data if dep.get("key")]

    ZSH_OUTPUT.write_text(render_zsh(commands, deps, spec), encoding="utf-8", newline="\n")
    POWERSHELL_OUTPUT.write_text(render_powershell(commands, deps, spec), encoding="utf-8", newline="\n")

    print(f"updated: {ZSH_OUTPUT.relative_to(REPO_ROOT)}")
    print(f"updated: {POWERSHELL_OUTPUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
