"""HTTP deployment: MCP over Streamable HTTP at ``/mcp`` plus ``/health``.

Adds CORS (so the Flutter web build can connect) and optional bearer-token
auth via ``PLANNER_API_TOKEN`` – set it whenever the server is reachable
from a LAN or the internet.
"""

from __future__ import annotations

import hmac
import os

from starlette.applications import Starlette
from starlette.middleware.cors import CORSMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Route
from starlette.types import ASGIApp, Receive, Scope, Send

from . import __version__
from .server import mcp


class BearerAuth:
    def __init__(self, app: ASGIApp, token: str | None):
        self.app = app
        self.token = token

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if (
            self.token
            and scope["type"] == "http"
            and scope["path"].startswith(mcp.settings.streamable_http_path)
            and scope["method"] != "OPTIONS"
        ):
            header = dict(scope["headers"]).get(b"authorization", b"").decode()
            supplied = header[7:] if header.lower().startswith("bearer ") else ""
            if not hmac.compare_digest(supplied, self.token):
                await JSONResponse({"error": "unauthorized"}, status_code=401)(scope, receive, send)
                return
        await self.app(scope, receive, send)


async def health(request: Request) -> JSONResponse:
    return JSONResponse(
        {
            "status": "ok",
            "name": "study-planner",
            "version": __version__,
            "mcp_path": mcp.settings.streamable_http_path,
            "auth_required": bool(request.app.state.auth_token),
        }
    )


def create_app(token: str | None = None) -> Starlette:
    token = token if token is not None else os.environ.get("PLANNER_API_TOKEN")
    app = mcp.streamable_http_app()
    app.state.auth_token = token
    app.router.routes.append(Route("/health", health))
    app.add_middleware(BearerAuth, token=token)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=os.environ.get("PLANNER_CORS_ORIGINS", "*").split(","),
        allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
        allow_headers=["*"],
        expose_headers=["Mcp-Session-Id"],
    )
    return app
