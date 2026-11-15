Re-checked against the **v2.2.0** tag — unchanged, so this is not stale.

(Correcting my earlier comment here, which pasted the checklist from the client-side issue #3483. Only its last line was about this one. The server-side facts:)

- `src/mcp/server/` still contains no `x-mcp-header` anything — no declaration mechanism, and `FastMCP`/`MCPServer` tool registration does not look for one.
- `find_invalid_x_mcp_header` is still in `src/mcp/shared/inbound.py` and is still imported by the modern streamable-HTTP server transport, where it validates the annotations on an **incoming request's** schema. It is still never run against a tool the server itself registers, which is the gap: an invalid annotation is accepted at registration and only rejected later, by clients.
- So the reproduction in the issue body stands on 2.2.0: an `x-mcp-header` on an `array`-typed parameter registers, starts and serves without complaint, and every conforming client drops the tool.

#3442 in that release does touch SEP-2243, but it adds conformance fixtures for the resource/prompt `Mcp-Name` headers rather than anything on this path.
I traced the current main implementation and confirmed the smallest fix boundary:

- ToolManager.add_tool() builds the Tool and stores it without validating tool.parameters.
- find_invalid_x_mcp_header() already walks the relevant JSON Schema positions and is already used by the client-side listing filter.
- The server-side registration path can reuse that validator before storing the tool, turning an invalid x-mcp-header into a local registration error instead of serving a tool every conforming client drops.

I think this should stay scoped to registration-time validation; a first-class annotation API is a separate design question. The regression should cover an array-typed parameter with x-mcp-header and confirm registration fails, while valid string/integer/boolean annotations remain accepted.

AI assistance was used for repository investigation and this implementation analysis; I reviewed the source and the proposed scope.
Thanks — I checked all four points against the `v2.2.0` tag and `main`, and they hold. Three things to add, plus one argument for the fix that I think strengthens the case.

**Confirmations.** `ToolManager.add_tool` (`tool_manager.py:39`) builds via `Tool.from_function` and stores at `:66` with nothing in between; `Tool.parameters` (`base.py:41`) is the JSON Schema; and `server.py:515` serves it verbatim as `input_schema=info.parameters` — so validating `tool.parameters` at registration validates exactly the object a client receives, with no transformation in between.

**1. `add_tool` is not the only door.** `ToolManager.__init__(tools=...)` (`tool_manager.py:23-27`) inserts `Tool` objects straight into `self._tools`, bypassing `add_tool` entirely. A check placed only in `add_tool` leaves that path open. A single private helper both call sites use covers it.

Separately, the lowlevel `Server(on_list_tools=...)` path never goes through `ToolManager` at all — the author returns `Tool` objects themselves. I do not think that needs to be in scope, but it is worth saying out loud that the guarantee is `MCPServer`-scoped rather than server-wide, so nobody reads the fix as stronger than it is.

**2. The predicate to reuse is the client's drop condition, not the SEP's table.** `find_invalid_x_mcp_header` is strictly stronger than the three MUST rows — it also enforces the RFC 9110 token shape, case-insensitive uniqueness, and reachability via a pure `properties` chain. That extra strictness is the point rather than over-reach: `client/session.py:1301` calls the same function, so rejecting exactly what it rejects gives the invariant *"the server never serves a tool a conforming client would drop."* Worth stating in the PR so the extra conditions do not later get trimmed back to the table.

**3. A mis-annotated tool is not only invisible — it is also unvalidated.** `validate_mcp_param_headers` opens with `if find_invalid_x_mcp_header(input_schema) is not None: return None` (`inbound.py:543`), and the docstring says so deliberately: *"A schema `find_invalid_x_mcp_header` rejects validates nothing: conforming clients drop the tool and emit no headers."* That reasoning is sound for conforming clients, but it means that today a tool with a bad annotation gets **zero header/body consistency checking** when a non-conforming client does call it. Registration-time rejection closes that too, which I think makes this more than an ergonomics fix.

**On the regression test**, I would add the `ToolManager(tools=[...])` constructor path alongside the array-typed case, and a duplicate-token case — the latter is the one where reusing the shared validator visibly buys something the SEP table would not.

Happy for you to take this — you have clearly done the tracing. I will stay out of the way unless you would rather I open it.
