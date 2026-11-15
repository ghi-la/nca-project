MCPServer has no x-mcp-header declaration mechanism and never validates one, so an invalid annotation is served happily and dropped by every client
### Summary

`MCPServer` offers no way to mark a tool parameter with `x-mcp-header`, and does not validate the annotation when one is smuggled in through pydantic. A server author who gets it wrong gets no signal at all: the tool is served happily, and every conforming client silently drops it.

SEP-2243's *Reference Implementation* section names this as a server-SDK requirement:

> * **Server SDKs**: Provide a mechanism (attribute/decorator) for marking parameters with `x-mcp-header`
> * **Client SDKs**: Implement the client behavior for extracting and encoding header values
> * **Validation**: Both sides must validate header/body consistency

The client half is implemented. The server half is not: `x-mcp-header` appears in `mcp/client/session.py`, `mcp/shared/inbound.py` and `mcp_types/_v2026_07_28/`, and **nowhere under `mcp/server/`**.

### 1. No declaration mechanism

The only route is pydantic passthrough:

```python
@server.tool()
async def fetch(
    owner: Annotated[str, Field(json_schema_extra={"x-mcp-header": "owner"})],
) -> str:
    ...
```

This works — the annotation reaches `inputSchema`, the client mirrors it, `mcp/shared/inbound.py` validates it — so this is an ergonomics and discoverability gap rather than a functional one. But it means the feature is invisible from the server API, and that a server author must know the extension keyword's exact spelling from the spec.

### 2. Nothing validates the declaration server-side

This is the part that fails silently. SEP-2243 puts type restrictions on `x-mcp-header` and assigns their enforcement to the server:

> | Test Case | Property Type | x-mcp-header Present | Expected Behavior |
> | Array type | `"type": "array"` | Yes | **Server MUST reject tool definition** |
> | Object type | `"type": "object"` | Yes | **Server MUST reject tool definition** |
> | Null type | `"type": "null"` | Yes | **Server MUST reject tool definition** |

`MCPServer` rejects none of them.

```python
import anyio
from typing import Annotated
from pydantic import Field
from mcp.client import Client
from mcp.client._memory import InMemoryTransport
from mcp.server.mcpserver import MCPServer

server = MCPServer("repro")

@server.tool()
async def bad(
    tags: Annotated[list[str], Field(json_schema_extra={"x-mcp-header": "Tags"})],
) -> str:
    """An array parameter annotated x-mcp-header -- the spec says reject."""
    return "ok"

async def main() -> None:
    async with Client(InMemoryTransport(server), mode="auto") as client:
        print("negotiated:", client.protocol_version)
        result = await client.list_tools()
        print("tools the client kept:", [t.name for t in result.tools])

anyio.run(main)
```

Output on `mcp` 2.1.1:

```
WARNING  dropping tool 'bad': invalid x-mcp-header (property 'tags':
         x-mcp-header is only permitted on integer/string/boolean
         properties (got 'array'))
negotiated: 2026-07-28
tools the client kept: []
```

Registration succeeded, startup succeeded, `tools/list` served it. The client — correctly, per the client-side MUST — drops it. So the failure mode is **a tool that exists on the server and is invisible to every client**, with the only diagnostic emitted in the client's process, which in a real deployment belongs to someone else.

The validator that would catch this already exists and is already imported by the server package's transport: `find_invalid_x_mcp_header` in `mcp/shared/inbound.py`. It is simply never run against a tool the server itself is registering.

### Suggested fixes

1. **Run `find_invalid_x_mcp_header` at tool-registration time** and raise. This is the one that matters: it turns a silent cross-process failure into an error at the line that caused it, and it reuses code that is already there.
2. **A first-class declaration API**, so the extension keyword does not have to be spelled by hand — whatever shape fits the SDK's conventions, e.g. `Annotated[str, McpHeader("Region")]`.

Happy to open a PR for (1) if the direction is agreeable.

### Environment

- `mcp` 2.1.1, `mcp-types` 2.1.1, Python 3.12.9
- Both reproductions negotiate `2026-07-28`

