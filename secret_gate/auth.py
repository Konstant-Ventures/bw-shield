"""
Authentication module — Bitwarden unlock and session management.
"""

from __future__ import annotations

import json
from typing import Dict, Any, Optional

from secret_gate import run, load_session, save_session, is_session_valid
from secret_gate.gui import password_dialog


def authenticate(
    password: Optional[str] = None,
    password_file: Optional[str] = None,
) -> Dict[str, Any]:
    """Authenticate to Bitwarden and return session credentials.

    Tries cached session first. If expired or absent, unlocks the vault
    via GUI dialog, direct password, or password file.

    Returns:
        {"success": bool, "bw_session": str|None, "bws_token": str|None, "message": str}
    """
    # 1. Try cached session
    if is_session_valid():
        session = load_session()
        return {
            "success": True,
            "bw_session": session.get("BW_SESSION"),
            "bws_token": session.get("BWS_ACCESS_TOKEN"),
            "message": "Authenticated from cache",
        }

    # 2. Check Bitwarden login status
    rc, stdout, stderr = run(["bw", "status", "--raw"])
    if rc != 0:
        return {
            "success": False,
            "bw_session": None,
            "bws_token": None,
            "message": "Not logged in to Bitwarden. Run 'bw login' first.",
        }

    try:
        status = json.loads(stdout.strip())
    except json.JSONDecodeError:
        return {
            "success": False,
            "bw_session": None,
            "bws_token": None,
            "message": "Failed to parse Bitwarden status.",
        }

    if status.get("status") == "unauthenticated":
        return {
            "success": False,
            "bw_session": None,
            "bws_token": None,
            "message": "Not logged in to Bitwarden. Run 'bw login' first.",
        }

    # 3. Obtain master password
    master_password: Optional[str] = password

    if password_file:
        try:
            with open(password_file, "r") as f:
                master_password = f.read().strip()
        except OSError as e:
            return {
                "success": False,
                "bw_session": None,
                "bws_token": None,
                "message": f"Cannot read password file: {e}",
            }

    if not master_password:
        try:
            master_password = password_dialog()
        except RuntimeError as e:
            return {
                "success": False,
                "bw_session": None,
                "bws_token": None,
                "message": str(e),
            }

    if not master_password:
        return {
            "success": False,
            "bw_session": None,
            "bws_token": None,
            "message": "No password provided.",
        }

    # 4. Unlock vault via stdin (never in process args)
    rc, stdout, stderr = run(["bw", "unlock", "--raw"], input_data=master_password)

    if rc != 0:
        return {
            "success": False,
            "bw_session": None,
            "bws_token": None,
            "message": f"Authentication failed: {stderr.strip() or 'bad password'}",
        }

    bw_session = stdout.strip()
    if not bw_session:
        return {
            "success": False,
            "bw_session": None,
            "bws_token": None,
            "message": "Unlock returned empty session key.",
        }

    # 5. Retrieve BWS access token from vault
    bws_token = _get_bws_token_from_vault(bw_session)

    # 6. Cache session
    save_session(bw_session, bws_token)

    return {
        "success": True,
        "bw_session": bw_session,
        "bws_token": bws_token,
        "message": "Authenticated successfully",
    }


def _get_bws_token_from_vault(bw_session: str) -> Optional[str]:
    """Retrieve the BWS machine-account access token from the Bitwarden vault.

    The token is stored as a custom field in a vault item. We search
    for the item by its configured name and extract the access token field.
    """
    from secret_gate.config import get_config

    config = get_config()

    rc, stdout, stderr = run(
        ["bw", "list", "items", "--search", config["vaultItemName"],
         "--session", bw_session]
    )
    if rc != 0:
        return None

    try:
        items = json.loads(stdout)
    except json.JSONDecodeError:
        return None

    if not items:
        return None

    item = items[0]
    field_name = config.get("accessTokenFieldName", "Access Token")

    for field in item.get("fields", []):
        if field.get("name") == field_name:
            value = field.get("value", "").strip()
            if value and value != "PASTE_TOKEN_HERE":
                return value

    return None
