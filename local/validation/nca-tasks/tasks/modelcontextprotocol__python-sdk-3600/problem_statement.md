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

