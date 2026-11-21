"""Security hardening tests for scripts/security/secure_artifact.py."""

from __future__ import annotations

import hashlib
import io
import sys
import tarfile
import urllib.request
from pathlib import Path

import pytest
import zstandard

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from scripts.security import secure_artifact  # noqa: E402


class _FakeResponse:
    def __init__(self, payload: bytes) -> None:
        self._stream = io.BytesIO(payload)

    def read(self, size: int = -1) -> bytes:
        return self._stream.read(size)

    def __enter__(self) -> _FakeResponse:
        return self

    def __exit__(self, *_args: object) -> None:
        self._stream.close()


def test_https_only_redirect_handler_rejects_non_https() -> None:
    handler = secure_artifact._HttpsOnlyRedirectHandler()
    req = urllib.request.Request("https://example.test/start")

    for bad_url in ("http://example.test/next", "ftp://example.test/next"):
        with pytest.raises(secure_artifact.IntegrityError, match="non-HTTPS"):
            handler.redirect_request(req, io.BytesIO(), 302, "Found", {}, bad_url)

    redirected = handler.redirect_request(req, io.BytesIO(), 302, "Found", {}, "https://example.test/next")
    assert redirected is not None
    assert redirected.full_url == "https://example.test/next"


def test_https_only_redirect_handler_blocks_downgrade_in_opener() -> None:
    class _FakeHttpsRedirectOrigin(urllib.request.BaseHandler):
        handler_order = 100

        def https_open(self, req: urllib.request.Request):
            return self.parent.error("http", req, io.BytesIO(), 302, "Found", {"location": "http://127.0.0.1/evil"})

    opener = urllib.request.build_opener(_FakeHttpsRedirectOrigin, secure_artifact._HttpsOnlyRedirectHandler)
    with pytest.raises(secure_artifact.IntegrityError, match="non-HTTPS"):
        opener.open("https://example.test/artifact.tar.gz", timeout=5)


def test_download_enforces_max_download_bytes(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setattr(secure_artifact, "MAX_DOWNLOAD_BYTES", 16)
    recorded_handlers: list[tuple[object, ...]] = []

    def fake_build_opener(*handlers: object):
        recorded_handlers.append(handlers)

        class _Opener:
            def open(self, url: str, timeout: int = 60):
                assert url == "https://example.test/payload.bin"
                assert timeout == 60
                return _FakeResponse(b"x" * 17)

        return _Opener()

    monkeypatch.setattr(urllib.request, "build_opener", fake_build_opener)
    output = tmp_path / "payload.bin"

    with pytest.raises(secure_artifact.IntegrityError, match="download exceeds maximum allowed size"):
        secure_artifact.download("https://example.test/payload.bin", output, "0" * 64)

    assert recorded_handlers == [(secure_artifact._HttpsOnlyRedirectHandler,)]
    assert not output.exists()
    assert list(tmp_path.iterdir()) == []


def test_download_allows_exact_max_download_bytes(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    payload = b"0123456789abcdef"
    expected = hashlib.sha256(payload).hexdigest()
    monkeypatch.setattr(secure_artifact, "MAX_DOWNLOAD_BYTES", len(payload))

    def fake_build_opener(*_handlers: object):
        class _Opener:
            def open(self, _url: str, timeout: int = 60):
                return _FakeResponse(payload)

        return _Opener()

    monkeypatch.setattr(urllib.request, "build_opener", fake_build_opener)
    output = tmp_path / "payload.bin"

    secure_artifact.download("https://example.test/payload.bin", output, expected)
    assert output.read_bytes() == payload


def test_extract_tar_zst_enforces_max_decompressed_bytes(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    tar_buffer = io.BytesIO()
    data = b"a" * 2048
    with tarfile.open(fileobj=tar_buffer, mode="w") as bundle:
        info = tarfile.TarInfo("hello.txt")
        info.size = len(data)
        bundle.addfile(info, io.BytesIO(data))
    compressed = zstandard.ZstdCompressor().compress(tar_buffer.getvalue())

    archive = tmp_path / "bundle.tar.zst"
    archive.write_bytes(compressed)
    dest = tmp_path / "out"

    monkeypatch.setattr(secure_artifact, "MAX_DECOMPRESSED_BYTES", 512)
    with pytest.raises(secure_artifact.IntegrityError, match="decompressed archive exceeds maximum allowed size"):
        secure_artifact.extract_tar_zst(archive, dest)

    monkeypatch.setattr(secure_artifact, "MAX_DECOMPRESSED_BYTES", 64 * 1024)
    secure_artifact.extract_tar_zst(archive, dest)
    assert (dest / "hello.txt").read_bytes() == data
