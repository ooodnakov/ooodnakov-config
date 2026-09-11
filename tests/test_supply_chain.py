from __future__ import annotations

import hashlib
import io
import json
import re
import sys
import tarfile
import tomllib
import zipfile
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from scripts.security import bin_track, secure_artifact  # noqa: E402


def _catalog() -> dict[str, object]:
    with (REPO_ROOT / "scripts/optional-deps.toml").open("rb") as stream:
        return tomllib.load(stream)


def test_direct_release_archives_have_valid_sha256_metadata() -> None:
    for dependency in _catalog()["deps"]:
        platforms = [dependency.get(name, {}) for name in ("linux", "macos", "windows")]
        direct = any(
            config.get("manager") in {"github-release", "download"} or "github.com" in str(config.get("url", ""))
            for config in platforms
            if isinstance(config, dict)
        )
        if direct:
            integrity = dependency.get("integrity")
            assert isinstance(integrity, dict) and integrity, dependency["key"]
            assert all(re.fullmatch(r"[0-9a-f]{64}", value) for value in integrity.values())


def test_script_exceptions_are_explicit_and_no_download_is_piped_to_shell() -> None:
    document = _catalog()
    scripted = [
        dependency
        for dependency in document["deps"]
        if any("install.sh" in str(value) or "sh.rustup.rs" in str(value) for value in dependency.values())
    ]
    assert scripted
    assert all(dependency.get("checksum_exception") for dependency in scripted)
    installers = "\n".join(
        path.read_text(encoding="utf-8") for path in (REPO_ROOT / "scripts/setup/lib").glob("setup-installers.*")
    )
    assert not re.search(r"(?:curl|wget)[^\n|]*\|\s*(?:ba)?sh", installers)


def test_all_github_actions_are_pinned_to_full_commit_sha() -> None:
    for workflow in (REPO_ROOT / ".github/workflows").glob("*.yml"):
        for reference in re.findall(r"uses:\s*([^\s#]+)", workflow.read_text(encoding="utf-8")):
            assert re.search(r"@[0-9a-f]{40}$", reference), f"unpinned action in {workflow}: {reference}"


def test_digest_mismatch_is_rejected(tmp_path: Path) -> None:
    artifact = tmp_path / "artifact.zip"
    artifact.write_bytes(b"untrusted")
    with pytest.raises(secure_artifact.IntegrityError, match="mismatch"):
        secure_artifact.verify(artifact, "0" * 64)


def test_verified_standalone_executable_can_be_staged(tmp_path: Path) -> None:
    executable = tmp_path / "tool"
    executable.write_bytes(b"verified executable")
    destination = tmp_path / "destination"

    secure_artifact.extract(executable, destination)

    assert (destination / "tool").read_bytes() == b"verified executable"


@pytest.mark.parametrize("kind", ("zip", "tar"))
def test_archive_path_traversal_is_rejected(tmp_path: Path, kind: str) -> None:
    archive = tmp_path / f"payload.{kind}"
    if kind == "zip":
        with zipfile.ZipFile(archive, "w") as bundle:
            bundle.writestr("../../escaped", "bad")
        extractor = secure_artifact.extract_zip
    else:
        with tarfile.open(archive, "w") as bundle:
            payload = b"bad"
            member = tarfile.TarInfo("../../escaped")
            member.size = len(payload)
            bundle.addfile(member, io.BytesIO(payload))
        extractor = secure_artifact.extract_tar
    with pytest.raises(secure_artifact.IntegrityError, match="unsafe archive member"):
        extractor(archive, tmp_path / "destination")
    assert not (tmp_path / "escaped").exists()


def test_archive_symlinks_are_rejected(tmp_path: Path) -> None:
    archive = tmp_path / "payload.tar"
    with tarfile.open(archive, "w") as bundle:
        member = tarfile.TarInfo("link")
        member.type = tarfile.SYMTYPE
        member.linkname = "/etc/passwd"
        bundle.addfile(member)
    with pytest.raises(secure_artifact.IntegrityError, match="unsafe archive member type"):
        secure_artifact.extract_tar(archive, tmp_path / "destination")


def test_bin_track_records_binary_without_redownload(tmp_path: Path, monkeypatch) -> None:
    binary = tmp_path / "bw"
    binary.write_bytes(b"verified binary bytes")
    config = tmp_path / "bin-config.json"
    monkeypatch.setenv("BIN_CONFIG", str(config))

    args = bin_track.argparse.Namespace(
        path=str(binary),
        name="bw",
        repo="bitwarden/cli",
        version="1.22.1",
        asset="bw-linux-1.22.1.zip",
        package_path="bw",
    )

    assert bin_track.track(args) == 0
    data = json.loads(config.read_text(encoding="utf-8"))
    entry = data["bins"][str(binary.resolve())]
    assert entry["remote_name"] == "bw"
    assert entry["version"] == "v1.22.1"
    assert entry["url"] == "https://github.com/bitwarden/cli/releases/tag/v1.22.1"
    assert entry["provider"] == "github"
    assert entry["package_path"] == "bw"
    assert entry["selected_asset"] == "bw-linux-1.22.1.zip"
    assert entry["hash"] == hashlib.sha256(b"verified binary bytes").hexdigest()
    # The on-disk binary is never re-downloaded or rewritten.
    assert binary.read_bytes() == b"verified binary bytes"

    # Idempotent: tracking again replaces the same key instead of duplicating it.
    assert bin_track.track(args) == 0
    assert len(json.loads(config.read_text(encoding="utf-8"))["bins"]) == 1
