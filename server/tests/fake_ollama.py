"""A scripted stand-in for Ollama, for end-to-end tests without a GPU.

    python tests/fake_ollama.py --port 11500

/api/tags lists one model. /api/chat: when tools are offered and no tool
result is in the conversation yet, it asks for `add_task` + `auto_plan`;
afterwards it answers with a short summary. Without tools it just echoes.
"""

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def _send(self, body):
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  # noqa: N802
        if self.path == "/api/tags":
            return self._send({"models": [{"name": "fake-model:latest"}]})
        self.send_error(404)

    def do_POST(self):  # noqa: N802
        req = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        messages = req.get("messages", [])
        tool_results = [m for m in messages if m.get("role") == "tool"]
        if req.get("tools") and not tool_results:
            msg = {
                "role": "assistant",
                "content": "",
                "tool_calls": [
                    {"function": {"name": "add_task", "arguments": {
                        "title": "Maths test prep", "subject": "Maths", "due": "2099-01-09",
                        "type": "exam", "priority": 3, "estimated_minutes": 120}}},
                    {"function": {"name": "auto_plan", "arguments": {"days": 7}}},
                ],
            }
        elif tool_results:
            msg = {"role": "assistant", "content": f"Done – I used {len(tool_results)} tools and updated your plan."}
        else:
            msg = {"role": "assistant", "content": "Echo: " + messages[-1]["content"]}
        self._send({"model": req.get("model"), "message": msg, "done": True})

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=11500)
    args = parser.parse_args()
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
