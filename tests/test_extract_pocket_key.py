"""Local capture extraction must neither leak, guess nor overwrite secrets."""
import importlib.util
from pathlib import Path
import stat

import pytest

spec = importlib.util.spec_from_file_location("extract_key", Path(__file__).parents[1] / "scripts/extract_pocket_key.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_extract_duplicate_capture_without_overwriting(tmp_path):
    capture = tmp_path / "capture.pklg"
    capture.write_bytes(b"\x00APP&SK&ABCDEF1234567890\x00APP&SK&ABCDEF1234567890\x00")
    output = tmp_path / "key.json"
    module.export_key(capture, output)
    assert stat.S_IMODE(output.stat().st_mode) == 0o600
    assert module.extract_keys(capture) == {"ABCDEF1234567890"}
    with pytest.raises(FileExistsError):
        module.export_key(capture, output)


def test_reject_ambiguous_missing_and_long_keys(tmp_path):
    for data in [b"nothing", b"APP&SK&ABCDEF123456789012345678901234", b"APP&SK&ABCDEF1234567890\0APP&SK&ZZZZZZ1234567890\0"]:
        capture = tmp_path / "capture"
        capture.write_bytes(data)
        with pytest.raises(ValueError):
            module.export_key(capture, tmp_path / "result")
        assert not (tmp_path / "result").exists()


def test_chunk_boundary_and_no_secret_on_stdout(tmp_path, monkeypatch, capsys):
    capture = tmp_path / "capture"
    capture.write_bytes(b"x" * (1024 * 1024 - 12) + b"APP&SK&ABCDEF1234567890\0")
    assert module.extract_keys(capture) == {"ABCDEF1234567890"}
    monkeypatch.setattr("sys.argv", ["extract", str(capture), "--output", str(tmp_path / "result")])
    assert module.main() == 0
    assert "ABCDEF1234567890" not in capsys.readouterr().out
