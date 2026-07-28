"""
Configuration management — merge defaults with CLI args and env vars.
The built-in defaults are embedded as a Python constant so the package
works after pip install without an external config file.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Dict, Any


_BUILTIN_DEFAULTS: Dict[str, Any] = {
    "serverUrl": "https://vault.bitwarden.eu",
    "vaultItemName": "Bitwarden SM - ops-bootstrap Access Token",
    "accessTokenFieldName": "Access Token",
    "sets": {
        "all": "*",
        "ci": ["CONDUCTOR_MCP_AUTH_TOKEN"],
        "inbox-agent": [
            "INBOX_TELEGRAM_BOT_TOKEN",
            "INBOX_OWNER_USER_ID",
            "INBOX_TELEGRAM_GROUP_CHAT_ID",
            "INBOX_GOOGLE_CLIENT_ID",
            "INBOX_GOOGLE_CLIENT_SECRET",
            "AI_WRITING_COPILOT_OPENCODE_API_KEY",
        ],
    },
}


def get_config(cli_args: Dict[str, Any] | None = None) -> Dict[str, Any]:
    """Build the effective configuration by merging, in order:

    1. Built-in defaults (embedded in code)
    2. config/defaults.json in the project root (dev mode)
    3. Environment variables
    4. CLI arguments (highest priority)

    Args:
        cli_args: Dictionary of command-line arguments (e.g. from vars(args)).

    Returns:
        Merged configuration dict.
    """
    cli_args = cli_args or {}
    config = dict(_BUILTIN_DEFAULTS)

    # Try loading a file-based defaults.json (dev mode / custom overrides)
    _script_dir = Path(__file__).parent
    _config_paths = [
        _script_dir.parent / "config" / "defaults.json",
        _script_dir / "config" / "defaults.json",
    ]
    for path in _config_paths:
        if path.exists():
            try:
                with open(path, "r") as f:
                    file_cfg = json.load(f)
                config.update(file_cfg)
                break
            except (json.JSONDecodeError, OSError):
                pass

    # Environment overrides
    if os.environ.get("BW_SERVER_URL"):
        config["serverUrl"] = os.environ["BW_SERVER_URL"]

    # CLI overrides (highest priority)
    for key, cli_key in [
        ("serverUrl", "server_url"),
        ("vaultItemName", "vault_item_name"),
        ("accessTokenFieldName", "access_token_field_name"),
    ]:
        if cli_args.get(cli_key):
            config[key] = cli_args[cli_key]

    return config
