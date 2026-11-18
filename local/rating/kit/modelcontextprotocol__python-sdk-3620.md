# modelcontextprotocol__python-sdk-3620

- repo: `modelcontextprotocol/python-sdk`, created: 2026-10-02, base_commit: `c8fcfc8d7faa`
- PR: https://github.com/modelcontextprotocol/python-sdk/pull/3620
- issue: https://github.com/modelcontextprotocol/python-sdk/issues/3484
- FAIL_TO_PASS: 14 tests, PASS_TO_PASS: 26 tests, collection_error: **yes**

## 1. Issue (what the agent sees)

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

## 2. Gold patch

```diff
diff --git a/docs/advanced/header-parameters.md b/docs/advanced/header-parameters.md
new file mode 100644
index 0000000000..a47be2f874
--- /dev/null
+++ b/docs/advanced/header-parameters.md
@@ -0,0 +1,47 @@
+# Header parameters
+
+Most servers never need this.
+
+A gateway or load balancer in front of your server can only route on what it can read without parsing the body. Mark a tool argument with `x-mcp-header`, and clients on the `2026-07-28` **[protocol version](../protocol-versions.md)** send its value as an HTTP header as well.
+
+## Mark an argument
+
+The mark is one extra key in the argument's JSON Schema. On `MCPServer`, `Field` puts it there:
+
+```python title="server.py" hl_lines="13"
+--8<-- "docs_src/header_parameters/tutorial001.py"
+```
+
+* Over Streamable HTTP on `2026-07-28`, a client that has listed the tool sends `Mcp-Param-Region` alongside the body, and the server rejects a call where the two disagree.
+* Every other connection ignores the annotation.
+
+Your function doesn't change: `region` still arrives as an argument.
+
+## What can be marked
+
+`str`, `int` and `bool` arguments. Anything else is refused when the tool is registered, with `InvalidSignature`.
+
+That includes `str | None`, which has no single type. An optional argument needs its schema spelled out, with pydantic's `WithJsonSchema`:
+
+```python
+region: Annotated[str | None, WithJsonSchema({"type": "string", "x-mcp-header": "Region"})] = None
+```
+
+## On the low-level `Server`
+
+There you write `input_schema` by hand, so the key goes straight in:
+
+```python title="server.py" hl_lines="18"
+--8<-- "docs_src/header_parameters/tutorial002.py"
+```
+
+* Nothing checks the annotation for you: an invalid one is served, and `2026-07-28` clients leave the tool out of their listing.
+
+## Recap
+
+* `x-mcp-header` on a tool argument makes `2026-07-28` clients repeat it as an `Mcp-Param-*` HTTP header.
+* The server rejects a call whose header and body disagree.
+* Only `str`, `int` and `bool` arguments can be marked. `MCPServer` raises `InvalidSignature` for anything else.
+* The low-level `Server` checks nothing, and clients drop a tool whose annotation is invalid.
+
+The rest of the hand-written `Server` API is **[The low-level Server](low-level-server.md)**.
diff --git a/docs/advanced/index.md b/docs/advanced/index.md
index 92af6d1782..057924efd2 100644
--- a/docs/advanced/index.md
+++ b/docs/advanced/index.md
@@ -9,6 +9,8 @@ layer is in the way:
   methods of your own.
 * **[Pagination](pagination.md)** and **[Middleware](middleware.md)**: two things you
   can *only* do on the low-level `Server`.
+* **[Header parameters](header-parameters.md)**: let a gateway route a tool call on one
+  of its arguments.
 * **[Extensions](extensions.md)** and **[MCP Apps](apps.md)**: the protocol's
   extension surface. Compose extension packages into a server, or write your own.
 
diff --git a/docs/troubleshooting.md b/docs/troubleshooting.md
index bb7dfda4f9..e23b5b16e1 100644
--- a/docs/troubleshooting.md
+++ b/docs/troubleshooting.md
@@ -123,6 +123,14 @@ Add the parentheses. `@mcp.resource(...)` and `@mcp.prompt()` say the same thing
     tools, has this shape: run `python server.py` yourself and read the traceback. A type checker
     also catches it: a function is not a valid `name=`.
 
+## `InvalidSignature: Tool '<name>' has an invalid x-mcp-header annotation: <reason>`
+
+A tool argument is marked with `x-mcp-header` in a way the spec doesn't allow, and `<reason>` says which rule it breaks. Clients on `2026-07-28` would leave such a tool out of their listing, so the SDK refuses to register it.
+
+Only `str`, `int` and `bool` arguments can be marked, and `str | None` is none of them. **[Header parameters](advanced/header-parameters.md)** has the spelling for an optional argument.
+
+Like the entry above, this raises when the module is **imported**, before any client connects.
+
 ## `Tool already exists: <name>`
 
 Two registrations used the same tool name. The **first** one wins, the second is silently dropped, and this warning in the *server log* is the only signal:
@@ -420,6 +428,7 @@ mcp = MCPServer("Weather", request_state_security=RequestStateSecurity(keys=[key
 * `ExceptionGroup: unhandled errors in a TaskGroup` is never the error. Read the **last line**; catching `MCPError` *inside* the `async with Client(...)` block skips the wrapping entirely.
 * `call_tool` does not raise for a failing tool. `Error executing tool ...` and `Unknown tool: ...` are results: check `result.is_error`. No message after the tool name means it crashed, and the traceback is in the server log.
 * `Client must be used within an async context manager` -> use `async with`. `Use @tool() instead of @tool` -> add the parentheses.
+* `has an invalid x-mcp-header annotation` -> only `str`, `int` and `bool` arguments can be marked.
 * `Tool already exists:` in the server log is the only sign that two same-named tools collapsed into one.
 * One 421, three spellings: `Server returned an error response` (the python `Client`), `421 Misdirected Request` / `Invalid Host header` (everything else), `Invalid Host header: <host>` (the server log). Fix: `transport_security=TransportSecuritySettings(allowed_hosts=[...])`.
 * `Task group is not initialized` -> a mounted app whose host lifespan never entered `mcp.session_manager.run()`.
diff --git a/docs_src/header_parameters/__init__.py b/docs_src/header_parameters/__init__.py
new file mode 100644
index 0000000000..e69de29bb2
diff --git a/docs_src/header_parameters/tutorial001.py b/docs_src/header_parameters/tutorial001.py
new file mode 100644
index 0000000000..c7a5c52ede
--- /dev/null
+++ b/docs_src/header_parameters/tutorial001.py
@@ -0,0 +1,16 @@
+from typing import Annotated
+
+from pydantic import Field
+
+from mcp.server import MCPServer
+
+mcp = MCPServer("Bookshop")
+
+
+@mcp.tool()
+def check_stock(
+    title: str,
+    region: Annotated[str, Field(json_schema_extra={"x-mcp-header": "Region"})],
+) -> str:
+    """Count the copies of a book in one region's warehouses."""
+    return f"{title}: 3 copies in {region}."
diff --git a/docs_src/header_parameters/tutorial002.py b/docs_src/header_parameters/tutorial002.py
new file mode 100644
index 0000000000..147d5234c5
--- /dev/null
+++ b/docs_src/header_parameters/tutorial002.py
@@ -0,0 +1,36 @@
+from mcp.server import Server, ServerRequestContext
+from mcp.types import (
+    CallToolRequestParams,
+    CallToolResult,
+    ListToolsResult,
+    PaginatedRequestParams,
+    TextContent,
+    Tool,
+)
+
+CHECK_STOCK = Tool(
+    name="check_stock",
+    description="Count the copies of a book in one region's warehouses.",
+    input_schema={
+        "type": "object",
+        "properties": {
+            "title": {"type": "string"},
+            "region": {"type": "string", "x-mcp-header": "Region"},
+        },
+        "required": ["title", "region"],
+    },
+)
+
+
+async def list_tools(ctx: ServerRequestContext, params: PaginatedRequestParams | None) -> ListToolsResult:
+    return ListToolsResult(tools=[CHECK_STOCK])
+
+
+async def call_tool(ctx: ServerRequestContext, params: CallToolRequestParams) -> CallToolResult:
+    args = params.arguments or {}
+    text = f"{args['title']}: 3 copies in {args['region']}."
+    return CallToolResult(content=[TextContent(type="text", text=text)])
+
+
+server = Server("Bookshop", on_list_tools=list_tools, on_call_tool=call_tool)
+app = server.streamable_http_app()
diff --git a/mkdocs.yml b/mkdocs.yml
index a75053326f..446e676344 100644
--- a/mkdocs.yml
+++ b/mkdocs.yml
@@ -65,6 +65,7 @@ nav:
       - The low-level Server: advanced/low-level-server.md
       - Pagination: advanced/pagination.md
       - Middleware: advanced/middleware.md
+      - Header parameters: advanced/header-parameters.md
       - Extensions: advanced/extensions.md
       - MCP Apps: advanced/apps.md
   - Troubleshooting: troubleshooting.md
diff --git a/src/mcp/server/mcpserver/tools/base.py b/src/mcp/server/mcpserver/tools/base.py
index 4a8bed792e..787f1761b2 100644
--- a/src/mcp/server/mcpserver/tools/base.py
+++ b/src/mcp/server/mcpserver/tools/base.py
@@ -24,6 +24,7 @@
 from mcp.server.mcpserver.utilities.func_metadata import FuncMetadata, func_metadata
 from mcp.shared._callable_inspection import is_async_callable
 from mcp.shared.exceptions import MCPError
+from mcp.shared.inbound import find_invalid_x_mcp_header
 from mcp.shared.tool_name_validation import validate_and_warn_tool_name
 
 if TYPE_CHECKING:
@@ -104,6 +105,8 @@ def from_function(
             structured_output=structured_output,
         )
         parameters = func_arg_metadata.arg_model.model_json_schema(by_alias=True)
+        if (reason := find_invalid_x_mcp_header(parameters)) is not None:
+            raise InvalidSignature(f"Tool {func_name!r} has an invalid x-mcp-header annotation: {reason}")
 
         # Match `model_dump_one_level`'s kwarg keys (alias when present, else field name)
         # so a by-name resolver param resolves to a key that exists at call time.
```

## 3. Test patch

```diff
diff --git a/tests/docs_src/test_header_parameters.py b/tests/docs_src/test_header_parameters.py
new file mode 100644
index 0000000000..5466dba9d6
--- /dev/null
+++ b/tests/docs_src/test_header_parameters.py
@@ -0,0 +1,142 @@
+"""`docs/advanced/header-parameters.md`: every claim the page makes, proved against the real SDK."""
+
+from collections.abc import AsyncIterator
+from contextlib import asynccontextmanager
+from typing import Annotated, Literal
+
+import httpx2
+import pytest
+from mcp_types import HEADER_MISMATCH, ListToolsResult, PaginatedRequestParams
+from pydantic import Field, WithJsonSchema
+from starlette.applications import Starlette
+
+from docs_src.header_parameters import tutorial001, tutorial002
+from mcp import Client
+from mcp.client.streamable_http import streamable_http_client
+from mcp.server import MCPServer, Server, ServerRequestContext
+from mcp.server.mcpserver.exceptions import InvalidSignature
+
+# See test_index.py for why this is a per-module mark and not a conftest hook.
+pytestmark = [pytest.mark.anyio, pytest.mark.filterwarnings("error::mcp.MCPDeprecationWarning")]
+
+URL = "http://localhost:8000/mcp"
+ARGUMENTS = {"title": "Dune", "region": "eu"}
+
+
+@asynccontextmanager
+async def check_stock_over_http(
+    app: Starlette, mode: Literal["auto", "legacy"] = "auto"
+) -> AsyncIterator[tuple[httpx2.AsyncClient, httpx2.Request]]:
+    """List the tools and call `check_stock` over in-process HTTP; yield the HTTP client and the call's request."""
+    requests: list[httpx2.Request] = []
+
+    async def record(request: httpx2.Request) -> None:
+        requests.append(request)
+
+    async with (
+        app.router.lifespan_context(app),
+        httpx2.ASGITransport(app) as transport,
+        httpx2.AsyncClient(transport=transport, event_hooks={"request": [record]}) as http,
+        Client(streamable_http_client(URL, http_client=http), mode=mode) as client,
+    ):
+        await client.list_tools()
+        result = await client.call_tool("check_stock", ARGUMENTS)
+        assert not result.is_error
+        yield http, next(request for request in requests if b'"tools/call"' in request.content)
+
+
+@pytest.mark.parametrize(
+    "app", [tutorial001.mcp.streamable_http_app(), tutorial002.app], ids=["tutorial001", "tutorial002"]
+)
+async def test_a_2026_http_client_sends_the_marked_argument_as_a_header_as_well(app: Starlette) -> None:
+    """Both tutorials: `region` travels as `Mcp-Param-Region` and stays in the body; `title` is body only."""
+    async with check_stock_over_http(app) as (_, call):
+        assert {k: v for k, v in call.headers.items() if k.startswith("mcp-param-")} == {"mcp-param-region": "eu"}
+        assert b'"region":"eu"' in call.content
+
+
+async def test_a_call_whose_header_and_body_disagree_is_rejected() -> None:
+    """tutorial001: the client's own request, replayed with a different `Mcp-Param-Region`, is a 400."""
+    async with check_stock_over_http(tutorial001.mcp.streamable_http_app()) as (http, call):
+        tampered = await http.post(URL, content=call.content, headers={**call.headers, "mcp-param-region": "us"})
+    assert tampered.status_code == 400
+    assert tampered.json()["error"]["code"] == HEADER_MISMATCH
+
+
+async def test_a_legacy_http_connection_ignores_the_annotation() -> None:
+    """tutorial001: before 2026-07-28 the same call succeeds and carries no `Mcp-Param-*` header."""
+    async with check_stock_over_http(tutorial001.mcp.streamable_http_app(), mode="legacy") as (_, call):
+        assert not [name for name in call.headers if name.startswith("mcp-param-")]
+
+
+async def test_a_connection_that_is_not_http_ignores_the_annotation() -> None:
+    """tutorial001: in memory there are no headers to send, and the call succeeds all the same."""
+    async with Client(tutorial001.mcp) as client:
+        assert client.protocol_version == "2026-07-28"
+        result = await client.call_tool("check_stock", ARGUMENTS)
+    assert result.structured_content == {"result": "Dune: 3 copies in eu."}
+
+
+async def test_int_and_bool_arguments_can_be_marked() -> None:
+    """`str` is tutorial001; `int` and `bool` register too, and a 2026-07-28 client keeps the tool."""
+    mcp = MCPServer("Bookshop")
+
+    @mcp.tool()
+    def reserve(
+        copies: Annotated[int, Field(json_schema_extra={"x-mcp-header": "Copies"})],
+        gift: Annotated[bool, Field(json_schema_extra={"x-mcp-header": "Gift"})],
+    ) -> None:
+        """Never called: registering and listing it is the claim."""
+
+    async with Client(mcp) as client:
+        assert [tool.name for tool in (await client.list_tools()).tools] == ["reserve"]
+
+
+async def test_any_other_type_is_refused_when_the_tool_is_registered() -> None:
+    """A marked `list[str]` raises `InvalidSignature` from the decorator, before any client connects."""
+    mcp = MCPServer("Bookshop")
+    with pytest.raises(InvalidSignature):
+
+        @mcp.tool()
+        def check_stock(regions: Annotated[list[str], Field(json_schema_extra={"x-mcp-header": "Regions"})]) -> None:
+            """Never called: the decoration itself is what raises."""
+
+    assert await mcp.list_tools() == []
+
+
+async def test_a_plain_optional_argument_is_refused_and_the_spelled_out_schema_registers() -> None:
+    """`str | None` has no single `type`, so it is refused; the page's `WithJsonSchema` spelling is kept."""
+    mcp = MCPServer("Bookshop")
+    with pytest.raises(InvalidSignature):
+
+        @mcp.tool()
+        def refused(region: Annotated[str | None, Field(json_schema_extra={"x-mcp-header": "Region"})] = None) -> None:
+            """Never called: the decoration itself is what raises."""
+
+    @mcp.tool()
+    def check_stock(
+        region: Annotated[str | None, WithJsonSchema({"type": "string", "x-mcp-header": "Region"})] = None,
+    ) -> str:
+        """Count the copies of a book in one region's warehouses."""
+        return f"3 copies in {region}."
+
+    async with Client(mcp) as client:
+        assert [tool.name for tool in (await client.list_tools()).tools] == ["check_stock"]
+        result = await client.call_tool("check_stock", {})
+    assert result.structured_content == {"result": "3 copies in None."}
+
+
+async def test_the_low_level_server_serves_an_invalid_annotation_and_a_2026_client_leaves_the_tool_out() -> None:
+    """tutorial002's tool with `region` turned into an array: a legacy client is shown it, a 2026-07-28 one is not."""
+    properties = {"region": {"type": "array", "x-mcp-header": "Region"}}
+    invalid = tutorial002.CHECK_STOCK.model_copy(update={"input_schema": {"type": "object", "properties": properties}})
+
+    async def list_tools(ctx: ServerRequestContext, params: PaginatedRequestParams | None) -> ListToolsResult:
+        return ListToolsResult(tools=[invalid])
+
+    server = Server("Bookshop", on_list_tools=list_tools)
+    async with Client(server, mode="legacy") as legacy:
+        assert [tool.name for tool in (await legacy.list_tools()).tools] == ["check_stock"]
+    async with Client(server) as modern:
+        assert modern.protocol_version == "2026-07-28"
+        assert (await modern.list_tools()).tools == []
diff --git a/tests/docs_src/test_troubleshooting.py b/tests/docs_src/test_troubleshooting.py
index 1e1b5e15b8..e39a78050e 100644
--- a/tests/docs_src/test_troubleshooting.py
+++ b/tests/docs_src/test_troubleshooting.py
@@ -1,10 +1,11 @@
 """`docs/troubleshooting.md`: every error string the page names, reproduced against the real SDK."""
 
 import logging
-from typing import Any
+from typing import Annotated, Any
 
 import httpx2
 import pytest
+from inline_snapshot import snapshot
 from mcp_types import (
     INVALID_PARAMS,
     INVALID_REQUEST,
@@ -14,6 +15,7 @@
     ErrorData,
     TextContent,
 )
+from pydantic import Field
 
 from docs_src.troubleshooting import (
     tutorial001,
@@ -30,6 +32,7 @@
 from mcp.client.streamable_http import streamable_http_client
 from mcp.server import MCPServer
 from mcp.server.mcpserver import RequestStateSecurity
+from mcp.server.mcpserver.exceptions import InvalidSignature
 
 # See test_index.py for why this is a per-module mark and not a conftest hook.
 pytestmark = [pytest.mark.anyio, pytest.mark.filterwarnings("error::mcp.MCPDeprecationWarning")]
@@ -124,6 +127,22 @@ def forecast(city: str) -> None:
             """Today's forecast for one city. Never called: the decoration itself is what raises."""
 
 
+async def test_an_invalid_x_mcp_header_annotation_raises_at_import_time() -> None:
+    """A marked `str | None` is refused by the decorator itself, with the heading's text and the reason after it."""
+    mcp = MCPServer("Weather")
+    with pytest.raises(InvalidSignature) as excinfo:
+
+        @mcp.tool()
+        def forecast(city: Annotated[str | None, Field(json_schema_extra={"x-mcp-header": "City"})] = None) -> None:
+            """Today's forecast for one city. Never called: the decoration itself is what raises."""
+
+    assert str(excinfo.value) == snapshot(
+        "Tool 'forecast' has an invalid x-mcp-header annotation: "
+        "property 'city': x-mcp-header is only permitted on integer/string/boolean properties "
+        "(the type keyword is NoneType, not a string)"
+    )
+
+
 async def test_a_duplicate_tool_name_keeps_the_first_and_drops_the_second() -> None:
     """tutorial002: `tools/list` reports one `forecast`, and it is the first registration that won."""
     async with Client(tutorial002.mcp) as client:
diff --git a/tests/server/mcpserver/tools/test_base.py b/tests/server/mcpserver/tools/test_base.py
index 0cb583028d..5ed47f51d5 100644
--- a/tests/server/mcpserver/tools/test_base.py
+++ b/tests/server/mcpserver/tools/test_base.py
@@ -1,8 +1,14 @@
+from collections.abc import Callable
+from typing import Annotated
+
 import mcp_types as types
 import pytest
+from inline_snapshot import snapshot
+from pydantic import Field
 
 from mcp import Client
 from mcp.server.mcpserver import Context, MCPServer
+from mcp.server.mcpserver.exceptions import InvalidSignature
 from mcp.server.mcpserver.tools.base import Tool
 from mcp.shared.exceptions import MCPError
 
@@ -55,3 +61,89 @@ async def boom() -> str:
 
     assert isinstance(result, types.CallToolResult)
     assert result.is_error is True
+
+
+def array_header(tags: Annotated[list[str], Field(json_schema_extra={"x-mcp-header": "Tags"})]) -> str:
+    raise NotImplementedError
+
+
+def number_header(ratio: Annotated[float, Field(json_schema_extra={"x-mcp-header": "Ratio"})]) -> str:
+    raise NotImplementedError
+
+
+def optional_header(region: Annotated[str | None, Field(json_schema_extra={"x-mcp-header": "Region"})] = None) -> str:
+    raise NotImplementedError
+
+
+def non_token_header(region: Annotated[str, Field(json_schema_extra={"x-mcp-header": "Region Name"})]) -> str:
+    raise NotImplementedError
+
+
+@pytest.mark.anyio
+@pytest.mark.parametrize(
+    ("fn", "message"),
+    [
+        pytest.param(
+            array_header,
+            snapshot(
+                "Tool 'array_header' has an invalid x-mcp-header annotation: "
+                "property 'tags': x-mcp-header is only permitted on integer/string/boolean properties (got 'array')"
+            ),
+            id="array",
+        ),
+        pytest.param(
+            number_header,
+            snapshot(
+                "Tool 'number_header' has an invalid x-mcp-header annotation: "
+                "property 'ratio': x-mcp-header is only permitted on integer/string/boolean properties (got 'number')"
+            ),
+            id="number",
+        ),
+        pytest.param(
+            optional_header,
+            snapshot(
+                "Tool 'optional_header' has an invalid x-mcp-header annotation: "
+                "property 'region': x-mcp-header is only permitted on integer/string/boolean properties "
+                "(the type keyword is NoneType, not a string)"
+            ),
+            id="optional",
+        ),
+        pytest.param(
+            non_token_header,
+            snapshot(
+                "Tool 'non_token_header' has an invalid x-mcp-header annotation: "
+                "property 'region': x-mcp-header 'Region Name' is not an RFC 9110 token"
+            ),
+            id="non-token-name",
+        ),
+    ],
+)
+async def test_tool_with_an_invalid_x_mcp_header_annotation_is_rejected_at_registration(
+    fn: Callable[..., str], message: str
+):
+    """SDK-defined: the spec has 2026-07-28 clients exclude such a tool, so registration
+    refuses it with an error naming the tool and the reason, and nothing is registered."""
+    mcp = MCPServer(name="srv")
+
+    with pytest.raises(InvalidSignature) as exc_info:
+        mcp.add_tool(fn)
+
+    assert str(exc_info.value) == message
+    assert await mcp.list_tools() == []
+
+
+@pytest.mark.anyio
+async def test_tool_with_valid_x_mcp_header_annotations_is_registered():
+    """SDK-defined: string, integer and boolean parameters may carry `x-mcp-header`,
+    so a tool that annotates one of each registers."""
+    mcp = MCPServer(name="srv")
+
+    @mcp.tool()
+    def fetch(
+        region: Annotated[str, Field(json_schema_extra={"x-mcp-header": "Region"})],
+        shard: Annotated[int, Field(json_schema_extra={"x-mcp-header": "Shard"})],
+        dry_run: Annotated[bool, Field(json_schema_extra={"x-mcp-header": "Dry-Run"})],
+    ) -> str:
+        raise NotImplementedError
+
+    assert [tool.name for tool in await mcp.list_tools()] == ["fetch"]
```

## 4. FAIL_TO_PASS tests

- `tests/docs_src/test_header_parameters.py::test_a_2026_http_client_sends_the_marked_argument_as_a_header_as_well[tutorial001]`
- `tests/docs_src/test_header_parameters.py::test_a_2026_http_client_sends_the_marked_argument_as_a_header_as_well[tutorial002]`
- `tests/docs_src/test_header_parameters.py::test_a_call_whose_header_and_body_disagree_is_rejected`
- `tests/docs_src/test_header_parameters.py::test_a_connection_that_is_not_http_ignores_the_annotation`
- `tests/docs_src/test_header_parameters.py::test_a_legacy_http_connection_ignores_the_annotation`
- `tests/docs_src/test_header_parameters.py::test_a_plain_optional_argument_is_refused_and_the_spelled_out_schema_registers`
- `tests/docs_src/test_header_parameters.py::test_any_other_type_is_refused_when_the_tool_is_registered`
- `tests/docs_src/test_header_parameters.py::test_int_and_bool_arguments_can_be_marked`
- `tests/docs_src/test_header_parameters.py::test_the_low_level_server_serves_an_invalid_annotation_and_a_2026_client_leaves_the_tool_out`
- `tests/docs_src/test_troubleshooting.py::test_an_invalid_x_mcp_header_annotation_raises_at_import_time`
- `tests/server/mcpserver/tools/test_base.py::test_tool_with_an_invalid_x_mcp_header_annotation_is_rejected_at_registration[array]`
- `tests/server/mcpserver/tools/test_base.py::test_tool_with_an_invalid_x_mcp_header_annotation_is_rejected_at_registration[non-token-name]`
- `tests/server/mcpserver/tools/test_base.py::test_tool_with_an_invalid_x_mcp_header_annotation_is_rejected_at_registration[number]`
- `tests/server/mcpserver/tools/test_base.py::test_tool_with_an_invalid_x_mcp_header_annotation_is_rejected_at_registration[optional]`
