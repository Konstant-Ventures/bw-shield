"""
Secret Gate CLI — entry point.

The agent runs these commands; the user responds to the GUI dialog.

  secret-gate auth          Open GUI password dialog → caches session
  secret-gate refresh       Pull ALL BWS secrets → export as env vars
  secret-gate refresh -s ci Only secrets in the "ci" set
  secret-gate refresh -k FOO,BAR  Only these specific keys
  secret-gate status        Check if session is valid

For shell sourcing (sets env vars in parent shell):
  eval $(secret-gate refresh --print-env)

For OpenCode MCP:
  eval $(secret-gate refresh -s ci --print-env)
  opencode
"""

from __future__ import annotations

import argparse
import os
import sys

from secret_gate import is_session_valid, load_session, save_session, SESSION_FILE
from secret_gate.auth import authenticate
from secret_gate.config import get_config
from secret_gate.refresh import (
    get_all_secrets,
    filter_secrets,
    export_secrets,
    print_export_lines,
    refresh_session,
)


def cmd_auth(args: argparse.Namespace) -> None:
    """Handle the `auth` subcommand."""
    result = authenticate(
        password=args.password,
        password_file=args.password_file,
    )

    if not result["success"]:
        print(f"ERROR: {result['message']}", file=sys.stderr)
        sys.exit(1)

    print(f"[OK] {result['message']}")
    bw_len = len(result.get("bw_session") or "")
    bws_len = len(result.get("bws_token") or "")
    print(f"     BW_SESSION        = {bw_len} chars")
    print(f"     BWS_ACCESS_TOKEN   = {bws_len} chars")
    print(f"     Cache              = {SESSION_FILE}")


def cmd_refresh(args: argparse.Namespace) -> None:
    """Handle the `refresh` subcommand."""
    if not is_session_valid():
        loaded = refresh_session()
        if not loaded:
            print("ERROR: Not authenticated. Run 'secret-gate auth' first.", file=sys.stderr)
            sys.exit(1)

    config = get_config(vars(args) if args else {})

    secrets = get_all_secrets(config)
    if not secrets:
        print("No secrets found in Bitwarden Secrets Manager.", file=sys.stderr)
        sys.exit(1)

    # Filter by set or keys
    keys_list = None
    if args.keys:
        keys_list = [k.strip() for k in args.keys.split(",")]

    filtered = filter_secrets(
        secrets,
        set_name=args.set,
        keys=keys_list,
        config=config,
    )

    if not filtered:
        print("No secrets matched the filter criteria.", file=sys.stderr)
        sys.exit(0)

    # Export to environment
    exported = export_secrets(filtered)

    # When --print-env: status → stderr, export lines → stdout
    if getattr(args, "print_env", False):
        print(f"[OK] Exported {len(exported)} environment variable(s)", file=sys.stderr)
        for var in sorted(exported)[:10]:
            val = os.environ.get(var, "")
            print(f"     {var} ({len(val)} chars)", file=sys.stderr)
        if len(exported) > 10:
            print(f"     ... and {len(exported) - 10} more", file=sys.stderr)
        print_export_lines(filtered, shell=args.shell)
    else:
        print(f"[OK] Exported {len(exported)} environment variable(s)")
        for var in sorted(exported)[:10]:
            val = os.environ.get(var, "")
            preview = f"{val[:40]}..." if len(val) > 40 else val
            print(f"     {var}={preview}")
        if len(exported) > 10:
            print(f"     ... and {len(exported) - 10} more")


def cmd_status() -> None:
    """Handle the `status` subcommand."""
    if is_session_valid():
        session = load_session()
        bw = len(session.get("BW_SESSION") or "")
        bws = len(session.get("BWS_ACCESS_TOKEN") or "")
        print(f"Status: authenticated")
        print(f"        BW_SESSION       = {bw} chars")
        print(f"        BWS_ACCESS_TOKEN  = {bws} chars")
        print(f"        Cache             = {SESSION_FILE}")
    else:
        print("Status: NOT authenticated (session expired or missing)")
        print("        Run: secret-gate auth")


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="secret-gate",
        description="Secure Bitwarden authentication and environment variable management.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # auth
    auth_p = sub.add_parser("auth", help="Authenticate to Bitwarden")
    auth_p.add_argument("-p", "--password", help="Direct password (not recommended)")
    auth_p.add_argument("--password-file", help="Read password from file")

    # refresh
    ref_p = sub.add_parser("refresh", help="Refresh env vars from BWS secrets")
    ref_p.add_argument("-s", "--set", help="Named secret set to export")
    ref_p.add_argument("-k", "--keys", help="Comma-separated secret keys to export")
    ref_p.add_argument("--print-env", action="store_true", help="Output export lines for shell sourcing")
    ref_p.add_argument("--shell", choices=["bash", "pwsh"], default="bash", help="Shell format for --print-env (default: bash)")

    # status
    sub.add_parser("status", help="Check authentication status")

    args = parser.parse_args()

    if args.command == "auth":
        cmd_auth(args)
    elif args.command == "refresh":
        cmd_refresh(args)
    elif args.command == "status":
        cmd_status()


if __name__ == "__main__":
    main()
