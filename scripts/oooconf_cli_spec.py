#!/usr/bin/env python3
"""Canonical oooconf CLI spec parser and helpers."""

from __future__ import annotations

import tomllib
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class CommandSpec:
    name: str
    description: str
    alias_for: str | None
    options: tuple[str, ...]
    subcommands: tuple[str, ...]
    subcommand_descriptions: dict[str, str]
    subcommand_options: dict[str, tuple[str, ...]]
    subcommand_values: dict[str, tuple[str, ...]]
    subsubcommands: dict[str, tuple[str, ...]]
    subsubcommand_descriptions: dict[str, dict[str, str]]
    subsubcommand_options: dict[str, dict[str, tuple[str, ...]]]
    value_sets: dict[str, tuple[str, ...]]
    values: tuple[str, ...]
    option_descriptions: dict[str, str]
    option_completion_types: dict[str, str]


@dataclass(frozen=True)
class CliSpec:
    global_options: tuple[str, ...]
    global_option_descriptions: dict[str, str]
    global_option_completion_types: dict[str, str]
    commands: dict[str, CommandSpec]

    def command_names(self) -> list[str]:
        return list(self.commands.keys())

    def aliases(self) -> dict[str, str]:
        return {name: command.alias_for for name, command in self.commands.items() if command.alias_for is not None}


def _as_tuple(values: object) -> tuple[str, ...]:
    if values is None:
        return ()
    if not isinstance(values, list):
        raise ValueError(f"Expected list[str], got {type(values).__name__}")
    normalized: list[str] = []
    for value in values:
        if not isinstance(value, str):
            raise ValueError(f"Expected string entry, got {type(value).__name__}")
        normalized.append(value)
    return tuple(normalized)


def _as_mapping_of_tuples(values: object) -> dict[str, tuple[str, ...]]:
    data = _ensure_dict(values)

    result: dict[str, tuple[str, ...]] = {}
    for key, entry in data.items():
        if not isinstance(key, str):
            raise ValueError("Command mapping keys must be strings")
        result[key] = _as_tuple(entry)
    return result


def _as_mapping_of_strings(values: object) -> dict[str, str]:
    data = _ensure_dict(values)

    result: dict[str, str] = {}
    for key, entry in data.items():
        if not isinstance(key, str):
            raise ValueError("Command mapping keys must be strings")
        if not isinstance(entry, str):
            raise ValueError("Expected string value for subcommand description")
        result[key] = entry
    return result


def _as_mapping_of_mapping_tuples(values: object) -> dict[str, dict[str, tuple[str, ...]]]:
    data = _ensure_dict(values)
    result: dict[str, dict[str, tuple[str, ...]]] = {}
    for key, entry in data.items():
        if not isinstance(key, str):
            raise ValueError("Command mapping keys must be strings")
        if not isinstance(entry, dict):
            raise ValueError("Expected table mapping for nested command entries")
        result[key] = _as_mapping_of_tuples(entry)
    return result


def _as_mapping_of_mapping_strings(values: object) -> dict[str, dict[str, str]]:
    data = _ensure_dict(values)
    result: dict[str, dict[str, str]] = {}
    for key, entry in data.items():
        if not isinstance(key, str):
            raise ValueError("Command mapping keys must be strings")
        if not isinstance(entry, dict):
            raise ValueError("Expected table mapping for nested command entries")
        result[key] = _as_mapping_of_strings(entry)
    return result


def _ensure_dict(values: object) -> dict[object, object]:
    if values is None:
        return {}
    if not isinstance(values, dict):
        raise ValueError(f"Expected table mapping, got {type(values).__name__}")
    return values


def load_cli_spec(path: Path) -> CliSpec:
    data = tomllib.loads(path.read_text(encoding="utf-8"))

    global_table = data.get("global", {})
    if not isinstance(global_table, dict):
        raise ValueError("[global] must be a TOML table")
    global_options = _as_tuple(global_table.get("options", []))
    global_option_descriptions = _as_mapping_of_strings(global_table.get("option_descriptions"))
    global_option_completion_types = _as_mapping_of_strings(global_table.get("option_completion_types"))

    raw_commands = data.get("commands", {})
    if not isinstance(raw_commands, dict) or not raw_commands:
        raise ValueError("[commands] table is required")

    commands: dict[str, CommandSpec] = {}
    for name, payload in raw_commands.items():
        if not isinstance(name, str):
            raise ValueError("Command names must be strings")
        if not isinstance(payload, dict):
            raise ValueError(f"[commands.{name}] must be a TOML table")

        description = payload.get("description", "command")
        if not isinstance(description, str):
            raise ValueError(f"[commands.{name}].description must be a string")

        alias_for = payload.get("alias_for")
        if alias_for is not None and not isinstance(alias_for, str):
            raise ValueError(f"[commands.{name}].alias_for must be a string")

        commands[name] = CommandSpec(
            name=name,
            description=description,
            alias_for=alias_for,
            options=_as_tuple(payload.get("options", [])),
            subcommands=_as_tuple(payload.get("subcommands", [])),
            subcommand_descriptions=_as_mapping_of_strings(payload.get("subcommand_descriptions")),
            subcommand_options=_as_mapping_of_tuples(payload.get("subcommand_options")),
            subcommand_values=_as_mapping_of_tuples(payload.get("subcommand_values")),
            subsubcommands=_as_mapping_of_tuples(payload.get("subsubcommands")),
            subsubcommand_descriptions=_as_mapping_of_mapping_strings(payload.get("subsubcommand_descriptions")),
            subsubcommand_options=_as_mapping_of_mapping_tuples(payload.get("subsubcommand_options")),
            value_sets=_as_mapping_of_tuples(payload.get("value_sets")),
            values=_as_tuple(payload.get("values", [])),
            option_descriptions=_as_mapping_of_strings(payload.get("option_descriptions")),
            option_completion_types=_as_mapping_of_strings(payload.get("option_completion_types")),
        )

    for command in commands.values():
        if command.alias_for and command.alias_for not in commands:
            raise ValueError(f"Command '{command.name}' aliases unknown command '{command.alias_for}'")

    return CliSpec(
        global_options=global_options,
        global_option_descriptions=global_option_descriptions,
        global_option_completion_types=global_option_completion_types,
        commands=commands,
    )
