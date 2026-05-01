import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from scripts.sync_color_theme import KOMOREBI_THEME_BY_THEME, _set_komorebi_theme_file


def test_komorebi_theme_sync_writes_schema_safe_main_theme(tmp_path: Path) -> None:
    path = tmp_path / "komorebi.json"

    for theme, expected in KOMOREBI_THEME_BY_THEME.items():
        path.write_text(
            json.dumps(
                {
                    "border": True,
                    "theme": {
                        "palette": "Base16",
                        "name": "Ashes",
                        "active_border": "Base0D",
                        "accent": "Base0D",
                    },
                }
            ),
            encoding="utf-8",
        )

        _set_komorebi_theme_file(path, theme)

        data = json.loads(path.read_text(encoding="utf-8"))
        assert data["theme"] == {
            "palette": expected["palette"],
            "name": expected["name"],
            "single_border": expected["single_border"],
            "unfocused_border": expected["unfocused_border"],
            "bar_accent": expected["bar_accent"],
        }
        assert "active_border" not in data["theme"]
        assert "accent" not in data["theme"]


def test_komorebi_theme_sync_writes_schema_safe_bar_theme(tmp_path: Path) -> None:
    path = tmp_path / "komorebi.bar.json"

    for theme, expected in KOMOREBI_THEME_BY_THEME.items():
        path.write_text(
            json.dumps(
                {
                    "left_widgets": [],
                    "right_widgets": [],
                    "theme": {
                        "palette": "Base16",
                        "name": "Ashes",
                        "bar_accent": "Base0D",
                        "active_border": "Base0D",
                    },
                }
            ),
            encoding="utf-8",
        )

        _set_komorebi_theme_file(path, theme)

        data = json.loads(path.read_text(encoding="utf-8"))
        assert data["theme"] == {
            "palette": expected["palette"],
            "name": expected["name"],
            "accent": expected["accent"],
        }
        assert "bar_accent" not in data["theme"]
        assert "active_border" not in data["theme"]
