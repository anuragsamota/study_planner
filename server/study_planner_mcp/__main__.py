"""Run the server: ``python -m study_planner_mcp [--transport http|stdio]``."""

from __future__ import annotations

import argparse
import os


def main() -> None:
    parser = argparse.ArgumentParser(description="Study Planner MCP server")
    parser.add_argument("--transport", choices=["http", "stdio"], default=os.environ.get("PLANNER_TRANSPORT", "http"))
    parser.add_argument("--host", default=os.environ.get("PLANNER_HOST", "0.0.0.0"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("PLANNER_PORT", "8765")))
    parser.add_argument("--data-dir", default=None, help="Where student data is stored (env PLANNER_DATA_DIR)")
    args = parser.parse_args()
    if args.data_dir:
        os.environ["PLANNER_DATA_DIR"] = args.data_dir

    if args.transport == "stdio":
        from .server import mcp

        mcp.run("stdio")
        return

    import uvicorn

    from .http_app import create_app

    if args.host not in ("127.0.0.1", "localhost") and not os.environ.get("PLANNER_API_TOKEN"):
        print("WARNING: listening on", args.host, "without PLANNER_API_TOKEN – anyone on the network can access it.")
    uvicorn.run(create_app(), host=args.host, port=args.port)


if __name__ == "__main__":
    main()
