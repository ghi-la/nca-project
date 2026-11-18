# modelcontextprotocol__python-sdk-3600

- repo: `modelcontextprotocol/python-sdk`, created: 2026-09-30, base_commit: `06d1d1e4d210`
- PR: https://github.com/modelcontextprotocol/python-sdk/pull/3600
- issue: https://github.com/modelcontextprotocol/python-sdk/issues/3332
- FAIL_TO_PASS: 12 tests, PASS_TO_PASS: 52 tests, collection_error: **no**

## 1. Issue (what the agent sees)

[v2] Expose the SSE max_event_size setting in Streamable HTTP clients
## What happened?

MCP Python SDK v2.0.0 constructs `httpx2.EventSource(response)` directly when parsing a Streamable HTTP POST response. Since HTTPX2 2.10, a single SSE event is limited to 1 MiB by default.

When a valid `tools/call` result is larger than 1 MiB and is returned as one SSE event, HTTPX2 raises `SSEError`. The SDK catches that transport error and the caller receives the generic MCP error:

```text
SSE stream ended without a response
```

There is currently no public Streamable HTTP setting that lets callers raise the SSE event-size limit. The transport also creates SSE readers in multiple places: the POST response path constructs `EventSource(response)` directly, while the GET and reconnection paths call `AsyncClient.sse()` without a transport-level event-size setting.

## What did you expect?

I expected the Streamable HTTP client/transport to expose an SSE event-size setting and apply it consistently to:

- POST SSE responses;
- the GET stream; and
- reconnection streams.

One possible API shape would be a `max_event_size` argument on `streamable_http_client()` and `StreamableHTTPTransport`, matching HTTPX2 terminology. The exact public API is open for maintainer direction.

If an event exceeds the configured limit, the original JSON-RPC request should receive a clear request-scoped error. The already-sent POST should not be replayed, and sibling requests sharing the session should remain usable.

## Reproduction

Use an MCP Streamable HTTP server whose tool returns more than 1 MiB of text in a single SSE event, then call that tool with the v2 client:

```python
result = await client.call_tool("large_result", {})
```

With a 2 MiB single-event response, the call fails with `SSE stream ended without a response`. The same response succeeds when the underlying `EventSource` is constructed with a larger `max_event_size`.

I can contribute an implementation and exact boundary tests if maintainers agree with exposing this setting.

## Environment

- Python 3.11
- MCP Python SDK 2.0.0
- HTTPX2 2.10.0
- Area: Client transports / Streamable HTTP

## Reference

- HTTPX2 support and the 1 MiB default: https://github.com/pydantic/httpx2/pull/1071

This issue was prepared with AI assistance and reviewed by the reporter.

## 2. Gold patch

```diff
diff --git a/docs/client/transports.md b/docs/client/transports.md
index 6d9d30f90d..69b6b84c22 100644
--- a/docs/client/transports.md
+++ b/docs/client/transports.md
@@ -46,16 +46,32 @@ environment variables or pass an explicit `verify=ssl_context` to your `httpx2.A
 (background in
 [`httpx` and `httpx-sse` replaced by `httpx2`](../migration.md#httpx-and-httpx-sse-replaced-by-httpx2)).
 
+### Larger SSE events
+
+Pass `max_sse_event_size` when a server sends a large tool result or notification in one SSE event:
+
+```python title="client.py" hl_lines="6-9"
+--8<-- "docs_src/client_transports/tutorial005.py"
+```
+
+The default is 1 MiB per event, measured in bytes before the event is parsed. The limit applies to
+POST responses, the GET stream, and resumed streams. An oversized event in a POST response or resumed
+stream fails that request with an SSE error. On the background GET stream, the client logs
+the error and retries the stream. Set `max_sse_event_size=None` to disable the cap when you trust the
+server and need larger events. JSON responses are unaffected. If you use `ClientSessionGroup`, set the
+same option on `StreamableHttpParameters`.
+
 !!! warning
     `streamable_http_client` used to take `headers=` and `timeout=` directly. It does not any more:
-    its only parameters are `url`, `http_client` and `terminate_on_close`. Reach for `headers=` out
+    its parameters are `url`, `http_client`, `terminate_on_close`, and `max_sse_event_size`. Reach for `headers=` out
     of habit and you get:
 
     ```text
     TypeError: streamable_http_client() got an unexpected keyword argument 'headers'
     ```
 
-    Everything HTTP-shaped now lives on the one `httpx2.AsyncClient` you pass in.
+    Headers, authentication, proxies, and timeouts live on the one `httpx2.AsyncClient` you pass in.
+    `max_sse_event_size` applies to the MCP transport's SSE readers instead.
 
 !!! info
     `httpx2` keeps the familiar `httpx` API, so if you know `httpx` you already know how to do auth,
@@ -132,6 +148,7 @@ A **transport** is any async context manager that yields a `(read, write)` pair
 
 * `Client("http://.../mcp")` (a URL) connects over Streamable HTTP, the production transport.
 * Headers, auth, proxies and timeouts belong on an `httpx2.AsyncClient` you pass to `streamable_http_client(url, http_client=...)`. There is no `headers=` keyword.
+* Use `streamable_http_client(url, max_sse_event_size=...)` to change the byte limit for each SSE event.
 * Redirects are followed only within the URL's own origin (a trailing-slash `307`/`308`), plus `http`→`https` on the same host. Anything else fails with `Redirect to … not followed`; configure the final URL.
 * stdio is `Client(StdioServerParameters(...))`. Wrap it in `stdio_client(...)` yourself only to redirect the child's stderr.
 * The subprocess gets an allow-listed environment, not yours; `env=` adds to it.
diff --git a/docs/migration.md b/docs/migration.md
index 03f046752c..0cfbb04b84 100644
--- a/docs/migration.md
+++ b/docs/migration.md
@@ -2104,7 +2104,7 @@ async with http_client:
 
 v1's internal client set `follow_redirects=True`. You don't need it on your own client: the transport follows a method-preserving redirect within the endpoint's origin (a trailing-slash 307/308, say) itself, and does not follow one anywhere else, whatever the client is configured to do.
 
-`streamable_http_client` itself keeps a small signature — `streamable_http_client(url, *, http_client=None, terminate_on_close=True)` — and now yields a 2-tuple (next section). The removed function's other parameters map onto the client you build:
+`streamable_http_client` itself keeps a small signature — `streamable_http_client(url, *, http_client=None, terminate_on_close=True, max_sse_event_size=1024 * 1024)` — and now yields a 2-tuple (next section). The removed function's other parameters map onto the client you build:
 
 - `headers`, `timeout`, `sse_read_timeout`, `auth`: set them on the `httpx2.AsyncClient` as above. `streamablehttp_client` defaulted to `httpx.Timeout(30, read=300)`; a bare `httpx2.AsyncClient()` falls back to httpx2's flat 5-second timeout, too short for the long-lived GET stream, so set `timeout=httpx2.Timeout(30, read=300)` (as shown) to keep v1's values. Omitting `http_client` still gives you a default client with those timeouts.
 - `httpx_client_factory`: gone with no replacement — call your factory yourself and pass the result as `http_client`.
diff --git a/docs_src/client_transports/tutorial005.py b/docs_src/client_transports/tutorial005.py
new file mode 100644
index 0000000000..b7fd2f7538
--- /dev/null
+++ b/docs_src/client_transports/tutorial005.py
@@ -0,0 +1,12 @@
+from mcp import Client
+from mcp.client.streamable_http import streamable_http_client
+
+
+async def main() -> None:
+    transport = streamable_http_client(
+        "http://localhost:8000/mcp",
+        max_sse_event_size=32 * 1024 * 1024,
+    )
+    async with Client(transport) as client:
+        result = await client.list_tools()
+        print([tool.name for tool in result.tools])
diff --git a/pyproject.toml b/pyproject.toml
index b2f26da55f..0cd0fb3bf0 100644
--- a/pyproject.toml
+++ b/pyproject.toml
@@ -131,7 +131,7 @@ dependencies = [
     # stderr (agronholm/anyio#816, fixed in 4.10).
     "anyio>=4.10; python_version >= '3.14'",
     "anyio>=4.9; python_version < '3.14'",
-    "httpx2>=2.5.0",
+    "httpx2>=2.10.0",
     "mcp-types=={{ version }}",
     "pydantic>=2.12.0",
     "starlette>=0.48.0; python_version >= '3.14'",
diff --git a/src/mcp/client/session_group.py b/src/mcp/client/session_group.py
index a544cecbe8..351c330a68 100644
--- a/src/mcp/client/session_group.py
+++ b/src/mcp/client/session_group.py
@@ -23,7 +23,7 @@
 from mcp.client.session import ElicitationFnT, ListRootsFnT, LoggingFnT, MessageHandlerFnT, SamplingFnT
 from mcp.client.sse import sse_client
 from mcp.client.stdio import StdioServerParameters
-from mcp.client.streamable_http import streamable_http_client
+from mcp.client.streamable_http import DEFAULT_MAX_SSE_EVENT_SIZE, streamable_http_client
 from mcp.shared._httpx_utils import create_mcp_http_client
 from mcp.shared.dispatcher import ProgressFnT
 from mcp.shared.exceptions import MCPError
@@ -63,6 +63,9 @@ class StreamableHttpParameters(BaseModel):
     # Close the client session when the transport closes.
     terminate_on_close: bool = True
 
+    # Maximum bytes in one server-sent event. None disables the limit.
+    max_sse_event_size: int | None = Field(default=DEFAULT_MAX_SSE_EVENT_SIZE, gt=0)
+
 
 ServerParameters: TypeAlias = StdioServerParameters | SseServerParameters | StreamableHttpParameters
 
@@ -335,6 +338,7 @@ async def _establish_session(
                     url=server_params.url,
                     http_client=httpx_client,
                     terminate_on_close=server_params.terminate_on_close,
+                    max_sse_event_size=server_params.max_sse_event_size,
                 )
                 read, write = await session_stack.enter_async_context(client)
 
diff --git a/src/mcp/client/streamable_http.py b/src/mcp/client/streamable_http.py
index 82de50fd05..053f1f10a9 100644
--- a/src/mcp/client/streamable_http.py
+++ b/src/mcp/client/streamable_http.py
@@ -58,6 +58,7 @@
 # Reconnection defaults
 DEFAULT_RECONNECTION_DELAY_MS = 1000  # 1 second fallback when server doesn't provide retry
 MAX_RECONNECTION_ATTEMPTS = 2  # Max retry attempts before giving up
+DEFAULT_MAX_SSE_EVENT_SIZE = 1024 * 1024
 
 
 class StreamableHTTPError(Exception):
@@ -110,13 +111,17 @@ class _InFlightPost:
 class StreamableHTTPTransport:
     """StreamableHTTP client transport implementation."""
 
-    def __init__(self, url: str) -> None:
+    def __init__(self, url: str, *, max_sse_event_size: int | None = DEFAULT_MAX_SSE_EVENT_SIZE) -> None:
         """Initialize the StreamableHTTP transport.
 
         Args:
             url: The endpoint URL.
+            max_sse_event_size: Maximum bytes in one SSE event. None disables the limit.
         """
+        if max_sse_event_size is not None and max_sse_event_size <= 0:
+            raise ValueError("max_sse_event_size must be positive or None")
         self.url = url
+        self.max_sse_event_size = max_sse_event_size
         self.session_id: str | None = None
         # Captured from each stamped message's metadata, synchronously in the
         # post_writer loop so the cache always reflects wire order (a POST task's
@@ -231,7 +236,9 @@ async def handle_get_stream(self, client: httpx2.AsyncClient, read_stream_writer
                 if last_event_id:
                     headers[LAST_EVENT_ID] = last_event_id
 
-                async with sse_within_origin(client, self.url, headers=headers) as event_source:
+                async with sse_within_origin(
+                    client, self.url, headers=headers, max_event_size=self.max_sse_event_size
+                ) as event_source:
                     if (redirect := _unfollowed_redirect(event_source.response)) is not None:
                         # The same GET would be redirected again, so retrying cannot help.
                         logger.warning(f"GET stream not opened: {redirect}")
@@ -278,7 +285,9 @@ async def _handle_resumption_request(self, ctx: RequestContext) -> None:
         if isinstance(ctx.session_message.message, JSONRPCRequest):  # pragma: no branch
             original_request_id = ctx.session_message.message.id
 
-        async with sse_within_origin(ctx.client, self.url, headers=headers) as event_source:
+        async with sse_within_origin(
+            ctx.client, self.url, headers=headers, max_event_size=self.max_sse_event_size
+        ) as event_source:
             if (redirect := _unfollowed_redirect(event_source.response)) is not None:
                 logger.warning(redirect)
                 assert original_request_id is not None
@@ -289,16 +298,22 @@ async def _handle_resumption_request(self, ctx: RequestContext) -> None:
             event_source.response.raise_for_status()
             logger.debug("Resumption GET SSE connection established")
 
-            async for sse in event_source:  # pragma: no branch
-                is_complete = await self._handle_sse_event(
-                    sse,
-                    ctx.read_stream_writer,
-                    original_request_id,
-                    ctx.metadata.on_resumption_token_update if ctx.metadata else None,
+            try:
+                async for sse in event_source:  # pragma: no branch
+                    is_complete = await self._handle_sse_event(
+                        sse,
+                        ctx.read_stream_writer,
+                        original_request_id,
+                        ctx.metadata.on_resumption_token_update if ctx.metadata else None,
+                    )
+                    if is_complete:
+                        await event_source.response.aclose()
+                        break
+            except httpx2.SSEError as exc:
+                assert original_request_id is not None
+                await self._resolve_abandoned_request(
+                    ctx.read_stream_writer, original_request_id, f"SSE stream failed: {exc}"
                 )
-                if is_complete:
-                    await event_source.response.aclose()
-                    break
 
     def _consume_modern_cancellation(self, session_message: SessionMessage) -> bool:
         """Translate an outbound `notifications/cancelled` at 2026; True means "do not POST".
@@ -464,7 +479,7 @@ async def _handle_sse_response(
         original_request_id = ctx.session_message.message.id
 
         try:
-            event_source = EventSource(response)
+            event_source = EventSource(response, max_event_size=self.max_sse_event_size)
             async for sse in event_source:  # pragma: no branch
                 # Track last event ID for potential reconnection
                 if sse.id:
@@ -485,6 +500,11 @@ async def _handle_sse_response(
                 if is_complete:
                     await response.aclose()
                     return  # Normal completion, no reconnect needed
+        except httpx2.SSEError as exc:
+            await self._resolve_abandoned_request(
+                ctx.read_stream_writer, original_request_id, f"SSE stream failed: {exc}"
+            )
+            return
         except Exception:
             logger.debug("SSE stream ended", exc_info=True)  # pragma: lax no cover
 
@@ -541,9 +561,14 @@ async def _handle_reconnection(
         headers = self._prepare_headers()
         headers[LAST_EVENT_ID] = last_event_id
 
+        is_sse_response = False
         try:
-            async with sse_within_origin(ctx.client, self.url, headers=headers) as event_source:
+            async with sse_within_origin(
+                ctx.client, self.url, headers=headers, max_event_size=self.max_sse_event_size
+            ) as event_source:
                 event_source.response.raise_for_status()
+                content_type = event_source.response.headers.get("content-type", "").partition(";")[0]
+                is_sse_response = content_type.strip().lower() == "text/event-stream"
                 logger.info("Reconnected to SSE stream")
 
                 # Track for potential further reconnection
@@ -569,6 +594,13 @@ async def _handle_reconnection(
                 # Stream ended again without response - reconnect again (reset attempt counter)
                 logger.info("SSE stream disconnected, reconnecting...")
                 await self._handle_reconnection(ctx, reconnect_last_event_id, reconnect_retry_ms, 0)
+        except httpx2.SSEError as exc:
+            if is_sse_response:
+                await self._resolve_abandoned_request(
+                    ctx.read_stream_writer, original_request_id, f"SSE stream failed: {exc}"
+                )
+            else:
+                await self._handle_reconnection(ctx, last_event_id, retry_interval_ms, attempt + 1)
         except Exception as e:  # pragma: no cover
             logger.debug(f"Reconnection failed: {e}")
             # Try to reconnect again if we still have an event ID
@@ -683,6 +715,7 @@ async def streamable_http_client(
     *,
     http_client: httpx2.AsyncClient | None = None,
     terminate_on_close: bool = True,
+    max_sse_event_size: int | None = DEFAULT_MAX_SSE_EVENT_SIZE,
 ) -> AsyncGenerator[TransportStreams, None]:
     """Client transport for StreamableHTTP.
 
@@ -699,6 +732,8 @@ async def streamable_http_client(
             client's `follow_redirects` setting is not consulted; the SDK's OAuth providers apply the
             same rule to the requests they make.
         terminate_on_close: If True, send a DELETE request to terminate the session when the context exits.
+        max_sse_event_size: Maximum bytes buffered for one SSE event. None disables the limit.
+            JSON responses are not affected.
 
     Yields:
         Tuple containing:
@@ -716,7 +751,7 @@ async def streamable_http_client(
         # Create default client with recommended MCP timeouts
         client = create_mcp_http_client()
 
-    transport = StreamableHTTPTransport(url)
+    transport = StreamableHTTPTransport(url, max_sse_event_size=max_sse_event_size)
 
     logger.debug(f"Connecting to StreamableHTTP endpoint: {url}")
 
diff --git a/src/mcp/shared/_httpx_utils.py b/src/mcp/shared/_httpx_utils.py
index 940b9f08cc..7107e5e535 100644
--- a/src/mcp/shared/_httpx_utils.py
+++ b/src/mcp/shared/_httpx_utils.py
@@ -156,13 +156,17 @@ async def request_within_origin(
 
 @asynccontextmanager
 async def sse_within_origin(
-    client: httpx2.AsyncClient, url: httpx2.URL | str, *, headers: dict[str, str] | None = None
+    client: httpx2.AsyncClient,
+    url: httpx2.URL | str,
+    *,
+    headers: dict[str, str] | None = None,
+    max_event_size: int | None = 1024 * 1024,
 ) -> AsyncGenerator[httpx2.EventSource]:
     """`client.sse(url)` with the redirect handling of `stream_within_origin`."""
     merged = httpx2.Headers(_SSE_HEADERS)
     merged.update(headers or {})
     async with stream_within_origin(client, "GET", url, headers=merged) as response:
-        yield httpx2.EventSource(response)
+        yield httpx2.EventSource(response, max_event_size=max_event_size)
 
 
 def redirect_location(response: httpx2.Response) -> httpx2.URL | None:
diff --git a/uv.lock b/uv.lock
index 0d93802eb4..33f102134d 100644
--- a/uv.lock
+++ b/uv.lock
@@ -1088,7 +1088,7 @@ translate = [
 requires-dist = [
     { name = "anyio", marker = "python_full_version < '3.14'", specifier = ">=4.9" },
     { name = "anyio", marker = "python_full_version >= '3.14'", specifier = ">=4.10" },
-    { name = "httpx2", specifier = ">=2.5.0" },
+    { name = "httpx2", specifier = ">=2.10.0" },
     { name = "jsonschema", specifier = ">=4.20.0" },
     { name = "mcp-types", editable = "src/mcp-types" },
     { name = "opentelemetry-api", specifier = ">=1.28.0" },
```

## 3. Test patch

```diff
diff --git a/tests/client/test_session_group.py b/tests/client/test_session_group.py
index b75d22b7a0..922e1eebcb 100644
--- a/tests/client/test_session_group.py
+++ b/tests/client/test_session_group.py
@@ -311,7 +311,9 @@ async def test_client_session_group_disconnect_non_existent_server():
             "mcp.client.session_group.sse_client",
         ),  # url, headers, timeout, sse_read_timeout
         (
-            StreamableHttpParameters(url="http://test.com/stream", terminate_on_close=False),
+            StreamableHttpParameters(
+                url="http://test.com/stream", terminate_on_close=False, max_sse_event_size=32 * 1024 * 1024
+            ),
             "streamablehttp",
             "mcp.client.session_group.streamable_http_client",
         ),  # url, headers, timeout, sse_read_timeout, terminate_on_close
@@ -380,6 +382,7 @@ async def test_client_session_group_establish_session_parameterized(
                 call_args = mock_specific_client_func.call_args
                 assert call_args.kwargs["url"] == server_params_instance.url
                 assert call_args.kwargs["terminate_on_close"] == server_params_instance.terminate_on_close
+                assert call_args.kwargs["max_sse_event_size"] == server_params_instance.max_sse_event_size
                 assert isinstance(call_args.kwargs["http_client"], httpx2.AsyncClient)
 
             mock_client_cm_instance.__aenter__.assert_awaited_once()
diff --git a/tests/client/test_streamable_http.py b/tests/client/test_streamable_http.py
index c6e62ad94a..9087394cd6 100644
--- a/tests/client/test_streamable_http.py
+++ b/tests/client/test_streamable_http.py
@@ -1,9 +1,8 @@
-"""Unit tests for the streamable-HTTP client transport.
+"""Tests for the streamable-HTTP client transport.
 
-The full client<->server round trip is pinned by the interaction suite under
-tests/interaction/transports/; these tests cover the transport's header encoding and the
-per-message metadata-headers merge directly because the headers are an HTTP-seam observation
-the public client never exposes.
+The full client<->server round trip is also pinned by the interaction suite under
+tests/interaction/transports/. Tests here cover SSE event sizes and HTTP-seam details
+that the public client never exposes.
 """
 
 import base64
@@ -22,12 +21,16 @@
     INVALID_REQUEST,
     METHOD_NOT_FOUND,
     PROTOCOL_VERSION_META_KEY,
+    CallToolRequestParams,
+    CallToolResult,
     JSONRPCError,
     JSONRPCNotification,
     JSONRPCRequest,
     JSONRPCResponse,
     ListToolsResult,
     PaginatedRequestParams,
+    TextContent,
+    Tool,
 )
 from mcp_types.version import LATEST_MODERN_VERSION
 from starlette.applications import Starlette
@@ -55,6 +58,337 @@
 from tests.shared.test_dispatcher import Recorder, echo_handlers
 
 
+@pytest.mark.anyio
+async def test_configured_sse_limit_accepts_a_tool_result_larger_than_one_mebibyte() -> None:
+    """SDK-defined: a larger SSE limit accepts a large tool result sent as one POST SSE event."""
+    payload = "x" * (2 * 1024 * 1024)
+
+    async def list_tools(ctx: ServerRequestContext, params: PaginatedRequestParams | None) -> ListToolsResult:
+        return ListToolsResult(tools=[Tool(name="large", input_schema={"type": "object"})])
+
+    async def call_tool(ctx: ServerRequestContext, params: CallToolRequestParams) -> CallToolResult:
+        assert params.name == "large"
+        return CallToolResult(content=[TextContent(text=payload)])
+
+    manager = StreamableHTTPSessionManager(app=Server("large-result", on_list_tools=list_tools, on_call_tool=call_tool))
+    app = Starlette(routes=[Mount("/mcp", app=manager.handle_request)])
+
+    with anyio.fail_after(5):
+        async with (
+            manager.run(),
+            httpx2.AsyncClient(transport=StreamingASGITransport(app)) as http,
+            Client(
+                streamable_http_client("http://localhost/mcp", http_client=http, max_sse_event_size=4 * 1024 * 1024),
+                mode="legacy",
+            ) as client,
+        ):
+            result = await client.call_tool("large", {})
+
+    assert result.content == [TextContent(text=payload)]
+
+
+@pytest.mark.anyio
+async def test_default_sse_limit_fails_one_large_tool_call_and_keeps_the_session_usable() -> None:
+    """SDK-defined: the 1 MiB default rejects one oversized tool result without poisoning the session."""
+    calls: list[str] = []
+
+    async def list_tools(ctx: ServerRequestContext, params: PaginatedRequestParams | None) -> ListToolsResult:
+        return ListToolsResult(tools=[Tool(name=name, input_schema={"type": "object"}) for name in ("large", "small")])
+
+    async def call_tool(ctx: ServerRequestContext, params: CallToolRequestParams) -> CallToolResult:
+        calls.append(params.name)
+        return CallToolResult(content=[TextContent(text="x" * (2 * 1024 * 1024) if params.name == "large" else "ok")])
+
+    manager = StreamableHTTPSessionManager(
+        app=Server("bounded-result", on_list_tools=list_tools, on_call_tool=call_tool)
+    )
+    app = Starlette(routes=[Mount("/mcp", app=manager.handle_request)])
+
+    with anyio.fail_after(5):
+        async with (
+            manager.run(),
+            httpx2.AsyncClient(transport=StreamingASGITransport(app)) as http,
+            Client(streamable_http_client("http://localhost/mcp", http_client=http), mode="legacy") as client,
+        ):
+            with pytest.raises(MCPError) as exc_info:
+                await client.call_tool("large", {})
+            result = await client.call_tool("small", {})
+
+    assert exc_info.value.error.code == CONNECTION_CLOSED
+    # httpx2 owns the error detail after this prefix.
+    assert exc_info.value.error.message.startswith("SSE stream failed: ")
+    assert result.content == [TextContent(text="ok")]
+    assert calls == ["large", "small"]
+
+
+@pytest.mark.anyio
+async def test_configured_sse_limit_accepts_a_large_get_notification() -> None:
+    """SDK-defined: a configured limit accepts a large standalone GET event.
+
+    The raw peer forces the notification onto GET, a transport detail hidden by the typed client.
+    """
+    payload = "x" * (2 * 1024 * 1024)
+    notification = json.dumps({"jsonrpc": "2.0", "method": "notifications/message", "params": {"data": payload}})
+
+    def handler(request: httpx2.Request) -> httpx2.Response:
+        if request.method == "GET":
+            return httpx2.Response(
+                200, content=f"data: {notification}\n\n".encode(), headers={"content-type": "text/event-stream"}
+            )
+        body = json.loads(request.content)
+        if body.get("method") == "initialize":
+            return httpx2.Response(
+                200, json={"jsonrpc": "2.0", "id": body["id"], "result": {}}, headers={"mcp-session-id": "s1"}
+            )
+        return httpx2.Response(202)
+
+    with anyio.fail_after(5):
+        async with (
+            httpx2.AsyncClient(transport=httpx2.MockTransport(handler)) as http,
+            streamable_http_client(
+                "http://test/mcp", http_client=http, terminate_on_close=False, max_sse_event_size=4 * 1024 * 1024
+            ) as (
+                read,
+                write,
+            ),
+        ):
+            await write.send(SessionMessage(JSONRPCRequest(jsonrpc="2.0", id=1, method="initialize", params={})))
+            await read.receive()
+            await write.send(SessionMessage(JSONRPCNotification(jsonrpc="2.0", method="notifications/initialized")))
+            received = await read.receive()
+
+    assert isinstance(received, SessionMessage)
+    assert isinstance(received.message, JSONRPCNotification)
+    assert received.message.method == "notifications/message"
+    assert received.message.params == {"data": payload}
+
+
+class _ParkedSSEStream(httpx2.AsyncByteStream):
+    """An SSE response body that emits one frame, then parks until closed.
+
+    `opened` fires when the body is consumed; `closed` fires when httpx2 releases it.
+    """
+
+    def __init__(self, content: bytes = b": parked\n\n") -> None:
+        self.opened = anyio.Event()
+        self.closed = anyio.Event()
+        self._release = anyio.Event()
+        self._content = content
+
+    async def __aiter__(self) -> AsyncIterator[bytes]:
+        self.opened.set()
+        yield self._content
+        await self._release.wait()
+
+    async def aclose(self) -> None:
+        self.closed.set()
+        self._release.set()
+
+
+@pytest.mark.anyio
+async def test_oversized_get_event_reconnects_and_delivers_later_messages() -> None:
+    """SDK-defined: a bad GET event does not prevent later server messages or POSTs.
+
+    The raw peer forces a bad GET followed by a fresh GET stream, which the typed client cannot schedule.
+    """
+    gets: list[httpx2.Request] = []
+
+    def handler(request: httpx2.Request) -> httpx2.Response:
+        if request.method == "GET":
+            gets.append(request)
+            if len(gets) == 1:
+                content = b'retry: 0\n\ndata: {"jsonrpc":"2.0","method":"notifications/message","params":{"data":"'
+                content += b"x" * 2048 + b'"}}\n\n'
+                return httpx2.Response(200, content=content, headers={"content-type": "text/event-stream"})
+            return httpx2.Response(
+                200,
+                stream=_ParkedSSEStream(
+                    b'data: {"jsonrpc":"2.0","method":"notifications/message","params":{"data":"ok"}}\n\n'
+                ),
+                headers={"content-type": "text/event-stream"},
+            )
+        body = json.loads(request.content)
+        if body.get("method") == "initialize":
+            return httpx2.Response(
+                200, json={"jsonrpc": "2.0", "id": body["id"], "result": {}}, headers={"mcp-session-id": "s1"}
+            )
+        if "id" in body:
+            return httpx2.Response(200, json={"jsonrpc": "2.0", "id": body["id"], "result": {}})
+        return httpx2.Response(202)
+
+    with anyio.fail_after(5):
+        async with (
+            httpx2.AsyncClient(transport=httpx2.MockTransport(handler)) as http,
+            streamable_http_client(
+                "http://test/mcp", http_client=http, terminate_on_close=False, max_sse_event_size=1024
+            ) as (read, write),
+        ):
+            await write.send(SessionMessage(JSONRPCRequest(jsonrpc="2.0", id=1, method="initialize", params={})))
+            await read.receive()
+            await write.send(SessionMessage(JSONRPCNotification(jsonrpc="2.0", method="notifications/initialized")))
+            notification = await read.receive()
+            await write.send(SessionMessage(JSONRPCRequest(jsonrpc="2.0", id=2, method="tools/list", params={})))
+            reply = await read.receive()
+
+    assert isinstance(notification, SessionMessage)
+    assert isinstance(notification.message, JSONRPCNotification)
+    assert notification.message.params == {"data": "ok"}
+    assert isinstance(reply, SessionMessage)
+    assert isinstance(reply.message, JSONRPCResponse)
+    assert reply.message.id == 2
+    assert len(gets) == 2
+
+
+@pytest.mark.anyio
+@pytest.mark.parametrize("limit", [0, -1])
+async def test_streamable_http_rejects_nonpositive_sse_event_limits(limit: int) -> None:
+    """SDK-defined: a nonpositive per-event byte limit is rejected before any HTTP request is sent."""
+    with pytest.raises(ValueError) as exc_info:
+        async with streamable_http_client("http://test/mcp", max_sse_event_size=limit):
+            raise NotImplementedError
+    assert str(exc_info.value) == snapshot("max_sse_event_size must be positive or None")
+
+
+@pytest.mark.anyio
+async def test_none_disables_the_sse_event_limit() -> None:
+    """SDK-defined: opting out accepts a POST SSE response larger than the 1 MiB default.
+
+    The raw peer forces SSE for the request; the typed server can choose a JSON response instead.
+    """
+    payload = "x" * (2 * 1024 * 1024)
+
+    def handler(request: httpx2.Request) -> httpx2.Response:
+        body = json.loads(request.content)
+        return httpx2.Response(
+            200,
+            content=f'data: {{"jsonrpc":"2.0","id":{body["id"]},"result":{{"text":"{payload}"}}}}\n\n'.encode(),
+            headers={"content-type": "text/event-stream"},
+        )
+
+    with anyio.fail_after(5):
+        async with (
+            httpx2.AsyncClient(transport=httpx2.MockTransport(handler)) as http,
+            streamable_http_client("http://test/mcp", http_client=http, max_sse_event_size=None) as (read, write),
+        ):
+            await write.send(SessionMessage(JSONRPCRequest(jsonrpc="2.0", id=1, method="tools/list", params={})))
+            reply = await read.receive()
+
+    assert isinstance(reply, SessionMessage)
+    assert isinstance(reply.message, JSONRPCResponse)
+    assert reply.message.result == {"text": payload}
+
+
+@pytest.mark.anyio
+async def test_configured_sse_limit_fails_an_oversized_resumption_event() -> None:
+    """SDK-defined: an oversized resumption event fails its request.
+
+    The raw peer sends an oversized replay regardless of token state, which a typed server cannot force.
+    """
+    seen: list[str] = []
+
+    def handler(request: httpx2.Request) -> httpx2.Response:
+        seen.append(request.method)
+        return httpx2.Response(
+            200,
+            content=b'data: {"jsonrpc":"2.0","id":1,"result":{"text":"' + b"x" * 2048 + b'"}}\n\n',
+            headers={"content-type": "text/event-stream"},
+        )
+
+    with anyio.fail_after(5):
+        async with (
+            httpx2.AsyncClient(transport=httpx2.MockTransport(handler)) as http,
+            streamable_http_client("http://test/mcp", http_client=http, max_sse_event_size=1024) as (read, write),
+        ):
+            await write.send(
+                SessionMessage(
+                    JSONRPCRequest(jsonrpc="2.0", id=1, method="tools/call", params={}),
+                    metadata=ClientMessageMetadata(resumption_token="evt-1"),
+                )
+            )
+            reply = await read.receive()
+
+    assert isinstance(reply, SessionMessage)
+    assert isinstance(reply.message, JSONRPCError)
+    assert reply.message.error.code == CONNECTION_CLOSED
+    # httpx2 owns the error detail after this prefix.
+    assert reply.message.error.message.startswith("SSE stream failed: ")
+    assert seen == ["GET"]
+
+
+@pytest.mark.anyio
+async def test_configured_sse_limit_does_not_replay_an_oversized_reconnected_event() -> None:
+    """SDK-defined: a reconnect that receives an oversized event fails once; replay cannot make it smaller.
+
+    The raw peer forces a priming event followed by an oversized replay, which a typed server cannot schedule exactly.
+    """
+    seen: list[str] = []
+
+    def handler(request: httpx2.Request) -> httpx2.Response:
+        seen.append(request.method)
+        if request.method == "POST":
+            return httpx2.Response(
+                200, content=b"id: evt-1\nretry: 0\n\n", headers={"content-type": "text/event-stream"}
+            )
+        assert request.headers["last-event-id"] == "evt-1"
+        return httpx2.Response(
+            200,
+            content=b'data: {"jsonrpc":"2.0","id":1,"result":{"text":"' + b"x" * 2048 + b'"}}\n\n',
+            headers={"content-type": "text/event-stream"},
+        )
+
+    with anyio.fail_after(5):
+        async with (
+            httpx2.AsyncClient(transport=httpx2.MockTransport(handler)) as http,
+            streamable_http_client("http://test/mcp", http_client=http, max_sse_event_size=1024) as (read, write),
+        ):
+            await write.send(SessionMessage(JSONRPCRequest(jsonrpc="2.0", id=1, method="tools/call", params={})))
+            reply = await read.receive()
+
+    assert isinstance(reply, SessionMessage)
+    assert isinstance(reply.message, JSONRPCError)
+    assert reply.message.error.code == CONNECTION_CLOSED
+    # httpx2 owns the error detail after this prefix.
+    assert reply.message.error.message.startswith("SSE stream failed: ")
+    assert seen == ["POST", "GET"]
+
+
+@pytest.mark.anyio
+async def test_non_sse_reconnection_response_retries_before_failing_the_request() -> None:
+    """SDK-defined: a temporary non-SSE reconnect response does not discard the request.
+
+    The raw peer forces a non-SSE GET followed by a valid replay, which the typed server cannot produce.
+    """
+    seen: list[str] = []
+
+    def handler(request: httpx2.Request) -> httpx2.Response:
+        seen.append(request.method)
+        if request.method == "POST":
+            return httpx2.Response(
+                200, content=b"id: evt-1\nretry: 0\n\n", headers={"content-type": "text/event-stream"}
+            )
+        assert request.headers["last-event-id"] == "evt-1"
+        if len(seen) == 2:
+            return httpx2.Response(200, content=b"temporary proxy response", headers={"content-type": "text/plain"})
+        return httpx2.Response(
+            200,
+            content=b'data: {"jsonrpc":"2.0","id":1,"result":{}}\n\n',
+            headers={"content-type": "text/event-stream"},
+        )
+
+    with anyio.fail_after(5):
+        async with (
+            httpx2.AsyncClient(transport=httpx2.MockTransport(handler)) as http,
+            streamable_http_client("http://test/mcp", http_client=http, max_sse_event_size=1024) as (read, write),
+        ):
+            await write.send(SessionMessage(JSONRPCRequest(jsonrpc="2.0", id=1, method="tools/call", params={})))
+            reply = await read.receive()
+
+    assert isinstance(reply, SessionMessage)
+    assert isinstance(reply.message, JSONRPCResponse)
+    assert reply.message.id == 1
+    assert seen == ["POST", "GET", "GET"]
+
+
 @pytest.mark.parametrize(
     ("raw", "expected", "wrapped"),
     [
@@ -191,29 +525,6 @@ def handler(request: httpx2.Request) -> httpx2.Response:
     assert recorded[3].headers[MCP_PROTOCOL_VERSION_HEADER] == "2025-11-25"
 
 
... (46 more lines, see the PR)
```

## 4. FAIL_TO_PASS tests

- `tests/client/test_session_group.py::test_client_session_group_establish_session_parameterized[server_params_instance2-streamablehttp-mcp.client.session_group.streamable_http_client]`
- `tests/client/test_streamable_http.py::test_configured_sse_limit_accepts_a_large_get_notification`
- `tests/client/test_streamable_http.py::test_configured_sse_limit_accepts_a_tool_result_larger_than_one_mebibyte`
- `tests/client/test_streamable_http.py::test_configured_sse_limit_does_not_replay_an_oversized_reconnected_event`
- `tests/client/test_streamable_http.py::test_configured_sse_limit_fails_an_oversized_resumption_event`
- `tests/client/test_streamable_http.py::test_default_sse_limit_fails_one_large_tool_call_and_keeps_the_session_usable`
- `tests/client/test_streamable_http.py::test_non_sse_reconnection_response_retries_before_failing_the_request`
- `tests/client/test_streamable_http.py::test_none_disables_the_sse_event_limit`
- `tests/client/test_streamable_http.py::test_oversized_get_event_reconnects_and_delivers_later_messages`
- `tests/client/test_streamable_http.py::test_streamable_http_rejects_nonpositive_sse_event_limits[-1]`
- `tests/client/test_streamable_http.py::test_streamable_http_rejects_nonpositive_sse_event_limits[0]`
- `tests/docs_src/test_client_transports.py::test_streamable_http_configuration_lives_on_the_httpx_client`
