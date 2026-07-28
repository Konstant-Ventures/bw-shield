"""
Cross-platform GUI password dialog for Secret Gate.

On Windows: uses tkinter (built-in).
On Linux desktops: uses zenity when available.
On macOS and headless Unix: falls back to stdin-based secure input.
"""

import sys
from typing import Optional


def password_dialog(title: str = "secret-gate") -> str:
    """
    Show a password dialog and return the entered password.

    On Windows, uses a tkinter GUI dialog that works even in
    NonInteractive shells (AI agents, CI runners, scheduled tasks).

    On Linux desktops, prefers a visible zenity dialog so authentication
    launched by an AI agent is not trapped in a hidden subprocess terminal.
    Other platforms fall back to getpass.

    Returns:
        The entered password as a string.

    Raises:
        RuntimeError: If the dialog is cancelled or fails.
    """
    if sys.platform == "win32":
        return _windows_gui_dialog(title)
    if sys.platform.startswith("linux"):
        password = _linux_gui_dialog(title)
        if password is not None:
            return password
    return _unix_secure_input(title)


def _linux_gui_dialog(title: str) -> Optional[str]:
    """Show a zenity password dialog when a Linux desktop is available."""
    import os
    import shutil
    import subprocess

    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        return None
    zenity = shutil.which("zenity")
    if not zenity:
        return None

    result = subprocess.run(
        [
            zenity,
            "--password",
            f"--title={title} — Bitwarden authentication",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError("Authentication cancelled or GUI dialog failed.")

    password = result.stdout.rstrip("\r\n")
    if not password:
        raise RuntimeError("No password entered.")
    return password


def _windows_gui_dialog(title: str) -> str:
    """Show a tkinter GUI password dialog on Windows."""
    import subprocess
    import tempfile
    import os

    # We spawn a separate python process with tkinter to avoid
    # issues with the main process's event loop / terminal state.
    dialog_code = f'''
import tkinter as tk
from tkinter import messagebox
import sys
import os

root = tk.Tk()
root.title("{title}")
root.resizable(False, False)

# Center the window
root.geometry("360x140")
root.eval("tk::PlaceWindow . center")

frame = tk.Frame(root, padx=12, pady=12)
frame.pack(fill="both", expand=True)

label = tk.Label(frame, text="Enter your Bitwarden master password:")
label.pack(anchor="w")

password_var = tk.StringVar()
entry = tk.Entry(frame, textvariable=password_var, show="*", width=40)
entry.pack(fill="x", pady=(4, 8))
entry.focus_set()

result = {{"password": None}}

def on_ok():
    result["password"] = password_var.get()
    root.destroy()

def on_cancel():
    root.destroy()

def on_enter(event):
    on_ok()

button_frame = tk.Frame(frame)
button_frame.pack(fill="x")

ok_btn = tk.Button(button_frame, text="OK", command=on_ok, width=10)
ok_btn.pack(side="left", padx=(0, 6))

cancel_btn = tk.Button(button_frame, text="Cancel", command=on_cancel, width=10)
cancel_btn.pack(side="left")

root.bind("<Return>", on_enter)
root.protocol("WM_DELETE_WINDOW", on_cancel)

root.mainloop()

if result["password"] is not None:
    # Write password to a temp file to avoid command-line leakage
    out_path = os.environ.get("SECRET_GATE_OUTPUT")
    if out_path:
        with open(out_path, "w") as f:
            f.write(result["password"])
    else:
        print(result["password"])
else:
    sys.exit(1)
'''

    # Write dialog code to a temp file and execute it
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".py", delete=False, encoding="utf-8"
    ) as tmp:
        tmp_path = tmp.name
        tmp.write(dialog_code)

    # Use another temp file to capture the password (avoids command-line leakage)
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".txt", delete=False, encoding="utf-8"
    ) as pw_file:
        pw_path = pw_file.name

    try:
        env = os.environ.copy()
        env["SECRET_GATE_OUTPUT"] = pw_path

        result = subprocess.run(
            [sys.executable, tmp_path],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )

        if result.returncode != 0:
            raise RuntimeError(
                "Authentication cancelled or GUI dialog failed."
            )

        with open(pw_path, "r") as f:
            password = f.read().strip()

        if not password:
            raise RuntimeError("No password entered.")

        return password
    finally:
        # Clean up temp files
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        try:
            os.unlink(pw_path)
        except OSError:
            pass


def _unix_secure_input(title: str) -> str:
    """Use getpass for secure password input on Unix systems."""
    import getpass

    try:
        password = getpass.getpass(f"{title}: ")
        if not password:
            raise RuntimeError("No password entered.")
        return password
    except (EOFError, KeyboardInterrupt):
        raise RuntimeError("Authentication cancelled.")
