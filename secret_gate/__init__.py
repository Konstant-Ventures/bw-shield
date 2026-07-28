"""
Secret Gate — Bitwarden authentication and environment variable management.

Zero-dependency Python package. Cross-platform (Windows/macOS/Linux).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Tuple, Optional

__version__ = "1.0.0"

if sys.platform == "win32":
    STATE_DIR = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local")) / "secret-gate"
else:
    STATE_DIR = Path.home() / ".local" / "state" / "secret-gate"

STATE_DIR.mkdir(parents=True, exist_ok=True)
SESSION_FILE = STATE_DIR / "session.json"


def run(cmd: list[str], input_data: Optional[str] = None) -> Tuple[int, str, str]:
    """Run a subprocess command and return (returncode, stdout, stderr).

    Uses shell=True on Windows because npm-installed CLIs (bw, bws)
    are .cmd scripts that subprocess can't resolve without a shell.
    """
    try:
        result = subprocess.run(
            cmd if sys.platform != "win32" else " ".join(cmd),
            capture_output=True,
            input=input_data,
            text=True,
            check=False,
            shell=(sys.platform == "win32"),
        )
        return result.returncode, result.stdout, result.stderr
    except Exception as e:
        return -1, "", str(e)


def load_session() -> dict[str, str]:
    """Load cached session from disk. Returns empty dict if not found."""
    if SESSION_FILE.exists():
        try:
            with open(SESSION_FILE, "r") as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {}


def save_session(bw_session: str, bws_token: Optional[str] = None) -> None:
    """Save session credentials to disk cache."""
    data = {"BW_SESSION": bw_session}
    if bws_token:
        data["BWS_ACCESS_TOKEN"] = bws_token
    with open(SESSION_FILE, "w") as f:
        json.dump(data, f)


def is_session_valid() -> bool:
    """Check whether the cached Bitwarden session is still unlocked."""
    session = load_session()
    bw_session = session.get("BW_SESSION")
    if not bw_session:
        return False

    rc, stdout, _ = run(["bw", "status", "--session", bw_session, "--raw"])
    if rc != 0:
        return False
    try:
        status = json.loads(stdout.strip())
        return status.get("status") == "unlocked"
    except (json.JSONDecodeError, AttributeError):
        return False
