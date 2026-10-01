"""lowey-mcp over HTTP on this laptop only, for MCP clients that speak streamable HTTP instead of stdio.

  lowey-mcp --http              http://127.0.0.1:8765/mcp (localhost only)

There is no internet mode: the iPad's bridge is local-network only and pairs each laptop with a one-time code, and this
server listens on 127.0.0.1 with the SDK's DNS-rebinding protection on. Every change is still approved on the iPad.
"""
from __future__ import annotations

DEFAULT_HTTP_PORT = 8765
LOCALHOST = "127.0.0.1"


def url(port: int = DEFAULT_HTTP_PORT) -> str:
    return f"http://{LOCALHOST}:{port}/mcp"


def serve(mcp, *, port: int = DEFAULT_HTTP_PORT) -> None:
    import anyio

    print(f"  Local MCP URL:  {url(port)}", flush=True)
    try:
        # No transport_security argument: the SDK turns DNS-rebinding protection on for 127.0.0.1.
        anyio.run(lambda: mcp.run_streamable_http_async(host=LOCALHOST, port=port, streamable_http_path="/mcp", stateless_http=True))
    except KeyboardInterrupt:
        pass
