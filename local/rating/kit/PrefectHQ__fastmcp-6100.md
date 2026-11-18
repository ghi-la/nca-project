# PrefectHQ__fastmcp-6100

- repo: `PrefectHQ/fastmcp`, created: 2026-10-27, base_commit: `3fe80e9bc3a2`
- PR: https://github.com/PrefectHQ/fastmcp/pull/6100
- issue: https://github.com/PrefectHQ/fastmcp/issues/5866
- FAIL_TO_PASS: 12 tests, PASS_TO_PASS: 90 tests, collection_error: **no**

## 1. Issue (what the agent sees)

[Bug] FastMCPApp treats hash-shaped tool names as pre-addressed, breaking Prefab callbacks after composition
## Summary

A FastMCPApp backend tool whose user-chosen name looks like a hashed backend name (`<12 lowercase hex>_<name>`, e.g. `abcdef012345_save`) is treated as already identity-addressed. When the app is composed with a namespaced `mount()` or a provider namespace, the emitted Prefab payload keeps the bare name instead of the listed namespaced name, so the UI callback fails:

```
listed: ['ns_abcdef012345_save', 'ns_form']
refs:   ['abcdef012345_save']
failed: NotFoundError Unknown tool: 'abcdef012345_save'
```

The payload identity map even self-identifies: `{"abcdef012345_save": "abcdef012345_save"}`. The no-namespace provider variant fails the same way, while ordinary tool names work.

## Reproduction (current `main` adf90b66, offline)

```python
app = FastMCPApp("contacts")
@app.tool(name="abcdef012345_save")
def save(name: str) -> str: ...          # ordinary backend tool, hash-shaped name
@app.ui
def contacts_form() -> ...: ...          # references save via CallTool

server = FastMCP("host")
server.mount(app, namespace="ns")
# list tools -> ['ns_abcdef012345_save', ...]
# Prefab payload refs -> ['abcdef012345_save'] (should be ns_abcdef012345_save)
# call_tool('abcdef012345_save') -> NotFoundError
```

## Root cause

`fastmcp_slim/fastmcp/apps/app.py:77-85` (`_prefix`): any name matching `parse_hashed_backend_name()` is assumed pre-addressed without verifying that the digest is actually `hash_tool(app_name, local_name)`. `annotate_payload_identities` then records a false self-identity, and `rewrite_payload_tool_names` (`server/providers/prefab_payload.py:115-158`) resolves `get_tool_by_hash("abcdef012345", "save")` to nothing and restores the stale bare name. After a mount/provider rename, that name is not callable.

## Suggested fix

Treat a name as pre-addressed only when it equals `hashed_backend_name(app_name, parsed_local_name)`; otherwise prefix it normally. Genuine pre-addressed names remain unchanged.

## Tests

A fix with unit and integration tests is ready: the resolver maps a hash-shaped user name to the app address, a genuinely pre-addressed name stays unchanged, and a namespaced mount/provider emits the listed ref and executes the tool. I'll open the linked PR with red/green evidence.


<!-- oss-candidate:03e092f631248e52a842843d -->

## 2. Gold patch

```diff
diff --git a/docs/apps/architecture.mdx b/docs/apps/architecture.mdx
index 9e0ff18267..9377cae934 100644
--- a/docs/apps/architecture.mdx
+++ b/docs/apps/architecture.mdx
@@ -53,7 +53,9 @@ FastMCP passes a `tool_resolver` callback to `to_json()`. Whenever the tree cont
 
 ### Hashed backend tool references
 
-FastMCP still tags app tools with `meta["fastmcp"]["app"]`, but backend routing no longer depends on sending the app name through each tool call. During serialization, FastMCP passes a resolver to `PrefabApp.to_json()`. When the tree contains `CallTool(save_contact)`, the resolver turns it into a deterministic hashed name such as `<hash>_save_contact`, where the hash is derived from the app name and backend tool name.
+FastMCP still tags app tools with `meta["fastmcp"]["app"]`, but backend routing no longer depends on sending the app name through each tool call. During serialization, FastMCP passes a resolver to `PrefabApp.to_json()`. When the tree contains `CallTool(save_contact)`, the resolver turns it into a deterministic hashed name such as `__<hash>_save_contact`, where the hash is derived from the app name and backend tool name.
+
+The `__<12 lowercase hex>_<name>` pattern is reserved for these generated addresses. `FastMCPApp` rejects registered backend and UI tool names matching it, so the resolver can distinguish registered names from addresses. This reservation concerns the name sent in tool calls; a component key such as `tool:save@` is a separate lookup identifier. Other double-underscore names, such as `__save`, remain valid.
 
 That hashed name rides along inside `structuredContent` all the way to the renderer. When the renderer calls the backend tool, it sends the hashed tool name in the normal MCP `tools/call` request. The server recognizes that format and routes through the app-tool lookup path described below.
 
@@ -95,7 +97,9 @@ Give each copy its own app name. Two tenants running the same product want `Fast
 
 ### The hashed lookup fallback
 
-The identity-addressed form `<hash>_<local_name>` remains callable. FastMCP first tries normal tool resolution; if no tool matches and the name has that shape, it calls `get_tool_by_hash(hash, local_name)`, which resolves the tool through the same lookup as its listed name. Transforms, enabled state, and authorization apply to a hashed name exactly as they do to a name call.
+Upgrading a server updates both address generation and lookup automatically. If you deploy an app backend and a proxy gateway separately, upgrade both to use the `__` address format; gateways cannot rewrite identity addresses emitted in the earlier `<hash>_<local_name>` format.
+
+The identity-addressed form `__<hash>_<local_name>` remains callable. FastMCP first tries normal tool resolution; if no tool matches and the name has that shape, it calls `get_tool_by_hash(hash, local_name)`, which resolves the tool through the same lookup as its listed name. Transforms, enabled state, and authorization apply to a hashed name exactly as they do to a name call.
 
 When one identity is claimed by more than one tool — which happens when the same app is composed into two branches — the call is refused rather than resolved, since picking either one would silently route into the wrong branch.
 
diff --git a/docs/apps/fastmcp-app.mdx b/docs/apps/fastmcp-app.mdx
index 94df30683c..199bff1bc0 100644
--- a/docs/apps/fastmcp-app.mdx
+++ b/docs/apps/fastmcp-app.mdx
@@ -137,6 +137,8 @@ def list_contacts() -> list[dict]:
 
 Backend tools support `name`, `description`, `auth`, and `timeout`.
 
+App tool names matching `__<12 lowercase hex>_<name>` (for example, `__abcdef012345_save`) are reserved for generated tool addresses. `@app.tool()`, `@app.ui()`, and `app.add_tool()` reject that pattern with a `ValueError` at registration. Other names containing double underscores, such as `__save` or `save__contact`, are allowed.
+
 ## `CallTool` — UI → backend
 
 `CallTool` is how the UI invokes a backend tool. Pass the tool's name (or a direct function reference):
diff --git a/fastmcp_slim/fastmcp/apps/app.py b/fastmcp_slim/fastmcp/apps/app.py
index 84d47d633f..268ce92996 100644
--- a/fastmcp_slim/fastmcp/apps/app.py
+++ b/fastmcp_slim/fastmcp/apps/app.py
@@ -61,7 +61,7 @@ def _make_resolver(app_name: str | None = None) -> Any:
     inside whatever composition the server has, so nothing here can know
     what these tools will be *called* by the time the payload reaches a
     host. References therefore start out identity-addressed, as
-    ``<hash>_<local_name>``.
+    ``__<hash>_<local_name>``.
 
     Each FastMCP server rewrites those references on the way out to the
     name it lists that tool under, so what a renderer finally receives is
@@ -76,8 +76,7 @@ def _make_resolver(app_name: str | None = None) -> Any:
 
     def _prefix(local_name: str) -> str:
         if app_name:
-            # Don't re-hash an already-addressed name (same guard the
-            # old ___ resolver had with "___" not in name).
+            # Don't re-hash a reference that already has an identity address.
             if parse_hashed_backend_name(local_name) is not None:
                 return local_name
             return hashed_backend_name(app_name, local_name)
@@ -111,6 +110,17 @@ def _resolve_tool_ref(fn: Any) -> Any:
     return _resolve_tool_ref
 
 
+def _validate_app_tool_name(name: str) -> None:
+    """Keep registered app names distinct from generated call addresses."""
+    from fastmcp.server.providers.addressing import parse_hashed_backend_name
+
+    if parse_hashed_backend_name(name) is not None:
+        raise ValueError(
+            f"Tool name {name!r} is reserved for generated tool addresses "
+            "(__<12 lowercase hex>_<name>). Choose a different tool name."
+        )
+
+
 def _dispatch_decorator(
     name_or_fn: str | AnyFunction | None,
     name: str | None,
@@ -208,6 +218,9 @@ def tool(
         Backend tools default to ``visibility=["app"]``.  Pass ``model=True``
         to also expose the tool to the model (``visibility=["app", "model"]``).
 
+        Names matching `__<12 lowercase hex>_<name>` are reserved for generated
+        tool addresses and raise `ValueError` at registration.
+
         Supports multiple calling patterns::
 
             @app.tool
@@ -229,6 +242,7 @@ def _register(fn: F, tool_name: str | None) -> F:
             resolved_name = tool_name or getattr(fn, "__name__", None)
             if resolved_name is None:
                 raise ValueError(f"Cannot determine tool name for {fn!r}")
+            _validate_app_tool_name(resolved_name)
 
             from fastmcp.apps.config import AppConfig, app_config_to_meta_dict
             from fastmcp.server.providers.addressing import (
@@ -311,6 +325,9 @@ def ui(
         the Prefab renderer resource and CSP. They are tagged with the app
         name so structured content includes ``_meta.fastmcp.app``.
 
+        Names matching `__<12 lowercase hex>_<name>` are reserved for generated
+        tool addresses and raise `ValueError` at registration.
+
         Supports multiple calling patterns::
 
             @app.ui
@@ -335,6 +352,7 @@ def _register(fn: F, tool_name: str | None) -> F:
             from fastmcp.tools.base import Tool
 
             resolved = tool_name or getattr(fn, "__name__", None) or "unknown"
+            _validate_app_tool_name(resolved)
             app_config = AppConfig(
                 resource_uri=PREFAB_RENDERER_URI,
                 visibility=["model"],
@@ -376,12 +394,15 @@ def add_tool(
     ) -> Tool:
         """Add a tool to this app programmatically.
 
-        The tool is tagged with this app's name for routing.
+        The tool is tagged with this app's name for routing. Names matching
+        `__<12 lowercase hex>_<name>` are reserved for generated tool addresses
+        and raise `ValueError` at registration.
         """
         from fastmcp.tools.base import Tool
 
         if not isinstance(tool, Tool):
             tool = Tool._ensure_tool(tool)
+        _validate_app_tool_name(tool.name)
 
         from fastmcp.server.providers.addressing import (
             TOOL_HASH_META_KEY,
diff --git a/fastmcp_slim/fastmcp/server/providers/addressing.py b/fastmcp_slim/fastmcp/server/providers/addressing.py
index 5b8ef0a27b..7565b398f9 100644
--- a/fastmcp_slim/fastmcp/server/providers/addressing.py
+++ b/fastmcp_slim/fastmcp/server/providers/addressing.py
@@ -4,7 +4,7 @@
 app name + tool name. The hash serves two purposes:
 
 1. **Backend-tool routing.** Tools with ``"app"`` in their visibility are
-   callable via ``<hash>_<local_name>``. The dispatcher parses the prefix
+   callable via ``__<hash>_<local_name>``. The dispatcher parses the prefix
    and calls ``get_tool_by_hash``, which finds the tool whose stored hash
    matches and applies the same transforms, visibility, and auth as a lookup
    by the tool's listed name.
@@ -71,12 +71,15 @@ def is_app_tool_with_identity(tool: Tool, tool_hash: str) -> bool:
 
 
 def hashed_backend_name(app_name: str, tool_name: str) -> str:
-    """Format the universal name for a backend tool: ``<hash>_<local_name>``."""
-    return f"{hash_tool(app_name, tool_name)}_{tool_name}"
+    """Format the universal name for a backend tool: ``__<hash>_<local_name>``."""
+    return f"__{hash_tool(app_name, tool_name)}_{tool_name}"
 
 
 def parse_hashed_backend_name(name: str) -> tuple[str, str] | None:
-    """Parse ``<HASH_LENGTH hex>_<rest>`` → ``(hash, local_tool_name)`` or None."""
+    """Parse ``__<HASH_LENGTH hex>_<rest>`` → ``(hash, local_tool_name)`` or None."""
+    if not name.startswith("__"):
+        return None
+    name = name[2:]
     if len(name) <= HASH_LENGTH + 1:
         return None
     prefix = name[:HASH_LENGTH]
diff --git a/fastmcp_slim/fastmcp/server/providers/base.py b/fastmcp_slim/fastmcp/server/providers/base.py
index 84eba6f348..a6c97dc892 100644
--- a/fastmcp_slim/fastmcp/server/providers/base.py
+++ b/fastmcp_slim/fastmcp/server/providers/base.py
@@ -281,7 +281,7 @@ async def get_tool_by_hash(self, tool_hash: str, tool_name: str) -> Tool | None:
         Server (FastMCP) performs enabled filtering after all transforms.
 
         Args:
-            tool_hash: The identity hash from a `<hash>_<local_name>` name.
+            tool_hash: The identity hash from a `__<hash>_<local_name>` name.
             tool_name: The local tool name from the same name.
 
         Returns:
diff --git a/fastmcp_slim/fastmcp/server/providers/fastmcp_provider.py b/fastmcp_slim/fastmcp/server/providers/fastmcp_provider.py
index 2d0cf1faef..4fbd927265 100644
--- a/fastmcp_slim/fastmcp/server/providers/fastmcp_provider.py
+++ b/fastmcp_slim/fastmcp/server/providers/fastmcp_provider.py
@@ -487,7 +487,7 @@ async def _get_tool_by_hash(self, tool_hash: str, tool_name: str) -> Tool | None
         if raw_tool is None:
             return None
         wrapped = FastMCPProviderTool.wrap(self.server, raw_tool)
-        wrapped._original_name = f"{tool_hash}_{tool_name}"
+        wrapped._original_name = f"__{tool_hash}_{tool_name}"
         return wrapped
 
     # -------------------------------------------------------------------------
diff --git a/fastmcp_slim/fastmcp/server/providers/prefab_payload.py b/fastmcp_slim/fastmcp/server/providers/prefab_payload.py
index 9741954d1f..017521023a 100644
--- a/fastmcp_slim/fastmcp/server/providers/prefab_payload.py
+++ b/fastmcp_slim/fastmcp/server/providers/prefab_payload.py
@@ -6,7 +6,7 @@
 layer above may rename them, and the outermost layer's names are the only ones
 a client can actually invoke.
 
-So the payload leaves the app addressed by identity — ``<hash>_<local_name>``,
+So the payload leaves the app addressed by identity — ``__<hash>_<local_name>``,
 stable everywhere — and every FastMCP server rewrites those references on the
 way out to whatever it lists that tool as. Servers rewrite innermost-first, so
 the edge writes last and wins.
@@ -91,7 +91,7 @@ def payload_has_identities(payload: Any) -> bool:
 def annotate_payload_identities(payload: dict[str, Any]) -> dict[str, Any]:
     """Record the identity-addressed form of each reference, at serialization.
 
-    References start out as ``<hash>_<local_name>``, so the map begins as an
+    References start out as ``__<hash>_<local_name>``, so the map begins as an
     identity map to itself. Once a later layer rewrites a name, this is the
     only remaining route back: it carries both what the reference points at
     and the address any server can fall back to.
diff --git a/fastmcp_slim/fastmcp/server/server.py b/fastmcp_slim/fastmcp/server/server.py
index 13770c8833..f1a8767e44 100644
--- a/fastmcp_slim/fastmcp/server/server.py
+++ b/fastmcp_slim/fastmcp/server/server.py
@@ -1426,7 +1426,7 @@ async def call_tool(
         #   1. Display-name path — the name this server lists the tool
         #      under, resolved through `get_tool`.
         #   2. Hashed-name path — backend tools that opted into
-        #      app-callable visibility, addressed as `<hash>_<local_name>`
+        #      app-callable visibility, addressed as `__<hash>_<local_name>`
         #      and resolved through `get_tool_by_hash`. It applies the same
         #      transforms, visibility, and auth as the display-name path.
         async with fastmcp.server.context.Context(fastmcp=self) as ctx:
diff --git a/fastmcp_slim/fastmcp/tools/base.py b/fastmcp_slim/fastmcp/tools/base.py
index 6c6d69d749..d75cc60ae0 100644
--- a/fastmcp_slim/fastmcp/tools/base.py
+++ b/fastmcp_slim/fastmcp/tools/base.py
@@ -550,7 +550,7 @@ def _get_tool_resolver(app_name: str | None = None) -> Callable[..., str] | None
 def _prefab_to_json(app: Any, fastmcp_app_name: str | None = None) -> dict[str, Any]:
     """Serialize a PrefabApp, addressing its peer-tool references by identity.
 
-    The resolver writes each reference as ``<hash>_<local_name>``, and the
+    The resolver writes each reference as ``__<hash>_<local_name>``, and the
     identity behind it is recorded in the payload's meta so that servers
     can re-address the reference on the way out without losing track of
     what it points at.
```

## 3. Test patch

```diff
diff --git a/tests/apps/test_tool_names.py b/tests/apps/test_tool_names.py
new file mode 100644
index 0000000000..10073cfff9
--- /dev/null
+++ b/tests/apps/test_tool_names.py
@@ -0,0 +1,57 @@
+"""App tool names must not be mistaken for generated identity addresses."""
+
+import pytest
+
+from fastmcp import FastMCPApp
+from fastmcp.tools.base import Tool
+
+
+@pytest.mark.parametrize("kind", ["tool", "ui"])
+@pytest.mark.parametrize("naming", ["function", "positional", "keyword"])
+def test_app_rejects_identity_address_as_tool_name(kind: str, naming: str) -> None:
+    app = FastMCPApp("contacts")
+    decorator = getattr(app, kind)
+
+    def save() -> str:
+        return "saved"
+
+    reserved_name = "__abcdef012345_save"
+    with pytest.raises(ValueError, match="reserved for generated tool addresses"):
+        if naming == "function":
+            save.__name__ = reserved_name
+            decorator(save)
+        elif naming == "positional":
+            decorator(reserved_name)(save)
+        else:
+            decorator(name=reserved_name)(save)
+
+
+@pytest.mark.parametrize("kind", ["tool", "ui"])
+@pytest.mark.parametrize(
+    "name",
+    ["save", "__save", "save__contact", "abcdef012345_save", "__zzzzzzzzzzzz_save"],
+)
+async def test_app_accepts_names_outside_identity_address_pattern(
+    kind: str, name: str
+) -> None:
+    app = FastMCPApp("contacts")
+
+    def save() -> str:
+        return "saved"
+
+    getattr(app, kind)(name=name)(save)
+    assert [tool.name for tool in await app._list_tools()] == [name]
+
+
+@pytest.mark.parametrize("as_tool", [False, True])
+def test_add_tool_rejects_identity_address_as_tool_name(as_tool: bool) -> None:
+    app = FastMCPApp("contacts")
+
+    def save() -> str:
+        return "saved"
+
+    save.__name__ = "__abcdef012345_save"
+    tool = Tool.from_function(save)
+    with pytest.raises(ValueError, match="reserved for generated tool addresses"):
+        app.add_tool(tool if as_tool else save)
+    assert tool.meta is None
diff --git a/tests/server/providers/test_addressing.py b/tests/server/providers/test_addressing.py
index ed348403dc..5abcf9a8b0 100644
--- a/tests/server/providers/test_addressing.py
+++ b/tests/server/providers/test_addressing.py
@@ -37,20 +37,25 @@ def test_different_tool_names_different_hash(self):
 class TestBackendNameRoundtrip:
     def test_format_and_parse(self):
         name = hashed_backend_name("contacts", "submit_form")
+        assert name == f"__{hash_tool('contacts', 'submit_form')}_submit_form"
         parsed = parse_hashed_backend_name(name)
         assert parsed is not None
         digest, local = parsed
         assert digest == hash_tool("contacts", "submit_form")
         assert local == "submit_form"
 
+    def test_parse_requires_double_underscore_prefix(self):
+        assert parse_hashed_backend_name("abcdef012345_save") is None
+        assert parse_hashed_backend_name("_abcdef012345_save") is None
+
     def test_parse_rejects_short_strings(self):
         assert parse_hashed_backend_name("foo") is None
 
     def test_parse_rejects_non_hex_prefix(self):
-        assert parse_hashed_backend_name("zzzzzzzzzzzz_save") is None
+        assert parse_hashed_backend_name("__zzzzzzzzzzzz_save") is None
 
     def test_parse_rejects_missing_separator(self):
-        assert parse_hashed_backend_name("abcdef012345save") is None
+        assert parse_hashed_backend_name("__abcdef012345save") is None
 
 
 class TestResourceUriRoundtrip:
diff --git a/tests/server/providers/test_prefab_roundtrip.py b/tests/server/providers/test_prefab_roundtrip.py
index 05897eef86..dfebf17f9f 100644
--- a/tests/server/providers/test_prefab_roundtrip.py
+++ b/tests/server/providers/test_prefab_roundtrip.py
@@ -174,6 +174,39 @@ def form() -> Text:
         assert result.content[0].text == "saved Carol"  # type: ignore[union-attr]  # ty:ignore[unresolved-attribute]
 
 
+@pytest.mark.parametrize("tool_name", ["abcdef012345_save", "__save"])
+@pytest.mark.parametrize("composition", ["provider", "mount"])
+async def test_hash_shaped_user_name_round_trip(tool_name: str, composition: str):
+    app = FastMCPApp("contacts")
+
+    @app.tool(name=tool_name)
+    def save(name: str) -> str:
+        return f"saved {name}"
+
+    @app.ui()
+    def form() -> Column:
+        return Column(
+            children=[Button(label="Save", on_click=CallTool(tool=tool_name))]
+        )
+
+    server = FastMCP("Platform")
+    if composition == "provider":
+        server.add_provider(app, namespace="ns")
+    else:
+        inner = FastMCP("Inner")
+        inner.add_provider(app)
+        server.mount(inner, namespace="ns")
+
+    result = await server.call_tool("ns_form", {})
+    assert result.structured_content is not None
+    (ref,) = _tool_refs(result.structured_content)
+    assert ref == f"ns_{tool_name}"
+    assert ref in [tool.name for tool in await server.list_tools()]
+
+    clicked = await server.call_tool(ref, {"name": "Alice"})
+    assert clicked.content[0].text == "saved Alice"  # type: ignore[union-attr]  # ty:ignore[unresolved-attribute]
+
+
 class TestProxiedServerRoundTrip:
     """A gateway proxying an app-bearing backend.
 
diff --git a/tests/server/test_hashed_tool_dispatch.py b/tests/server/test_hashed_tool_dispatch.py
index bd59907c3c..db769a4dda 100644
--- a/tests/server/test_hashed_tool_dispatch.py
+++ b/tests/server/test_hashed_tool_dispatch.py
@@ -1,7 +1,7 @@
 """Hashed tool names follow the same lookup rules as listed names.
 
 A FastMCPApp backend tool is also callable by its identity-addressed name,
-`<hash>_<local_name>`. Calling a tool that way resolves the same tool, with
+`__<hash>_<local_name>`. Calling a tool that way resolves the same tool, with
 the same transforms, enabled state, auth, and version fallback, as calling it
 by the name the server lists it under.
 """
```

## 4. FAIL_TO_PASS tests

- `tests/apps/test_tool_names.py::test_add_tool_rejects_identity_address_as_tool_name[False]`
- `tests/apps/test_tool_names.py::test_add_tool_rejects_identity_address_as_tool_name[True]`
- `tests/apps/test_tool_names.py::test_app_rejects_identity_address_as_tool_name[function-tool]`
- `tests/apps/test_tool_names.py::test_app_rejects_identity_address_as_tool_name[function-ui]`
- `tests/apps/test_tool_names.py::test_app_rejects_identity_address_as_tool_name[keyword-tool]`
- `tests/apps/test_tool_names.py::test_app_rejects_identity_address_as_tool_name[keyword-ui]`
- `tests/apps/test_tool_names.py::test_app_rejects_identity_address_as_tool_name[positional-tool]`
- `tests/apps/test_tool_names.py::test_app_rejects_identity_address_as_tool_name[positional-ui]`
- `tests/server/providers/test_addressing.py::TestBackendNameRoundtrip::test_format_and_parse`
- `tests/server/providers/test_addressing.py::TestBackendNameRoundtrip::test_parse_requires_double_underscore_prefix`
- `tests/server/providers/test_prefab_roundtrip.py::test_hash_shaped_user_name_round_trip[mount-abcdef012345_save]`
- `tests/server/providers/test_prefab_roundtrip.py::test_hash_shaped_user_name_round_trip[provider-abcdef012345_save]`
