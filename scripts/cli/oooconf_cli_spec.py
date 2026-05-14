#!/usr/bin/env python3
"""Canonical oooconf CLI spec parser and helpers."""

from __future__ import annotations

import re
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class Command:
    """One recursive oooconf command node."""

    name: str
    description: str = "command"
    alias_for: str | None = None
    options: dict[str, str] = field(default_factory=dict)
    completers: dict[str, str] = field(default_factory=dict)
    values: dict[str, str] = field(default_factory=dict)
    value_set: str | None = None
    option_value_sets: dict[str, str] = field(default_factory=dict)
    subcommands: dict[str, Command] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, name: str, data: dict[str, Any], path: tuple[str, ...] = ()) -> Command:
        """Build a command tree from nested TOML data."""
        if not isinstance(name, str):
            raise ValueError("Command names must be strings")
        if not isinstance(data, dict):
            raise ValueError(f"[{'.'.join((*path, name))}] must be a TOML table")

        command_path = (*path, name)
        location = ".".join(command_path)
        description = data.get("description", "command")
        if not isinstance(description, str):
            raise ValueError(f"[{location}].description must be a string")

        alias_for = data.get("alias_for")
        if alias_for is not None and not isinstance(alias_for, str):
            raise ValueError(f"[{location}].alias_for must be a string")

        value_set = data.get("value_set")
        if value_set is not None and not isinstance(value_set, str):
            raise ValueError(f"[{location}].value_set must be a string")

        raw_subcommands = _ensure_dict(data.get("subcommands"), f"[{location}].subcommands")
        subcommands = {
            sub_name: cls.from_dict(sub_name, sub_data, (*command_path, "subcommands"))
            for sub_name, sub_data in raw_subcommands.items()
        }

        return cls(
            name=name,
            description=description,
            alias_for=alias_for,
            options=_as_description_map(data.get("options"), f"[{location}].options"),
            completers=_as_string_map(data.get("completers"), f"[{location}].completers"),
            values=_as_description_map(data.get("values"), f"[{location}].values"),
            value_set=value_set,
            option_value_sets=_as_string_map(data.get("option_value_sets"), f"[{location}].option_value_sets"),
            subcommands=subcommands,
        )


@dataclass(frozen=True)
class CliSpec:
    global_options: dict[str, str]
    global_completers: dict[str, str]
    definitions: dict[str, dict[str, str]]
    commands: dict[str, Command]

    def command_names(self) -> list[str]:
        return list(self.commands.keys())

    def aliases(self) -> dict[str, str]:
        return {name: command.alias_for for name, command in self.commands.items() if command.alias_for is not None}

    def definition_values(self, name: str) -> dict[str, str]:
        if name not in self.definitions:
            raise ValueError(f"Unknown shared definition '{name}'")
        return self.definitions[name]


def shell_safe_name(value: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9_]", "_", value)
    if not safe:
        safe = "item"
    if safe[0].isdigit():
        safe = f"_{safe}"
    return safe


def load_cli_spec(path: Path, extra_definitions: dict[str, dict[str, str]] | None = None) -> CliSpec:
    data = tomllib.loads(path.read_text(encoding="utf-8"))

    global_table = _ensure_dict(data.get("global", {}), "[global]")
    definitions = _as_definitions(data.get("definitions"), "[definitions]")
    if extra_definitions:
        definitions = {**definitions, **extra_definitions}

    raw_commands = _ensure_dict(data.get("commands"), "[commands]")
    if not raw_commands:
        raise ValueError("[commands] table is required")

    commands = {name: Command.from_dict(name, payload, ("commands",)) for name, payload in raw_commands.items()}

    spec = CliSpec(
        global_options=_as_description_map(global_table.get("options"), "[global].options"),
        global_completers=_as_string_map(global_table.get("completers"), "[global].completers"),
        definitions=definitions,
        commands=commands,
    )
    validate_cli_spec(spec)
    return spec


def validate_cli_spec(spec: CliSpec) -> None:
    for option in spec.global_completers:
        if option not in spec.global_options:
            raise ValueError(f"[global].completers references unknown option '{option}'")

    safe_top_level: dict[str, str] = {}
    for name, command in spec.commands.items():
        if command.alias_for and command.alias_for not in spec.commands:
            raise ValueError(f"Command '{name}' aliases unknown command '{command.alias_for}'")
        _track_safe_name(safe_top_level, name, (name,))
        _validate_command(command, spec, (name,))


def _validate_command(command: Command, spec: CliSpec, path: tuple[str, ...]) -> None:
    location = " ".join(path)
    if command.value_set and command.value_set not in spec.definitions:
        raise ValueError(f"Command '{location}' references unknown value_set '{command.value_set}'")
    for option in command.completers:
        if option not in command.options and option not in spec.global_options:
            raise ValueError(f"Command '{location}' completer references unknown option '{option}'")
    for option, value_set in command.option_value_sets.items():
        if option not in command.options and option not in spec.global_options:
            raise ValueError(f"Command '{location}' option_value_sets references unknown option '{option}'")
        if value_set not in spec.definitions:
            raise ValueError(f"Command '{location}' references unknown option value_set '{value_set}'")

    safe_children: dict[str, str] = {}
    for name, child in command.subcommands.items():
        _track_safe_name(safe_children, name, (*path, name))
        _validate_command(child, spec, (*path, name))


def _track_safe_name(seen: dict[str, str], name: str, path: tuple[str, ...]) -> None:
    safe = shell_safe_name(name)
    rendered_path = " ".join(path)
    if safe in seen:
        raise ValueError(f"Command path '{rendered_path}' collides with '{seen[safe]}' after shell-safe normalization")
    seen[safe] = rendered_path


def _ensure_dict(values: object, location: str) -> dict[str, Any]:
    if values is None:
        return {}
    if not isinstance(values, dict):
        raise ValueError(f"{location} must be a TOML table")
    result: dict[str, Any] = {}
    for key, value in values.items():
        if not isinstance(key, str):
            raise ValueError(f"{location} keys must be strings")
        result[key] = value
    return result


def _as_string_map(values: object, location: str) -> dict[str, str]:
    raw = _ensure_dict(values, location)
    result: dict[str, str] = {}
    for key, value in raw.items():
        if not isinstance(value, str):
            raise ValueError(f"{location}.{key} must be a string")
        result[key] = value
    return result


def _as_description_map(values: object, location: str) -> dict[str, str]:
    if values is None:
        return {}
    if isinstance(values, list):
        result: dict[str, str] = {}
        for value in values:
            if not isinstance(value, str):
                raise ValueError(f"{location} entries must be strings")
            result[value] = _default_description(value)
        return result
    return _as_string_map(values, location)


def _as_definitions(values: object, location: str) -> dict[str, dict[str, str]]:
    raw = _ensure_dict(values, location)
    result: dict[str, dict[str, str]] = {}
    for name, mapping in raw.items():
        result[name] = _as_description_map(mapping, f"{location}.{name}")
    return result


def _default_description(value: str) -> str:
    if value.startswith("--"):
        return value[2:].replace("-", " ")
    if value.startswith("-"):
        return value[1:]
    return value
