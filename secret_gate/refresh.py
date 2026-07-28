"""
Refresh module — pull secrets from Bitwarden Secrets Manager
and export them as environment variables.
"""

from __future__ import annotations

import json
import os
import sys
from typing import Dict, List, Any, Optional

from secret_gate import run, load_session, is_session_valid


def get_all_secrets(config: Dict[str, Any]) -> List[Dict[str, str]]:
    """Retrieve all secrets from Bitwarden Secrets Manager.

    Requires BWS_ACCESS_TOKEN to be set in the environment
    (placed there by `secret-gate auth` or `refresh_session`).

    Returns:
        List of secrets, each with "key" and "value" keys.
    """
    bws_token = os.environ.get("BWS_ACCESS_TOKEN")
    if not bws_token:
        session = load_session()
        bws_token = session.get("BWS_ACCESS_TOKEN")
        if bws_token:
            os.environ["BWS_ACCESS_TOKEN"] = bws_token

    if not bws_token:
        return []

    server_url = config.get("serverUrl", "https://vault.bitwarden.eu")

    # Configure BWS server
    run(["bws", "config", "server-base", server_url])

    rc, stdout, stderr = run(["bws", "secret", "list"])
    if rc != 0:
        return []

    try:
        raw_secrets = json.loads(stdout)
    except json.JSONDecodeError:
        return []

    if not isinstance(raw_secrets, list):
        return []

    secrets: List[Dict[str, str]] = []
    for s in raw_secrets:
        key = s.get("key") or s.get("name") or ""
        value = s.get("value")
        if key and value is not None:
            secrets.append({"key": key, "value": value})

    return secrets


def refresh_session() -> bool:
    """Load cached session credentials into environment variables.

    Returns True if a valid session was loaded.
    """
    if not is_session_valid():
        return False

    session = load_session()
    bw_session = session.get("BW_SESSION")
    bws_token = session.get("BWS_ACCESS_TOKEN")

    if bw_session:
        os.environ["BW_SESSION"] = bw_session
    if bws_token:
        os.environ["BWS_ACCESS_TOKEN"] = bws_token

    return bool(bw_session)


def filter_secrets(
    secrets: List[Dict[str, str]],
    set_name: Optional[str] = None,
    keys: Optional[List[str]] = None,
    config: Optional[Dict[str, Any]] = None,
) -> List[Dict[str, str]]:
    """Filter secrets by named set and/or explicit key list.

    When both set_name and keys are provided, the result is the
    intersection: secrets must be in the set AND match a key.
    """
    if config is None:
        config = {}

    # Build the target key set
    target_keys: Optional[set] = None

    if set_name:
        sets = config.get("sets", {})
        if set_name not in sets:
            available = ", ".join(sets.keys())
            print(f"ERROR: Set '{set_name}' not found. Available: {available}", file=sys.stderr)
            return []
        set_keys = sets[set_name]
        if set_keys == "*":
            target_keys = None  # means "all"
        elif isinstance(set_keys, list):
            target_keys = set(set_keys)
        else:
            target_keys = set()

    if keys:
        key_set = set(keys)
        if target_keys is None:
            target_keys = key_set
        else:
            target_keys = target_keys & key_set

    if target_keys is None:
        return secrets

    return [s for s in secrets if s["key"] in target_keys]


def export_secrets(secrets: List[Dict[str, str]]) -> List[str]:
    """Set secrets as environment variables in the current process.

    Returns list of exported variable names.
    """
    exported: List[str] = []
    for s in secrets:
        key = s["key"]
        value = s["value"]
        os.environ[key] = value
        exported.append(key)
    return exported


def print_export_lines(secrets: List[Dict[str, str]], shell: str = "bash") -> None:
    """Print environment variable assignments for shell sourcing.

    Args:
        secrets: List of secret dicts with 'key' and 'value'.
        shell: Target shell — 'bash' (export KEY="VALUE") or
               'pwsh' ($env:KEY = "VALUE").
    """
    for s in secrets:
        key = s["key"]
        value = s["value"]
        escaped = value.replace("$", "\\$").replace("`", "\\`").replace('"', '\\"').replace("\\", "\\\\")

        if shell == "pwsh":
            print(f'$env:{key} = "{escaped}"')
        else:
            print(f'export {key}="{escaped}"')
