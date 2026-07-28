"""
Tests for secret-gate CLI and core modules.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

# Allow importing secret_gate from the source tree
sys.path.insert(0, str(Path(__file__).parent.parent))

from secret_gate import run, load_session, save_session, is_session_valid, SESSION_FILE
from secret_gate.auth import authenticate
from secret_gate.config import get_config
from secret_gate.refresh import filter_secrets, export_secrets, print_export_lines


# ── config tests ──────────────────────────────────────────────────

def test_get_config_defaults():
    cfg = get_config()
    assert cfg["serverUrl"] == "https://vault.bitwarden.eu"
    assert "sets" in cfg
    assert isinstance(cfg["sets"], dict)


def test_get_config_cli_overrides():
    cfg = get_config({"server_url": "https://custom.example.com"})
    assert cfg["serverUrl"] == "https://custom.example.com"


# ── refresh tests ─────────────────────────────────────────────────

def test_filter_secrets_all_set():
    secrets = [
        {"key": "A", "value": "1"},
        {"key": "B", "value": "2"},
    ]
    config = {"sets": {"all": "*"}}
    result = filter_secrets(secrets, set_name="all", config=config)
    assert len(result) == 2


def test_filter_secrets_named_set():
    secrets = [
        {"key": "A", "value": "1"},
        {"key": "B", "value": "2"},
        {"key": "C", "value": "3"},
    ]
    config = {"sets": {"ci": ["A", "C"]}}
    result = filter_secrets(secrets, set_name="ci", config=config)
    assert len(result) == 2
    assert {s["key"] for s in result} == {"A", "C"}


def test_filter_secrets_by_keys():
    secrets = [
        {"key": "A", "value": "1"},
        {"key": "B", "value": "2"},
    ]
    result = filter_secrets(secrets, keys=["A"])
    assert len(result) == 1
    assert result[0]["key"] == "A"


def test_filter_secrets_unknown_set():
    secrets = [{"key": "A", "value": "1"}]
    config = {"sets": {}}
    result = filter_secrets(secrets, set_name="nonexistent", config=config)
    assert result == []


def test_export_secrets(monkeypatch):
    secrets = [
        {"key": "TEST_SECRET", "value": "myvalue"},
    ]
    exported = export_secrets(secrets)
    assert "TEST_SECRET" in exported
    assert os.environ["TEST_SECRET"] == "myvalue"
    del os.environ["TEST_SECRET"]


def test_print_export_lines(capsys):
    secrets = [
        {"key": "FOO", "value": "bar"},
    ]
    print_export_lines(secrets)
    captured = capsys.readouterr()
    assert 'export FOO="bar"' in captured.out


def test_print_export_lines_escapes_dollar(capsys):
    secrets = [
        {"key": "TOKEN", "value": "abc$123"},
    ]
    print_export_lines(secrets)
    captured = capsys.readouterr()
    assert "\\$" in captured.out


# ── auth tests ────────────────────────────────────────────────────

def test_authenticate_cached_valid(monkeypatch, tmp_path):
    """When cache is valid, authenticate returns cached session."""
    session_file = tmp_path / "session.json"
    session_file.write_text(json.dumps({
        "BW_SESSION": "test-session",
        "BWS_ACCESS_TOKEN": "test-token",
    }))
    monkeypatch.setattr("secret_gate.SESSION_FILE", session_file)
    monkeypatch.setattr("secret_gate.STATE_DIR", tmp_path)

    def fake_run(cmd, input_data=None):
        result = MagicMock()
        if cmd[0] == "bw" and cmd[1] == "status":
            result.returncode = 0
            result.stdout = '{"status":"unlocked"}'
        else:
            result.returncode = 1
            result.stdout = ""
        return result.returncode, result.stdout, ""

    monkeypatch.setattr("secret_gate.run", fake_run)
    monkeypatch.setattr("secret_gate.auth.run", fake_run)

    result = authenticate()
    assert result["success"] is True
    assert result["bw_session"] == "test-session"


def test_authenticate_no_login(monkeypatch, tmp_path):
    """When bw is not logged in, returns failure."""

    def fake_run(cmd, input_data=None):
        if cmd[0] == "bw" and cmd[1] == "status":
            return 1, "", "not logged in"
        return 1, "", ""

    monkeypatch.setattr("secret_gate.run", fake_run)
    monkeypatch.setattr("secret_gate.auth.run", fake_run)
    # Also disable cache
    monkeypatch.setattr("secret_gate.auth.load_session", lambda: {})
    monkeypatch.setattr("secret_gate.auth.is_session_valid", lambda: False)
    monkeypatch.setattr("secret_gate.SESSION_FILE", tmp_path / "nonexistent.json")

    result = authenticate()
    assert result["success"] is False
    assert "logged in" in result["message"].lower()


# ── session cache tests ───────────────────────────────────────────

def test_session_roundtrip(tmp_path, monkeypatch):
    monkeypatch.setattr("secret_gate.STATE_DIR", tmp_path)
    monkeypatch.setattr("secret_gate.SESSION_FILE", tmp_path / "session.json")

    save_session("abc123", "def456")
    session = load_session()
    assert session["BW_SESSION"] == "abc123"
    assert session["BWS_ACCESS_TOKEN"] == "def456"


def test_is_session_valid_false_no_cache(monkeypatch, tmp_path):
    monkeypatch.setattr("secret_gate.STATE_DIR", tmp_path)
    monkeypatch.setattr("secret_gate.SESSION_FILE", tmp_path / "nonexistent.json")
    assert is_session_valid() is False
