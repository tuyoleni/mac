#!/usr/bin/env python3
"""ws-mcp: a small, read-only MCP server so any AI tool can ask which workspace
a folder belongs to. It only calls `ws which`, `ws list` and `ws status`.
Standard library only; speaks MCP over stdio (one JSON message per line)."""
import json
import os
import shutil
import subprocess
import sys

NAME, VERSION = "ws", "0.1.0"


def ws_bin():
    for c in (os.environ.get("WS_BIN"), os.path.expanduser("~/.local/bin/ws"), shutil.which("ws")):
        if c and os.path.exists(c):
            return c
    return None


def run(*args):
    b = ws_bin()
    if not b:
        return "ws is not installed", True
    try:
        p = subprocess.run([b, *args], capture_output=True, text=True, timeout=20)
    except Exception as e:  # noqa: BLE001
        return f"ws failed: {e}", True
    out = (p.stdout + p.stderr).strip()
    return out or "(no output)", False


def t_for_path(a):
    path = os.path.expanduser(a.get("path") or os.getcwd())
    out, err = run("which", path)
    return out, err


def t_list(_):
    return run("list")


def t_status(_):
    return run("status")


TOOLS = {
    "workspace_for_path": (
        "Which workspace owns a folder or file? Returns the workspace name and its root, "
        "or '(no workspace)'. Git identity, SSH key and CLI logins follow the workspace automatically.",
        {"type": "object", "properties": {"path": {"type": "string", "description": "Absolute path (default: server cwd)"}}},
        t_for_path,
    ),
    "workspace_list": ("List all workspaces and their folders.", {"type": "object", "properties": {}}, t_list),
    "workspace_status": (
        "Table of workspaces: folder, git email, which logins exist (gh, convex, vercel, gcloud), project count.",
        {"type": "object", "properties": {}},
        t_status,
    ),
}


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def reply(mid, result):
    send({"jsonrpc": "2.0", "id": mid, "result": result})


def fail(mid, code, msg):
    send({"jsonrpc": "2.0", "id": mid, "error": {"code": code, "message": msg}})


def handle(msg):
    method, mid = msg.get("method"), msg.get("id")
    if method == "initialize":
        want = (msg.get("params") or {}).get("protocolVersion", "2024-11-05")
        reply(mid, {
            "protocolVersion": want,
            "capabilities": {"tools": {}},
            "serverInfo": {"name": NAME, "version": VERSION},
        })
    elif method == "ping":
        reply(mid, {})
    elif method == "tools/list":
        reply(mid, {"tools": [
            {"name": n, "description": d, "inputSchema": s, "annotations": {"readOnlyHint": True}}
            for n, (d, s, _) in TOOLS.items()
        ]})
    elif method == "tools/call":
        p = msg.get("params") or {}
        tool = TOOLS.get(p.get("name"))
        if not tool:
            fail(mid, -32602, f"unknown tool: {p.get('name')}")
            return
        text, is_err = tool[2](p.get("arguments") or {})
        reply(mid, {"content": [{"type": "text", "text": text}], "isError": is_err})
    elif mid is not None:  # unknown request; notifications (no id) are ignored
        fail(mid, -32601, f"method not found: {method}")


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            handle(json.loads(line))
        except json.JSONDecodeError:
            send({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "parse error"}})
        except Exception as e:  # noqa: BLE001
            sys.stderr.write(f"ws-mcp error: {e}\n")


if __name__ == "__main__":
    main()
