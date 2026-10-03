"""End-to-end over Streamable HTTP, using the same raw JSON-RPC the Flutter client sends."""

import json
import socket
import threading
import time

import httpx
import pytest
import uvicorn

from study_planner_mcp.http_app import create_app


@pytest.fixture(scope="module")
def base_url():
    # FastMCP's session manager can only be started once per process.
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    server = uvicorn.Server(uvicorn.Config(create_app(token="secret"), host="127.0.0.1", port=port, log_level="warning"))
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()
    for _ in range(100):
        if server.started:
            break
        time.sleep(0.05)
    yield f"http://127.0.0.1:{port}"
    server.should_exit = True
    thread.join(5)


HEADERS = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json", "Authorization": "Bearer secret"}


def rpc(url, method, params=None, id_=1):
    r = httpx.post(f"{url}/mcp", headers=HEADERS, json={"jsonrpc": "2.0", "id": id_, "method": method, "params": params or {}})
    r.raise_for_status()
    return r.json()


def test_health_and_auth(base_url):
    assert httpx.get(f"{base_url}/health").json()["auth_required"] is True
    r = httpx.post(f"{base_url}/mcp", json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
    assert r.status_code == 401


def test_jsonrpc_flow(base_url):
    init = rpc(base_url, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "t", "version": "1"}})
    assert init["result"]["serverInfo"]["name"] == "study-planner"
    tools = {t["name"]: t for t in rpc(base_url, "tools/list")["result"]["tools"]}
    assert {"auto_plan", "add_task", "get_analytics", "sync_push"} <= set(tools)
    assert "student_id" in tools["add_task"]["inputSchema"]["properties"]

    res = rpc(base_url, "tools/call", {"name": "add_subject", "arguments": {"name": "Physics", "student_id": "s1"}})
    assert not res["result"].get("isError")
    res = rpc(base_url, "tools/call", {"name": "add_task", "arguments": {"title": "Lab", "subject": "Nope", "student_id": "s1"}})
    assert res["result"]["isError"] is True
    res = rpc(base_url, "tools/call", {"name": "list_subjects", "arguments": {"student_id": "s1"}})
    assert "Physics" in json.dumps(res["result"])
