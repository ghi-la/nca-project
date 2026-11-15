MCP Apps: each tool's renderer resource is a full copy of the same bundled page — N tools = N downloads of the same 6.6 MB
### Summary

With FastMCP 4.0.11's MCP Apps support, every tool that carries a `PrefabAppConfig` gets its own renderer resource at a per-tool URI (`ui://prefab/tool/<hash>/renderer.html`, where `<hash>` derives from the tool name — `fastmcp/server/providers/prefab_synthesis.py::hash_tool` in the installed 4.0.11). The page itself is identical for every tool: `get_renderer_html(mode="bundled")` is ~6.6 MB.

A client that opens views for K different tools downloads the same 6.6 MB bundle K times, because the URIs differ and there is no HTTP-level caching inside the JSON-RPC-over-POST transport. In our server (44 tools, 6 with views) a user touring the views pulls ~40 MB before the second view is even on screen.

### Observed behaviour

- `resources/list` is fine: `Resource.to_mcp_resource()` carries only name/uri/description/mime (verified in 4.0.11, `fastmcp/resources/base.py:457`) — no text on the wire for listings.
- `resources/read` of each tool's renderer URI returns the full 6.6 MB text.
- The text is byte-identical across tools (we patch one bug in it and serve the same string for every tool via `model_copy(update={"text": ...})`).

### Expected behaviour

One canonical renderer URI (e.g. `ui://prefab/renderer.html`), with each tool's `_meta.ui` pointing at the shared page. Tool-specific state already travels separately (the Prefab app JSON), so nothing else needs to vary per tool.

### Why this matters

- First-view latency per tool is dominated by a 6.6 MB transfer.
- The identical payload is re-fetched across tools within one session.
- Anyone serving patched or large renderers (as we do for a Prefab redraw-loop fix) multiplies the cost by the number of view tools.

### Reproduction

1. Serve a FastMCP server with ≥2 tools created from `PrefabAppConfig` (any PrefabApp).
2. Connect a client that supports MCP Apps; open the view of tool A, then tool B.
3. Observe two `resources/read` calls, each returning the same 6.6 MB page under different URIs.

### Environment

- fastmcp 4.0.11 (pinned; verified against the installed distribution), mcp SDK 2.x, Python 3.13, streamable-HTTP transport, Claude Desktop / mcp-remote as client.

*Cross-check request: we could not confirm against current `main` (the package layout was not obvious from the tree) — if this has already changed on main, happy to close.*
