# Rating sheet (all tasks)

Rubric: `RUBRIC.md`. Write the scores in your own `rating_<name>.csv`.

Index: [1](#prefecthqfastmcp-6077) · [2](#prefecthqfastmcp-6100) · [3](#prefecthqfastmcp-6147) · [4](#prefecthqfastmcp-6180) · [5](#prefecthqfastmcp-6187) · [6](#celerycelery-10598) · [7](#celerycelery-10605) · [8](#celerycelery-10606) · [9](#celerycelery-10668) · [10](#celerycelery-10714) · [11](#modelcontextprotocolpython-sdk-3485) · [12](#modelcontextprotocolpython-sdk-3600) · [13](#modelcontextprotocolpython-sdk-3620) · [14](#modelcontextprotocolpython-sdk-3622) · [15](#psfblack-5259) · [16](#psfblack-5297) · [17](#psfblack-5304) · [18](#psfblack-5386) · [19](#psfblack-5408) · [20](#psfblack-5411) · [21](#psfblack-5416) · [22](#scrapyscrapy-8189) · [23](#scrapyscrapy-8193) · [24](#scrapyscrapy-8204) · [25](#scrapyscrapy-8224)

---

## PrefectHQ__fastmcp-6077

**1/25** · [PR](https://github.com/PrefectHQ/fastmcp/pull/6077) · [issue #5472](https://github.com/PrefectHQ/fastmcp/issues/5472) · 25 FAIL_TO_PASS tests

### Issue

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

### Files changed by the gold patch

- `docs/apps/architecture.mdx` (+4 / -2)
- `fastmcp_slim/fastmcp/server/providers/addressing.py` (+3 / -3)
- `fastmcp_slim/fastmcp/server/providers/local_provider/decorators/tools.py` (+2 / -3)
- `fastmcp_slim/fastmcp/server/providers/prefab_synthesis.py` (+85 / -44)
- `fastmcp_slim/fastmcp/server/server.py` (+8 / -9)

### Tests that must pass (names, deduplicated)

- `test_all_four_domain_fields_preserved`
- `test_app_tool_synthesizes_renderer`
- `test_app_true_synthesizes_renderer_resource`
- `test_auto_synthesizes_renderer_resource`
- `test_csp_domain_order_does_not_change_identity`
- `test_domain_and_prefers_border_reach_resource`
- `test_equivalent_to_app_true`
- `test_frame_domains_reach_resource`
- `test_legacy_per_tool_uri_preserves_read_content_and_metadata`
- `test_listing_does_not_load_html`
- `test_matching_tools_share_one_listed_resource`
- `test_multiple_tools_share_renderer_resource`
- `test_namespaced_mount_still_synthesizes_resource`
- `test_nested_mounts_share_renderer_and_keep_backend_identity`
- `test_prefers_border_false_is_preserved`
- `test_renderer_html_is_built_on_read_not_list`
- `test_renderer_mode_and_version_change_identity`
- `test_renderer_resource_has_correct_mime_type`
- `test_renderer_resource_has_csp`
- `test_tools_list_includes_app_meta`
- … 4 more

<details><summary>Gold patch</summary>

```diff
diff --git a/docs/apps/architecture.mdx b/docs/apps/architecture.mdx
index 9e0ff18267..e4dc86f3c3 100644
--- a/docs/apps/architecture.mdx
+++ b/docs/apps/architecture.mdx
@@ -31,7 +31,7 @@ When you mark a tool with `app=True` or `@app.ui()`, FastMCP wires up the metada
 
 `app` on `@mcp.tool` accepts `True`, an `AppConfig`, or a dict. When you pass `True`, FastMCP explicitly marks the tool as a Prefab UI tool and stamps placeholder UI metadata so the provider can synthesize the correct renderer resource later. When you omit `app`, FastMCP only applies this automatically if the tool's return type is a Prefab type (`PrefabApp`, `Component`, or unions containing them).
 
-The tool and renderer are linked through a `resourceUri` field in the metadata. Internally, registration uses the placeholder URI `ui://prefab/renderer.html`; when tools and resources are listed or read, FastMCP rewrites that placeholder to a per-tool URI like `ui://prefab/tool/<hash>/renderer.html` and synthesizes the matching renderer resource on demand.
+The tool and renderer are linked through a `resourceUri` field in the metadata. Internally, registration uses the placeholder URI `ui://prefab/renderer.html`; when tools and resources are listed or read, FastMCP rewrites that placeholder to a shared URI like `ui://prefab/renderer/<hash>/renderer.html` and synthesizes the matching renderer resource on demand.
 
 ### FastMCPApp registration
 
@@ -111,7 +111,9 @@ The Prefab renderer is a self-contained JavaScript application that interprets t
 
 ### Renderer resources
 
-FastMCP exposes the renderer through per-tool resources such as `ui://prefab/tool/<hash>/renderer.html`, each with MIME type `text/html;profile=mcp-app`. The HTML is bundled inside the `prefab-ui` Python package; `get_renderer_html()` returns it as a string. The resources are synthesized on demand from each tool's UI metadata, so CSP and permissions can differ per tool even though they use the same Prefab renderer.
+Tools with matching renderer configurations share one resource at `ui://prefab/renderer/<hash>/renderer.html`, with MIME type `text/html;profile=mcp-app`. The identity includes the installed Prefab version, delivery mode, and effective resource metadata. Different CSP, permissions, domains, or border preferences produce separate resources. Explicit resource URI overrides are left unchanged, and previously advertised per-tool URIs remain readable.
+
+Listing tools and resources does not load the renderer HTML. FastMCP generates the page when a host reads the resource. The default delivery mode returns a small HTML page that loads version-pinned assets from a CDN; `PREFAB_BUNDLED_RENDERER=1` serves a self-contained page instead. Shared URIs let hosts recognize equivalent resources, whether or not they choose to cache them.
 
 The resource also carries CSP metadata (via `get_renderer_csp()`) declaring the CDN domains the renderer needs. Hosts use this to configure the iframe's Content Security Policy.
 
diff --git a/fastmcp_slim/fastmcp/server/providers/addressing.py b/fastmcp_slim/fastmcp/server/providers/addressing.py
index 5b8ef0a27b..9cc879fb9c 100644
--- a/fastmcp_slim/fastmcp/server/providers/addressing.py
+++ b/fastmcp_slim/fastmcp/server/providers/addressing.py
@@ -9,9 +9,9 @@
    matches and applies the same transforms, visibility, and auth as a lookup
    by the tool's listed name.
 
-2. **Per-tool Prefab renderer URIs.** Each prefab tool gets a unique renderer
-   resource at ``ui://prefab/tool/<hash>/renderer.html``. ``list_resources``
-   and ``read_resource`` synthesize these on demand from the tool's meta.
+2. **Legacy Prefab renderer aliases.** Previously advertised per-tool URIs at
+   ``ui://prefab/tool/<hash>/renderer.html`` remain readable. New renderer
+   resources are shared by effective configuration in ``prefab_synthesis``.
 
 The hash is computed at registration time from ``(app_name, tool_name)`` —
 both known at that moment — and stored in ``meta["fastmcp"]["tool_hash"]``.
diff --git a/fastmcp_slim/fastmcp/server/providers/local_provider/decorators/tools.py b/fastmcp_slim/fastmcp/server/providers/local_provider/decorators/tools.py
index 6a36895629..9779801b58 100644
--- a/fastmcp_slim/fastmcp/server/providers/local_provider/decorators/tools.py
+++ b/fastmcp_slim/fastmcp/server/providers/local_provider/decorators/tools.py
@@ -67,9 +67,8 @@ def _stamp_prefab_marker(tool: Tool) -> None:
 
     Sets ``meta["ui"]["resourceUri"]`` to a placeholder URI. The server
     recognizes the placeholder at list_tools / list_resources / read_resource
-    time and synthesizes a per-tool resource on the fly with a hashed URI
-    derived from the tool's mount-point address. Nothing is stored — the
-    renderer HTML and CSP are generated on demand from the tool's own meta.
+    time and synthesizes a shared renderer URI from its effective configuration.
+    Resource metadata comes from the tool; HTML is loaded only when read.
     """
     from fastmcp.apps.config import AppConfig, app_config_to_meta_dict
 
diff --git a/fastmcp_slim/fastmcp/server/providers/prefab_synthesis.py b/fastmcp_slim/fastmcp/server/providers/prefab_synthesis.py
index 30ebd05ebf..66c5d4ae0a 100644
--- a/fastmcp_slim/fastmcp/server/providers/prefab_synthesis.py
+++ b/fastmcp_slim/fastmcp/server/providers/prefab_synthesis.py
@@ -1,20 +1,18 @@
-"""On-demand Prefab renderer resource synthesis.
-
-Tools marked as Prefab (via ``app=True``, ``PrefabAppConfig``, etc.) carry
-a placeholder ``meta.ui.resourceUri`` and optionally a hash in
-``meta.fastmcp.tool_hash``. This module synthesizes per-tool renderer
-resources on demand at ``list_resources`` and ``read_resource`` time
-without storing or materializing anything.
-
-Each tool's resource URI is ``ui://prefab/tool/<hash>/renderer.html``
-where the hash comes from the tool's own meta (set at registration from
-the app name + tool name). CSP on the resource is the tool's
-``meta.ui.csp`` merged with the renderer defaults across all four
-``*_domains`` fields.
+"""On-demand Prefab renderer resources shared by effective configuration.
+
+Tools carry a placeholder UI resource URI. Listings rewrite it to a stable
+renderer URI derived from the Prefab version, delivery mode, and effective
+resource metadata. Matching tools share a resource; different CSP, permissions,
+domains, and border preferences stay distinct. HTML is loaded only on read.
+Legacy per-tool URIs remain readable independently of backend tool identity.
 """
 
 from __future__ import annotations
 
+import hashlib
+import json
+import os
+from functools import partial
 from typing import TYPE_CHECKING, Any, cast
 
 from fastmcp.server.providers.addressing import (
@@ -73,8 +71,9 @@ def _merge_domain_lists(
 
 
 def _build_resource_for_tool(tool: Tool) -> Resource | None:
-    """Synthesize a FunctionResource for a prefab tool. Returns None if prefab_ui isn't installed."""
+    """Build a lazy renderer resource, identified by its effective configuration."""
     try:
+        from prefab_ui import __version__
         from prefab_ui.renderer import get_renderer_csp, get_renderer_html
     except ImportError:
         return None
@@ -87,12 +86,15 @@ def _build_resource_for_tool(tool: Tool) -> Resource | None:
     )
     from fastmcp.resources.function_resource import FunctionResource
 
-    tool_hash = _get_tool_hash(tool)
-    if tool_hash is None:
-        return None
+    # Mirror Prefab's documented delivery-mode precedence without loading HTML.
+    mode = os.environ.get("PREFAB_RENDERER_URL", "").rstrip("/")
+    if not mode:
+        bundled = bool(os.environ.get("PREFAB_BUNDLED_RENDERER"))
+        dev_version = "dev" in __version__ or __version__ == "0.0.0"
+        mode = "bundled" if bundled or dev_version else "cdn"
 
     # Merge user CSP with renderer defaults — all four domain fields.
-    defaults: dict[str, Any] = get_renderer_csp() or {}
+    defaults: dict[str, Any] = get_renderer_csp(mode=mode) or {}
     user_csp: dict[str, Any] = {}
     if tool.meta and isinstance(tool.meta.get("ui"), dict):
         raw = tool.meta["ui"].get("csp")
@@ -123,6 +125,10 @@ def _get(d: dict[str, Any], snake: str, camel: str) -> list[str] | None:
             _get(user_csp, "base_uri_domains", "baseUriDomains"),
         ),
     }
+    # CSP domain lists are sets of allowed origins; order has no meaning.
+    merged = {
+        key: sorted(set(value)) if value else None for key, value in merged.items()
+    }
 
     resource_csp = ResourceCSP(**merged) if any(merged.values()) else None
 
@@ -152,15 +158,21 @@ def _get(d: dict[str, Any], snake: str, camel: str) -> list[str] | None:
         domain=domain,
         prefers_border=prefers_border,
     )
-    uri = f"ui://prefab/tool/{tool_hash}/renderer.html"
+    meta = {"ui": app_config_to_meta_dict(resource_app)}
+    identity = json.dumps(
+        {"version": __version__, "mode": mode, "mime_type": UI_MIME_TYPE, "meta": meta},
+        sort_keys=True,
+        separators=(",", ":"),
+    )
+    digest = hashlib.sha256(identity.encode()).hexdigest()
+    uri = f"ui://prefab/renderer/{digest}/renderer.html"
 
-    # The page is built on read: listing would otherwise build one copy per tool.
     return FunctionResource(
         uri=cast(Any, uri),
-        name=f"Prefab Renderer ({tool.name})",
-        fn=get_renderer_html,
+        name="Prefab Renderer",
+        fn=partial(get_renderer_html, mode=mode),
         mime_type=UI_MIME_TYPE,
-        meta={"ui": app_config_to_meta_dict(resource_app)},
+        meta=meta,
     )
 
 
@@ -211,17 +223,42 @@ def _walk_provider(provider: Provider) -> None:
     return results
 
 
+async def _effective_prefab_tools(server: FastMCP) -> list[Tool]:
+    """Use provider and session transforms before deriving resource identity."""
+    from fastmcp.server.providers.base import Provider
+    from fastmcp.server.transforms.visibility import (
+        apply_session_transforms,
+        is_enabled,
+    )
+    from fastmcp.utilities.versions import VersionSpec
+
+    tools = await apply_session_transforms(list(await Provider.list_tools(server)))
+    result: list[Tool] = []
+    for tool in tools:
+        if not is_enabled(tool):
+            continue
+        ui = (tool.meta or {}).get("ui")
+        if _is_prefab_tool(tool):
+            result.append(tool)
+        elif isinstance(ui, dict) and str(ui.get("resourceUri", "")).startswith(
+            "ui://prefab/renderer/"
+        ):
+            # Mounted servers have already rewritten their listed metadata.
+            # A normal lookup retains the resource fields needed for synthesis.
+            original = await server.get_tool(tool.name, VersionSpec(eq=tool.version))
+            if original is not None and _is_prefab_tool(original):
+                result.append(original)
+    return result
+
+
 async def synthesize_prefab_resources(server: FastMCP) -> list[Resource]:
-    """Return fresh synthetic Prefab resources for all prefab tools. Pure."""
+    """Return one lazy resource per effective renderer configuration."""
     resources: list[Resource] = []
-    seen_hashes: set[str] = set()
-    for tool in _walk_prefab_tools(server):
-        h = _get_tool_hash(tool)
-        if h is None or h in seen_hashes:
-            continue
-        seen_hashes.add(h)
+    seen: set[str] = set()
+    for tool in await _effective_prefab_tools(server):
         resource = _build_resource_for_tool(tool)
-        if resource is not None:
+        if resource is not None and resource.key not in seen:
+            seen.add(resource.key)
             resources.append(resource)
     return resources
 
@@ -231,29 +268,33 @@ async def synthesize_prefab_resource_by_uri(
 ) -> Resource | None:
     """Intercept a Prefab renderer URI and synthesize on demand."""
     digest = parse_hashed_resource_uri(uri)
-    if digest is None:
+    if digest is None and not uri.startswith("ui://prefab/renderer/"):
         return None
-    for tool in _walk_prefab_tools(server):
-        if _get_tool_hash(tool) == digest:
-            return _build_resource_for_tool(tool)
+    tools = (
+        _walk_prefab_tools(server)
+        if digest is not None
+        else await _effective_prefab_tools(server)
+    )
+    for tool in tools:
+        resource = _build_resource_for_tool(tool)
+        if resource is not None:
+            if digest is not None and _get_tool_hash(tool) == digest:
+                return resource.model_copy(update={"uri": uri})
+            if str(resource.uri) == uri:
+                return resource
     return None
 
 
 def rewrite_tool_meta_for_wire(tool: Tool) -> Tool:
-    """Return a model_copy with the per-tool URI and resource-only fields stripped.
-
-    Reads the hash from the tool's own meta. If no hash is found,
-    returns the tool unchanged. Produces a fresh copy — the original
-    Tool object is untouched.
-    """
+    """Return a copy with the shared URI and resource-only fields stripped."""
     if not _is_prefab_tool(tool):
         return tool
-    tool_hash = _get_tool_hash(tool)
-    if tool_hash is None:
+    resource = _build_resource_for_tool(tool)
+    if resource is None:
         return tool
     assert tool.meta is not None
     new_ui = dict(tool.meta["ui"])
-    new_ui["resourceUri"] = f"ui://prefab/tool/{tool_hash}/renderer.html"
+    new_ui["resourceUri"] = str(resource.uri)
     new_ui.pop("csp", None)
     new_ui.pop("permissions", None)
     new_ui.pop("domain", None)
diff --git a/fastmcp_slim/fastmcp/server/server.py b/fastmcp_slim/fastmcp/server/server.py
index 13770c8833..b8747ad515 100644
--- a/fastmcp_slim/fastmcp/server/server.py
+++ b/fastmcp_slim/fastmcp/server/server.py
@@ -686,13 +686,10 @@ def add_provider(self, provider: Provider, *, namespace: str = "") -> None:
         super().add_provider(provider, namespace=namespace)
 
     def _rewrite_prefab_uris(self, tools: list[Tool]) -> list[Tool]:
-        """Replace placeholder Prefab URIs with per-tool hashed ones.
+        """Replace placeholder Prefab URIs with shared renderer identities.
 
-        For each tool whose ``meta.ui.resourceUri`` is the placeholder,
-        reads the tool's stored hash from ``meta.fastmcp.tool_hash``
-        and rewrites the URI to the per-tool form. Also strips CSP from
-        tool meta (it belongs on the resource). Produces ``model_copy``
-        views — originals are untouched.
+        Matching renderer configurations share a URI. Resource-only fields
+        such as CSP are stripped from copies of tool metadata.
         """
         from fastmcp.server.providers.prefab_synthesis import (
             _is_prefab_tool,
@@ -999,14 +996,16 @@ async def list_resources(
                 resources = await apply_session_transforms(resources)
                 resources = [r for r in resources if is_enabled(r)]
 
-                # Append synthetic Prefab renderer resources — one per
-                # prefab tool, hashed by mount address. These don't live on
+                # Append synthetic Prefab resources shared by effective
+                # renderer configuration. These don't live on
                 # any provider's storage; they're computed on demand.
                 from fastmcp.server.providers.prefab_synthesis import (
                     synthesize_prefab_resources,
                 )
 
-                resources.extend(await synthesize_prefab_resources(self))
+                known_keys = {resource.key for resource in resources}
+                synthetic = await synthesize_prefab_resources(self)
+                resources.extend(r for r in synthetic if r.key not in known_keys)
 
                 skip_auth, token = _get_auth_context()
                 authorized: list[Resource] = []
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/tests/server/providers/test_prefab_sharing.py b/tests/server/providers/test_prefab_sharing.py
new file mode 100644
index 0000000000..9ad0ce58ce
--- /dev/null
+++ b/tests/server/providers/test_prefab_sharing.py
@@ -0,0 +1,173 @@
+"""Renderer identity follows its content configuration, independently of tools."""
+
+import pytest
+from mcp_types import TextResourceContents
+
+from fastmcp import Client, FastMCP, FastMCPApp
+from fastmcp.apps import AppConfig, PrefabAppConfig, ResourceCSP, ResourcePermissions
+from fastmcp.server.providers.addressing import hashed_resource_uri
+from fastmcp.server.transforms import ToolTransform
+from fastmcp.tools.tool_transform import ToolTransformConfig
+
+pytest.importorskip("prefab_ui")
+
+
+async def test_matching_tools_share_one_listed_resource():
+    server = FastMCP("test")
+    server.tool(name="first", app=True)(lambda: "first")
+    server.tool(name="second", app=PrefabAppConfig())(lambda: "second")
+
+    async with Client(server) as client:
+        tools = await client.list_tools()
+        uris = {t.meta["ui"]["resourceUri"] for t in tools}
+        assert len(uris) == 1
+        resources = await client.list_resources()
+        assert {str(r.uri) for r in resources} == uris
+        assert len(resources) == 1
+
+
+@pytest.mark.parametrize(
+    "config",
+    [
+        PrefabAppConfig(csp=ResourceCSP(connect_domains=["https://api.example.com"])),
+        PrefabAppConfig(csp=ResourceCSP(resource_domains=["https://cdn.example.com"])),
+        PrefabAppConfig(csp=ResourceCSP(frame_domains=["https://frame.example.com"])),
+        PrefabAppConfig(csp=ResourceCSP(base_uri_domains=["https://base.example.com"])),
+        PrefabAppConfig(permissions=ResourcePermissions(camera={})),
+        PrefabAppConfig(domain="https://app.example.com"),
+        PrefabAppConfig(prefers_border=True),
+        PrefabAppConfig(prefers_border=False),
+    ],
+)
+async def test_different_resource_metadata_stays_distinct(config):
+    server = FastMCP("test")
+    server.tool(name="default", app=True)(lambda: "default")
+    server.tool(name="configured", app=config)(lambda: "configured")
+    async with Client(server) as client:
+        tools = await client.list_tools()
+        assert tools[0].meta["ui"]["resourceUri"] != tools[1].meta["ui"]["resourceUri"]
+        resources = await client.list_resources()
+        assert len(resources) == 2
+        for resource in resources:
+            content = (await client.read_resource(resource.uri))[0]
+            assert content.meta["ui"] == resource.meta["ui"]
+
+
+async def test_csp_domain_order_does_not_change_identity():
+    server = FastMCP("test")
+    domains = ["https://a.example.com", "https://b.example.com"]
+    for name, values in [("first", domains), ("second", domains[::-1])]:
+        config = PrefabAppConfig(csp=ResourceCSP(frame_domains=values))
+        server.tool(name=name, app=config)(lambda: "view")
+    resources = await server.list_resources()
+    assert len(resources) == 1
+
+
+async def test_legacy_per_tool_uri_preserves_read_content_and_metadata():
+    app = FastMCPApp("dashboard")
+    app.ui(name="show")(lambda: "show")
+    server = FastMCP("test")
+    server.add_provider(app, namespace="crm")
+    legacy = hashed_resource_uri("dashboard", "show")
+    async with Client(server) as client:
+        tool = (await client.list_tools())[0]
+        uri = tool.meta["ui"]["resourceUri"]
+        assert uri != legacy
+        canonical = (await client.read_resource(uri))[0]
+        alias = (await client.read_resource(legacy))[0]
+        assert isinstance(alias, TextResourceContents)
+        assert str(alias.uri) == legacy
+        assert alias.text == canonical.text
+        assert alias.mime_type == canonical.mime_type
+        assert alias.meta == canonical.meta
+
+
+async def test_nested_mounts_share_renderer_and_keep_backend_identity():
+    child = FastMCP("child")
+    for name in ["one", "two"]:
+        app = FastMCPApp(name)
+        app.ui(name="show")(lambda: "show")
+        child.add_provider(app, namespace=name)
+    parent = FastMCP("parent")
+    parent.mount(child, namespace="nested")
+    async with Client(parent) as client:
+        tools = await client.list_tools()
+        assert len({t.meta["fastmcp"]["tool_hash"] for t in tools}) == 2
+        uris = {t.meta["ui"]["resourceUri"] for t in tools}
+        assert len(uris) == 1
+        for uri in uris:
+            assert isinstance(
+                (await client.read_resource(uri))[0], TextResourceContents
+            )
+
+
+async def test_custom_resource_uri_is_untouched():
+    server = FastMCP("test")
+    server.tool(name="custom", app=AppConfig(resource_uri="ui://custom/view.html"))(
+        lambda: "view"
+    )
+    async with Client(server) as client:
+        tool = (await client.list_tools())[0]
+        assert tool.meta["ui"]["resourceUri"] == "ui://custom/view.html"
+        assert await client.list_resources() == []
+
+
+async def test_listing_does_not_load_html(monkeypatch):
+    def unexpected_html(*args, **kwargs):
+        pytest.fail("listing loaded renderer HTML")
+
+    monkeypatch.setattr("prefab_ui.renderer.get_renderer_html", unexpected_html)
+    server = FastMCP("test")
+    server.tool(name="one", app=True)(lambda: "one")
+    server.tool(name="two", app=True)(lambda: "two")
+    async with Client(server) as client:
+        assert len(await client.list_tools()) == 2
+        assert len(await client.list_resources()) == 1
+
+
+async def test_renderer_mode_and_version_change_identity(monkeypatch):
+    monkeypatch.delenv("PREFAB_RENDERER_URL", raising=False)
+    monkeypatch.delenv("PREFAB_BUNDLED_RENDERER", raising=False)
+    server = FastMCP("test")
+    server.tool(name="view", app=True)(lambda: "view")
+    cdn = str((await server.list_resources())[0].uri)
+    monkeypatch.setenv("PREFAB_BUNDLED_RENDERER", "1")
+    bundled = str((await server.list_resources())[0].uri)
+    assert cdn != bundled
+    monkeypatch.setattr("prefab_ui.__version__", "999.0.0")
+    upgraded = str((await server.list_resources())[0].uri)
+    assert upgraded != bundled
+    monkeypatch.setenv("PREFAB_RENDERER_URL", "https://dev.example.com")
+    external = str((await server.list_resources())[0].uri)
+    assert external != upgraded
+
+
+@pytest.mark.parametrize("mounted", [False, True])
+async def test_transformed_resource_configuration_is_readable(mounted):
+    server = FastMCP("test")
+    server.tool(name="view", app=True)(lambda: "view")
+    server.add_transform(
+        ToolTransform(
+            {
+                "view": ToolTransformConfig(
+                    meta={
+                        "ui": {
+                            "resourceUri": "ui://prefab/renderer.html",
+                            "domain": "https://isolated.example",
+                        }
+                    }
+                )
+            }
+        )
+    )
+    if mounted:
+        parent = FastMCP("parent")
+        parent.mount(server, namespace="nested")
+        server = parent
+    async with Client(server) as client:
+        tool = (await client.list_tools())[0]
+        uri = tool.meta["ui"]["resourceUri"]
+        resources = await client.list_resources()
+        assert uri in {str(r.uri) for r in resources}
+        content = (await client.read_resource(uri))[0]
+        assert content.meta["ui"]["domain"] == "https://isolated.example"
diff --git a/tests/server/providers/test_prefab_synthesis.py b/tests/server/providers/test_prefab_synthesis.py
index 0332d9f3bd..e2a7ce16dc 100644
--- a/tests/server/providers/test_prefab_synthesis.py
+++ b/tests/server/providers/test_prefab_synthesis.py
@@ -38,7 +38,7 @@ def show_widget() -> str:
 
         # Find the synthesized prefab resource for this tool.
         resources = list(await mcp.list_resources())
-        renderer = next((r for r in resources if "prefab/tool" in str(r.uri)), None)
+        renderer = next((r for r in resources if "prefab/renderer" in str(r.uri)), None)
         assert renderer is not None, "no prefab resource was synthesized"
         assert renderer.meta is not None
 
@@ -66,7 +66,7 @@ def widget() -> str:
             return "x"
 
         resources = list(await mcp.list_resources())
-        renderer = next(r for r in resources if "prefab/tool" in str(r.uri))
+        renderer = next(r for r in resources if "prefab/renderer" in str(r.uri))
         assert renderer.meta is not None
         csp = renderer.meta["ui"]["csp"]
 
@@ -116,7 +116,7 @@ def show_widget() -> str:
             return "widget"
 
         resources = list(await mcp.list_resources())
-        renderer = next(r for r in resources if "prefab/tool" in str(r.uri))
+        renderer = next(r for r in resources if "prefab/renderer" in str(r.uri))
         assert renderer.meta is not None
         ui = renderer.meta["ui"]
         assert ui["domain"] == "https://widget.example.com"
@@ -135,7 +135,7 @@ def show_widget() -> str:
             return "widget"
 
         renderer = next(
-            r for r in await mcp.list_resources() if "prefab/tool" in str(r.uri)
+            r for r in await mcp.list_resources() if "prefab/renderer" in str(r.uri)
         )
         assert renderer.meta is not None
         assert renderer.meta["ui"]["prefersBorder"] is False
@@ -148,7 +148,7 @@ def show_widget() -> str:
             return "widget"
 
         renderer = next(
-            r for r in await mcp.list_resources() if "prefab/tool" in str(r.uri)
+            r for r in await mcp.list_resources() if "prefab/renderer" in str(r.uri)
         )
         assert renderer.meta is not None
         assert "domain" not in renderer.meta["ui"]
@@ -176,11 +176,10 @@ def show_widget() -> str:
         assert meta["ui"]["prefersBorder"] is True
 
 
-class TestPerToolURIs:
-    """Each prefab tool gets its own URI — distinct CSP per tool becomes
-    possible because no two tools share a renderer resource."""
+class TestSharedRendererURIs:
+    """Equivalent resource configurations share a renderer URI."""
 
-    async def test_two_tools_get_distinct_uris(self):
+    async def test_two_tools_share_uri(self):
         mcp = FastMCP("test")
 
         @mcp.tool(app=True)
@@ -198,15 +197,15 @@ def tool_b() -> str:
         assert b.meta is not None
         uri_a = a.meta["ui"]["resourceUri"]
         uri_b = b.meta["ui"]["resourceUri"]
-        assert uri_a != uri_b
-        assert uri_a.startswith("ui://prefab/tool/")
-        assert uri_b.startswith("ui://prefab/tool/")
+        assert uri_a == uri_b
+        assert uri_a.startswith("ui://prefab/renderer/")
+        assert uri_b.startswith("ui://prefab/renderer/")
 
 
 class TestFastMCPAppMounts:
-    """Tools inside FastMCPApps get URIs derived from the app's mount address."""
+    """Tools inside FastMCPApps receive shared renderer resources."""
 
-    async def test_app_tool_uri_uses_address(self):
+    async def test_app_tool_synthesizes_renderer(self):
         app = FastMCPApp("dashboard")
 
         @app.ui()
@@ -217,7 +216,7 @@ def show() -> str:
         mcp.add_provider(app)
 
         resources = list(await mcp.list_resources())
-        prefab = [r for r in resources if "prefab/tool" in str(r.uri)]
+        prefab = [r for r in resources if "prefab/renderer" in str(r.uri)]
         assert len(prefab) == 1
 
     async def test_namespaced_mount_still_synthesizes_resource(self):
@@ -231,7 +230,7 @@ def contact_form() -> str:
         mcp.add_provider(app, namespace="customers")
 
         resources = list(await mcp.list_resources())
-        prefab = [r for r in resources if "prefab/tool" in str(r.uri)]
+        prefab = [r for r in resources if "prefab/renderer" in str(r.uri)]
         assert len(prefab) == 1
 
 
@@ -262,7 +261,7 @@ async def test_renderer_html_is_built_on_read_not_list(
         """Listing must not build the renderer page once per tool (#6038)."""
         calls = 0
 
-        def fake_renderer_html() -> str:
+        def fake_renderer_html(mode: str | None = None) -> str:
             nonlocal calls
             calls += 1
             return "<!doctype html><html>renderer</html>"
@@ -275,7 +274,7 @@ def fake_renderer_html() -> str:
 
         async with Client(mcp) as client:
             resources = await client.list_resources()
-            assert len(resources) == 3
+            assert len(resources) == 1
             assert calls == 0
 
             contents = await client.read_resource(resources[0].uri)
@@ -305,4 +304,4 @@ def greet(name: str) -> str:
             return name
 
         resources = list(await mcp.list_resources())
-        assert not any("prefab/tool" in str(r.uri) for r in resources)
+        assert not any("prefab/renderer" in str(r.uri) for r in resources)
diff --git a/tests/test_apps.py b/tests/test_apps.py
index d3d8842621..375db8e91e 100644
--- a/tests/test_apps.py
+++ b/tests/test_apps.py
@@ -712,7 +712,7 @@ def test_merges_renderer_csp_with_user_csp(self):
         assert config.csp.frame_domains == ["https://example.com"]
 
     async def test_auto_synthesizes_renderer_resource(self):
-        """Each prefab tool gets a per-tool renderer resource on demand."""
+        """Prefab tools synthesize shared renderer resources on demand."""
         from fastmcp.apps import PrefabAppConfig
 
         server = FastMCP("test")
@@ -722,11 +722,11 @@ def my_tool() -> str:
             return "hello"
 
         resources = list(await server.list_resources())
-        prefab = [r for r in resources if "prefab/tool" in str(r.uri)]
+        prefab = [r for r in resources if "prefab/renderer" in str(r.uri)]
         assert len(prefab) == 1
 
     async def test_equivalent_to_app_true(self):
-        """PrefabAppConfig() and app=True both synthesize a per-tool renderer."""
+        """PrefabAppConfig() and app=True produce equivalent renderer identities."""
         from fastmcp.apps import PrefabAppConfig
 
         server1 = FastMCP("test1")
@@ -748,6 +748,7 @@ def tool_b() -> str:
         assert tools2[0].meta is not None
         ui2 = tools2[0].meta.get("ui", {})
 
-        # Both produce per-tool URIs in the prefab/tool/<hash>/ form.
-        assert ui1.get("resourceUri", "").startswith("ui://prefab/tool/")
-        assert ui2.get("resourceUri", "").startswith("ui://prefab/tool/")
+        assert ui1["resourceUri"] == ui2["resourceUri"]
+        # Equivalent configurations produce the same shared renderer URI.
+        assert ui1.get("resourceUri", "").startswith("ui://prefab/renderer/")
+        assert ui2.get("resourceUri", "").startswith("ui://prefab/renderer/")
diff --git a/tests/test_apps_prefab.py b/tests/test_apps_prefab.py
index f1c5ade0f2..4e6bc5d34c 100644
--- a/tests/test_apps_prefab.py
+++ b/tests/test_apps_prefab.py
@@ -130,7 +130,7 @@ def my_tool() -> str:
             return "hello"
 
         resources = list(await mcp.list_resources())
-        prefab_resources = [r for r in resources if "prefab/tool" in str(r.uri)]
+        prefab_resources = [r for r in resources if "prefab/renderer" in str(r.uri)]
         assert len(prefab_resources) == 1
         assert "renderer.html" in str(prefab_resources[0].uri)
 
@@ -142,7 +142,7 @@ def my_tool() -> str:
             return "hello"
 
         resources = list(await mcp.list_resources())
-        renderer = next(r for r in resources if "prefab/tool" in str(r.uri))
+        renderer = next(r for r in resources if "prefab/renderer" in str(r.uri))
         assert isinstance(renderer, FunctionResource)
         assert renderer.mime_type == UI_MIME_TYPE
 
@@ -154,14 +154,13 @@ def my_tool() -> str:
             return "hello"
 
         resources = list(await mcp.list_resources())
-        renderer = next(r for r in resources if "prefab/tool" in str(r.uri))
+        renderer = next(r for r in resources if "prefab/renderer" in str(r.uri))
         assert renderer.meta is not None
         assert "ui" in renderer.meta
         assert "csp" in renderer.meta["ui"]
 
-    async def test_multiple_tools_get_dedicated_resources(self):
-        """Each prefab tool gets its own resource at a distinct hashed
-        URI — no shared singleton, so per-tool CSP becomes possible."""
+    async def test_multiple_tools_share_renderer_resource(self):
+        """Tools with matching resource configuration share one renderer."""
         mcp = FastMCP("test")
 
         @mcp.tool(app=True)
@@ -173,8 +172,8 @@ def tool_b() -> str:
             return "b"
 
         resources = list(await mcp.list_resources())
-        prefab_uris = {str(r.uri) for r in resources if "prefab/tool" in str(r.uri)}
-        assert len(prefab_uris) == 2
+        prefab_uris = {str(r.uri) for r in resources if "prefab/renderer" in str(r.uri)}
+        assert len(prefab_uris) == 1
 
     def test_explicit_app_config_not_overridden(self):
         mcp = FastMCP("test")
@@ -427,8 +426,8 @@ def my_tool() -> PrefabApp:
         tool = next(t for t in tools if t.name == "my_tool")
         meta = tool.meta or {}
         assert "ui" in meta
-        # URI is the per-tool hashed form, not the singleton.
-        assert meta["ui"]["resourceUri"].startswith("ui://prefab/tool/")
+        # URI identifies the effective renderer configuration.
+        assert meta["ui"]["resourceUri"].startswith("ui://prefab/renderer/")
         assert meta["ui"]["resourceUri"].endswith("/renderer.html")
 
     async def test_renderer_resource_readable(self):
diff --git a/tests/test_fastmcp_app.py b/tests/test_fastmcp_app.py
index 1cb3eb32d9..ce762810df 100644
--- a/tests/test_fastmcp_app.py
+++ b/tests/test_fastmcp_app.py
@@ -875,9 +875,8 @@ def save(name: str) -> str:
         names = {t.name for t in tools}
         assert names == {"dashboard", "save"}
 
-    async def test_ui_synthesizes_per_tool_renderer_resource(self):
-        """Each @app.ui() tool gets its own renderer resource synthesized
-        on demand from the server's address registry."""
+    async def test_ui_synthesizes_renderer_resource(self):
+        """An @app.ui() tool gets its renderer resource synthesized on demand."""
         app = FastMCPApp("test")
 
         @app.ui()
@@ -888,7 +887,7 @@ def dashboard() -> str:
         server.add_provider(app)
 
         resources = list(await server.list_resources())
-        prefab = [r for r in resources if "prefab/tool" in str(r.uri)]
+        prefab = [r for r in resources if "prefab/renderer" in str(r.uri)]
         assert len(prefab) == 1
```
</details>

---

## PrefectHQ__fastmcp-6100

**2/25** · [PR](https://github.com/PrefectHQ/fastmcp/pull/6100) · [issue #5866](https://github.com/PrefectHQ/fastmcp/issues/5866) · 12 FAIL_TO_PASS tests

### Issue

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

### Files changed by the gold patch

- `docs/apps/architecture.mdx` (+6 / -2)
- `docs/apps/fastmcp-app.mdx` (+2 / -0)
- `fastmcp_slim/fastmcp/apps/app.py` (+25 / -4)
- `fastmcp_slim/fastmcp/server/providers/addressing.py` (+7 / -4)
- `fastmcp_slim/fastmcp/server/providers/base.py` (+1 / -1)
- `fastmcp_slim/fastmcp/server/providers/fastmcp_provider.py` (+1 / -1)
- `fastmcp_slim/fastmcp/server/providers/prefab_payload.py` (+2 / -2)
- `fastmcp_slim/fastmcp/server/server.py` (+1 / -1)
- `fastmcp_slim/fastmcp/tools/base.py` (+1 / -1)

### Tests that must pass (names, deduplicated)

- `test_add_tool_rejects_identity_address_as_tool_name`
- `test_app_rejects_identity_address_as_tool_name`
- `test_format_and_parse`
- `test_hash_shaped_user_name_round_trip`
- `test_parse_requires_double_underscore_prefix`

<details><summary>Gold patch</summary>

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
</details>

<details><summary>Test patch</summary>

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
</details>

---

## PrefectHQ__fastmcp-6147

**3/25** · [PR](https://github.com/PrefectHQ/fastmcp/pull/6147) · [issue #6115](https://github.com/PrefectHQ/fastmcp/issues/6115) · 9 FAIL_TO_PASS tests

### Issue

Tool function caches keep the tools of dropped servers alive
`without_injected_parameters` (`fastmcp/server/dependencies.py`) and `get_cached_typeadapter` (`fastmcp/utilities/types.py`) are `@lru_cache(maxsize=5000)` and keyed by the tool function. A server that is dropped keeps up to 5,000 of its tool functions alive, with everything their closures hold. `remove_tool` does not clear them, and FastMCP has no public call that does.

This matters for a server that builds its tools as closures per request or per user, for example to give each user their own tool list. Each rebuilt server adds entries, and the old servers' tool data stays in memory until the LRU pushes them out.

The functions are also keys of the unbounded dicts of `uncalled_for` (`_signature_cache`, `_parameter_cache`): https://github.com/chrisguidry/uncalled-for/issues/21.

## Reproduction

fastmcp 3.3.1, uncalled-for 0.2.0, Python 3.12.

```python
import asyncio
import gc
import weakref

from fastmcp import Client, FastMCP
from uncalled_for import introspection


async def build_and_call() -> weakref.ref:
    mcp = FastMCP("demo")
    index = list(range(100_000))

    def search(query: str) -> int:
        return len(index)

    mcp.tool(search)
    async with Client(mcp) as client:
        await client.call_tool("search", {"query": "q"})
    return weakref.ref(search)


async def main() -> None:
    refs = [await build_and_call() for _ in range(50)]
    gc.collect()
    print(f"tool functions still alive: {sum(ref() is not None for ref in refs)} of 50")


asyncio.run(main())
```

| Run | Tool functions still alive |
|---|---|
| As released | 50 of 50 |
| `uncalled_for`'s two dicts made `WeakKeyDictionary` | 50 of 50: the two LRU caches still hold them |
| Weak dicts, and the two LRU caches cleared before `gc.collect()` | 0 of 50 |

In our backend, 300 rebuilds of one 64-tool server grew the process by 54 MB. Today we free a dropped server's functions with `_clear_signature_caches(fn)` for each tool and resource, then `cache_clear()` on the two LRU caches. That calls a private name and empties the caches of every server in the process.

## Suggested change

Any of these would let a dropped server's functions go:

- Key the two caches weakly, for example by a `WeakKeyDictionary` in place of `lru_cache`, or store the result on the function object.
- Remove a tool's entries when `remove_tool` runs, or when the server shuts down.
- A public `forget(fn)` beside `_clear_signature_caches`, which clears every cache that FastMCP and `uncalled_for` keep for one function.

### Files changed by the gold patch

- `fastmcp_slim/fastmcp/server/dependencies.py` (+2 / -2)
- `fastmcp_slim/fastmcp/server/sessions.py` (+2 / -2)
- `fastmcp_slim/fastmcp/tools/function_tool.py` (+2 / -2)
- `fastmcp_slim/fastmcp/utilities/_callable_cache.py` (+82 / -0)
- `fastmcp_slim/fastmcp/utilities/types.py` (+29 / -3)

### Tests that must pass (names, deduplicated)

- `test_bound_method_cache_is_owned_by_its_instance`
- `test_callable_cache_does_not_retain_a_dropped_closure`
- `test_dependency_wrapper_caches_each_thread_option_separately`
- `test_dropped_servers_leave_no_fastmcp_owned_tool_closures`
- `test_method_without_instance_namespace_is_not_retained`
- `test_partial_adapter_is_reused_without_retaining_its_bound_payload`

<details><summary>Gold patch</summary>

```diff
diff --git a/fastmcp_slim/fastmcp/server/dependencies.py b/fastmcp_slim/fastmcp/server/dependencies.py
index e326867142..f10e9c0187 100644
--- a/fastmcp_slim/fastmcp/server/dependencies.py
+++ b/fastmcp_slim/fastmcp/server/dependencies.py
@@ -15,7 +15,6 @@
 from contextlib import AsyncExitStack, asynccontextmanager, contextmanager
 from contextvars import ContextVar
 from dataclasses import dataclass
-from functools import lru_cache
 from types import TracebackType
 from typing import TYPE_CHECKING, Any, Protocol, cast, get_type_hints, runtime_checkable
 
@@ -42,6 +41,7 @@
 from fastmcp.exceptions import FastMCPError
 from fastmcp.server.auth import AccessToken
 from fastmcp.server.http import _current_http_request
+from fastmcp.utilities._callable_cache import cache_on_callable
 from fastmcp.utilities.async_utils import (
     call_sync_fn_in_threadpool,
     is_coroutine_function,
@@ -728,7 +728,7 @@ def get_access_token() -> AccessToken | None:
 # --- Schema generation helper ---
 
 
-@lru_cache(maxsize=5000)
+@cache_on_callable
 def without_injected_parameters(
     fn: Callable[..., Any], *, run_in_thread: bool = True
 ) -> Callable[..., Any]:
diff --git a/fastmcp_slim/fastmcp/server/sessions.py b/fastmcp_slim/fastmcp/server/sessions.py
index 82ef061a21..17298b28d8 100644
--- a/fastmcp_slim/fastmcp/server/sessions.py
+++ b/fastmcp_slim/fastmcp/server/sessions.py
@@ -41,7 +41,6 @@
 import json
 import time
 from collections.abc import Callable, Sequence
-from functools import lru_cache
 from types import TracebackType
 from typing import (
     TYPE_CHECKING,
@@ -61,6 +60,7 @@
 from fastmcp.exceptions import FastMCPError
 from fastmcp.server.dependencies import get_access_token, get_server, get_session
 from fastmcp.server.providers.base import Provider
+from fastmcp.utilities._callable_cache import cache_on_callable
 from fastmcp.utilities.logging import get_logger
 
 if TYPE_CHECKING:
@@ -339,7 +339,7 @@ class _SessionIdMarker:
 SessionId = Annotated[str, _SessionIdMarker()]
 
 
-@lru_cache(maxsize=5000)
+@cache_on_callable
 def session_id_parameter_names(fn: Callable[..., object]) -> tuple[str, ...]:
     """Names of a function's parameters annotated with `SessionId`.
 
diff --git a/fastmcp_slim/fastmcp/tools/function_tool.py b/fastmcp_slim/fastmcp/tools/function_tool.py
index 872d31310a..0706dd4096 100644
--- a/fastmcp_slim/fastmcp/tools/function_tool.py
+++ b/fastmcp_slim/fastmcp/tools/function_tool.py
@@ -7,7 +7,6 @@
 import logging
 from collections.abc import Callable
 from dataclasses import dataclass, field
-from functools import lru_cache
 from types import MethodType
 from typing import (
     Annotated,
@@ -38,6 +37,7 @@
     ToolResult,
 )
 from fastmcp.tools.function_parsing import ParsedFunction, _is_object_schema
+from fastmcp.utilities._callable_cache import cache_on_callable
 from fastmcp.utilities.async_utils import (
     call_sync_fn_in_threadpool,
     is_coroutine_function,
@@ -80,7 +80,7 @@ def _materialize_sync_generator(result: Any) -> Any:
     return result
 
 
-@lru_cache(maxsize=5000)
+@cache_on_callable
 def _wrap_body_errors(
     fn: Callable[..., Any], *, materialize_generators: bool = False
 ) -> Callable[..., Any]:
diff --git a/fastmcp_slim/fastmcp/utilities/_callable_cache.py b/fastmcp_slim/fastmcp/utilities/_callable_cache.py
new file mode 100644
index 0000000000..dfeb35deee
--- /dev/null
+++ b/fastmcp_slim/fastmcp/utilities/_callable_cache.py
@@ -0,0 +1,82 @@
+"""Memoize callable metadata without making the callable process-owned."""
+
+import inspect
+import weakref
+from collections.abc import Callable
+from dataclasses import dataclass, field
+from functools import wraps
+from threading import RLock
+from typing import Any, ParamSpec, TypeVar
+
+P = ParamSpec("P")
+R = TypeVar("R")
+_CACHE_ATTRIBUTE = "__fastmcp_callable_cache__"
+
+
+@dataclass
+class _CallableCache:
+    owner: weakref.ReferenceType[Any] | None
+    values: dict[tuple[Any, ...], Any] = field(default_factory=dict)
+
+    def __reduce__(self) -> tuple[type, tuple[None]]:
+        # Tasks can pickle user functions. Metadata is process-local and may
+        # contain weakrefs or adapters; a restored callable builds it afresh.
+        return type(self), (None,)
+
+
+def cache_on_callable(build: Callable[P, R]) -> Callable[P, R]:
+    """Cache on the first argument, or its instance for a bound method.
+
+    Wrapper and TypeAdapter values can refer back to their callable, so a weak
+    key alone cannot prevent retention. Owning the values on the callable makes
+    the whole cycle collectable. Callables without a writable namespace or weak
+    reference support are evaluated uncached instead of retained globally.
+    """
+    first_parameter = next(iter(inspect.signature(build).parameters))
+    lock = RLock()
+
+    @wraps(build)
+    def cached(*args: P.args, **kwargs: P.kwargs) -> R:
+        try:
+            target = args[0]
+        except IndexError:
+            if first_parameter not in kwargs:
+                return build(*args, **kwargs)
+            target = kwargs[first_parameter]
+        if inspect.ismethod(target):
+            method = target.__func__
+            owner = target.__self__
+        else:
+            method = None
+            owner = target
+        options = tuple((k, v) for k, v in kwargs.items() if k != first_parameter)
+        key = (build, method, args[1:], options)
+        try:
+            namespace = vars(owner)
+            owner_ref = weakref.ref(owner)
+        except TypeError:
+            return build(*args, **kwargs)
+
+        with lock:
+            cache = namespace.get(_CACHE_ATTRIBUTE)
+            # Function wrappers often copy __dict__. Never reuse the source
+            # function's metadata on a distinct wrapper with a different schema.
+            if (
+                not isinstance(cache, _CallableCache)
+                or cache.owner is None
+                or cache.owner() is not owner
+            ):
+                cache = _CallableCache(owner_ref)
+                try:
+                    namespace[_CACHE_ATTRIBUTE] = cache
+                except TypeError:
+                    return build(*args, **kwargs)
+            if key in cache.values:
+                return cache.values[key]
+
+        value = build(*args, **kwargs)
+        with lock:
+            cache.values[key] = value
+        return value
+
+    return cached
diff --git a/fastmcp_slim/fastmcp/utilities/types.py b/fastmcp_slim/fastmcp/utilities/types.py
index 56d77e59cd..ce2718a710 100644
--- a/fastmcp_slim/fastmcp/utilities/types.py
+++ b/fastmcp_slim/fastmcp/utilities/types.py
@@ -5,7 +5,7 @@
 import mimetypes
 import os
 from collections.abc import Callable
-from functools import lru_cache
+from functools import lru_cache, partial
 from pathlib import Path
 from types import EllipsisType, UnionType
 from typing import (
@@ -17,6 +17,7 @@
     get_args,
     get_origin,
     get_type_hints,
+    overload,
 )
 from urllib.parse import quote
 
@@ -25,6 +26,8 @@
 from pydantic import AnyUrl, BaseModel, ConfigDict, Field, TypeAdapter, UrlConstraints
 from typing_extensions import TypeVar
 
+from fastmcp.utilities._callable_cache import cache_on_callable
+
 T = TypeVar("T", default=Any)
 
 # TODO(sdkv2): the SDK's `mcp.types.AnyFunction` alias was removed with the
@@ -52,14 +55,37 @@ def get_function_type_hints(fn: Callable[..., Any]) -> dict[str, Any]:
     return get_type_hints(fn, include_extras=True)
 
 
-@lru_cache(maxsize=5000)
-def get_cached_typeadapter(cls: T) -> TypeAdapter[T]:
+@overload
+def get_cached_typeadapter(cls: type[T]) -> TypeAdapter[T]: ...
+
+
+@overload
+def get_cached_typeadapter(cls: Any) -> TypeAdapter[Any]: ...
+
+
+def get_cached_typeadapter(cls: Any) -> TypeAdapter[Any]:
     """
     TypeAdapters are heavy objects, and in an application context we'd typically
     create them once in a global scope and reuse them as often as possible.
     However, this isn't feasible for user-generated functions. Instead, we use a
     cache to minimize the cost of creating them as much as possible.
     """
+    if inspect.isfunction(cls) or inspect.ismethod(cls) or isinstance(cls, partial):
+        return _get_callable_typeadapter(cls)
+    return _get_type_typeadapter(cls)
+
+
+@cache_on_callable
+def _get_callable_typeadapter(cls: T) -> TypeAdapter[T]:
+    return _create_typeadapter(cls)
+
+
+@lru_cache(maxsize=5000)
+def _get_type_typeadapter(cls: T) -> TypeAdapter[T]:
+    return _create_typeadapter(cls)
+
+
+def _create_typeadapter(cls: T) -> TypeAdapter[T]:
     # For functions, process annotations to handle forward references and convert
     # Annotated[Type, "string"] to Annotated[Type, Field(description="string")]
     if inspect.isfunction(cls) or inspect.ismethod(cls):
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/tests/server/test_callable_cache_lifetime.py b/tests/server/test_callable_cache_lifetime.py
new file mode 100644
index 0000000000..8592e6c498
--- /dev/null
+++ b/tests/server/test_callable_cache_lifetime.py
@@ -0,0 +1,219 @@
+"""Callable caches must not outlive the user functions they accelerate."""
+
+import gc
+import weakref
+from collections.abc import Callable
+from functools import partial, wraps
+
+import cloudpickle
+import pytest
+from uncalled_for import annotations, introspection
+
+from fastmcp import Client, FastMCP
+from fastmcp.server.context import Context
+from fastmcp.server.dependencies import without_injected_parameters
+from fastmcp.server.sessions import session_id_parameter_names
+from fastmcp.tools.function_tool import _wrap_body_errors
+from fastmcp.utilities.types import get_cached_typeadapter
+
+
+class Payload:
+    def __init__(self) -> None:
+        self.items = list(range(100))
+
+
+@pytest.fixture
+def external_introspection_caches(monkeypatch: pytest.MonkeyPatch) -> None:
+    # uncalled-for #21 independently retains callables in its introspection
+    # (signature, parameter) and annotations (metadata, annotation) caches.
+    # Isolate them so these regressions can verify FastMCP's ownership without
+    # changing the dependency's process-wide cache objects in production.
+    monkeypatch.setattr(introspection, "_signature_cache", {})
+    monkeypatch.setattr(introspection, "_parameter_cache", {})
+    monkeypatch.setattr(annotations, "_metadata_cache", {})
+    monkeypatch.setattr(annotations, "_annotation_cache", {})
+
+
+def release_external_introspection() -> None:
+    introspection._signature_cache.clear()
+    introspection._parameter_cache.clear()
+    annotations._metadata_cache.clear()
+    annotations._annotation_cache.clear()
+
+
+@pytest.mark.usefixtures("external_introspection_caches")
+@pytest.mark.parametrize(
+    "build",
+    [
+        get_cached_typeadapter,
+        without_injected_parameters,
+        _wrap_body_errors,
+        session_id_parameter_names,
+    ],
+    ids=["type-adapter", "dependencies", "body-errors", "session-id"],
+)
+def test_callable_cache_does_not_retain_a_dropped_closure(
+    build: Callable[..., object],
+) -> None:
+    def populate() -> tuple[weakref.ReferenceType, weakref.ReferenceType]:
+        payload = Payload()
+
+        def tool(query: str) -> int:
+            return len(payload.items)
+
+        build(tool)
+        return weakref.ref(tool), weakref.ref(payload)
+
+    tool_ref, payload_ref = populate()
+    release_external_introspection()
+    gc.collect()
+
+    assert tool_ref() is None
+    assert payload_ref() is None
+
+
+@pytest.mark.usefixtures("external_introspection_caches")
+async def test_dropped_servers_leave_no_fastmcp_owned_tool_closures() -> None:
+    async def build_and_call() -> tuple[weakref.ReferenceType, weakref.ReferenceType]:
+        server = FastMCP("temporary")
+        payload = Payload()
+
+        def search(query: str) -> int:
+            return len(payload.items)
+
+        server.tool(search)
+        async with Client(server) as client:
+            result = await client.call_tool("search", {"query": "q"})
+            assert result.data == 100
+        return weakref.ref(search), weakref.ref(payload)
+
+    refs = [await build_and_call() for _ in range(3)]
+    release_external_introspection()
+    gc.collect()
+
+    assert all(tool() is None and payload() is None for tool, payload in refs)
+
+
+@pytest.mark.usefixtures("external_introspection_caches")
+def test_live_callable_keeps_its_cached_adapter() -> None:
+    def tool(value: int) -> int:
+        return value + 1
+
+    adapter = get_cached_typeadapter(tool)
+    assert get_cached_typeadapter(tool) is adapter
+    assert adapter.validate_python({"value": 2}) == 3
+    gc.collect()
+    assert get_cached_typeadapter(tool) is adapter
+    assert get_cached_typeadapter(int) is get_cached_typeadapter(int)
+
+
+def test_wrapped_function_does_not_reuse_the_source_functions_cache() -> None:
+    def source() -> int:
+        return 1
+
+    original = _wrap_body_errors(source)
+
+    @wraps(source)
+    def wrapped() -> int:
+        return 2
+
+    distinct = _wrap_body_errors(wrapped)
+    assert distinct is not original
+    assert original() == 1
+    assert distinct() == 2
+    assert _wrap_body_errors(wrapped) is distinct
+
+
+@pytest.mark.usefixtures("external_introspection_caches")
+def test_dependency_wrapper_caches_each_thread_option_separately() -> None:
+    def tool(value: int, ctx: Context) -> int:
+        return value
+
+    threaded = without_injected_parameters(tool, run_in_thread=True)
+    inline = without_injected_parameters(tool, run_in_thread=False)
+    assert threaded is not inline
+    assert without_injected_parameters(tool, run_in_thread=True) is threaded
+    assert without_injected_parameters(fn=tool, run_in_thread=False) is inline
+
+
+@pytest.mark.usefixtures("external_introspection_caches")
+def test_bound_method_cache_is_owned_by_its_instance() -> None:
+    class Receiver:
+        def __init__(self, value: int) -> None:
+            self.value = value
+
+        def tool(self, offset: int) -> int:
+            return self.value + offset
+
+    live = Receiver(10)
+    adapter = get_cached_typeadapter(live.tool)
+    assert get_cached_typeadapter(live.tool) is adapter
+
+    def populate() -> weakref.ReferenceType:
+        dropped = Receiver(20)
+        other = get_cached_typeadapter(dropped.tool)
+        assert other is not adapter
+        assert other.validate_python({"offset": 1}) == 21
+        _wrap_body_errors(dropped.tool)
+        without_injected_parameters(dropped.tool)
+        session_id_parameter_names(dropped.tool)
+        return weakref.ref(dropped)
+
+    dropped_ref = populate()
+    release_external_introspection()
+    gc.collect()
+    assert dropped_ref() is None
+    assert get_cached_typeadapter(live.tool) is adapter
+    assert adapter.validate_python({"offset": 1}) == 11
+
+
+@pytest.mark.usefixtures("external_introspection_caches")
+def test_method_without_instance_namespace_is_not_retained() -> None:
+    class Receiver:
+        __slots__ = ("__weakref__",)
+
+        def tool(self, offset: int) -> int:
+            return offset
+
+    def populate() -> weakref.ReferenceType:
+        receiver = Receiver()
+        adapter = get_cached_typeadapter(receiver.tool)
+        assert adapter.validate_python({"offset": 2}) == 2
+        _wrap_body_errors(receiver.tool)
+        without_injected_parameters(receiver.tool)
+        session_id_parameter_names(receiver.tool)
+        return weakref.ref(receiver)
+
+    receiver_ref = populate()
+    release_external_introspection()
+    gc.collect()
+    assert receiver_ref() is None
+
+
+def test_partial_adapter_is_reused_without_retaining_its_bound_payload() -> None:
+    def tool(payload: Payload, offset: int) -> int:
+        return len(payload.items) + offset
+
+    def populate() -> tuple[weakref.ReferenceType, weakref.ReferenceType]:
+        payload = Payload()
+        bound = partial(tool, payload)
+        adapter = get_cached_typeadapter(bound)
+        assert get_cached_typeadapter(bound) is adapter
+        assert adapter.validate_python({"offset": 2}) == 102
+        return weakref.ref(bound), weakref.ref(payload)
+
+    bound_ref, payload_ref = populate()
+    gc.collect()
+    assert bound_ref() is None
+    assert payload_ref() is None
+
+
+def test_callable_cache_is_not_serialized_with_a_task_function() -> None:
+    def tool(value: int) -> int:
+        return value + 1
+
+    get_cached_typeadapter(tool)
+    restored = cloudpickle.loads(cloudpickle.dumps(tool))
+    assert restored(2) == 3
+    assert get_cached_typeadapter(restored).validate_python({"value": 2}) == 3
+    assert get_cached_typeadapter(restored) is not get_cached_typeadapter(tool)
```
</details>

---

## PrefectHQ__fastmcp-6180

**4/25** · [PR](https://github.com/PrefectHQ/fastmcp/pull/6180) · [issue #6034](https://github.com/PrefectHQ/fastmcp/issues/6034) · 86 FAIL_TO_PASS tests · ⚠️ **tests import a name introduced by the fix**

### Issue

compress_schema prunes used $defs when $ref uses JSON Pointer escapes (~0, ~1), percent-encoding, or sub-paths
### What happened?

When calling `compress_schema()` on a JSON schema whose `$ref` values use percent-encoding (e.g. `#/$defs/Alias%20One`), RFC 6901 JSON Pointer escapes (`#/$defs/a~1b`, `#/$defs/c~0d`), or sub-path pointers into a definition (`#/$defs/Container/properties/value`), `compress_schema()` treats those referenced definitions as unused and removes them from `$defs`, leaving dangling `$ref` pointers in the returned schema.

Expected behavior: `compress_schema()` should preserve `"Alias One"`, `"a/b"`, `"c~d"`, and `"Container"` in `$defs` and only prune genuinely unreferenced definitions.

### Example Code

```Python
from fastmcp.utilities.json_schema import compress_schema

schema = {
    "type": "object",
    "properties": {
        "spaced": {"$ref": "#/$defs/Alias%20One"},
        "slashed": {"$ref": "#/$defs/a~1b"},
        "tilded": {"$ref": "#/$defs/c~0d"},
        "subpath": {"$ref": "#/$defs/Container/properties/value"},
    },
    "$defs": {
        "Alias One": {"type": "string"},
        "a/b": {"type": "integer"},
        "c~d": {"type": "boolean"},
        "Container": {
            "type": "object",
            "properties": {"value": {"type": "number"}},
        },
    },
}

result = compress_schema(schema)
print(result.get("$defs"))  # Prints None (all 4 used definitions were pruned!)
assert "$defs" in result
```

### Version Information

```Text
FastMCP version: 3.0.0.dev0 (main @ 6d665f0)
Python version: 3.12.8
OS: Windows 11
```

### Files changed by the gold patch

- `fastmcp_slim/fastmcp/utilities/json_schema.py` (+37 / -7)
- `fastmcp_slim/fastmcp/utilities/openapi/schemas.py` (+7 / -6)

### Tests that must pass (names, deduplicated)

- `test_alias_chain_keeps_outer_siblings`
- `test_alias_cycle_or_missing_target_is_unchanged`
- `test_alternate_roots`
- `test_cloud_metadata_ref_not_fetched`
- `test_combined_operations`
- `test_compresses_schema_nested_far_beyond_the_recursion_limit`
- `test_deep_nesting`
- `test_def_to_def_escaped_reference_keeps_both_defs`
- `test_dereference_false_preserves_refs`
- `test_dereference_true_inlines_refs`
- `test_dereferences_nested_refs`
- `test_dereferences_simple_ref`
- `test_disable_pruning_additional_properties`
- `test_discriminator_property_remains_required_after_inlining`
- `test_does_not_modify_external_ref`
- `test_does_not_modify_schema_with_type_at_root`
- `test_does_not_modify_schema_without_defs`
- `test_does_not_modify_schema_without_ref`
- `test_does_not_mutate_input`
- `test_escaped_and_spaced_schema_names_survive_parsing`
- … 54 more

<details><summary>Gold patch</summary>

```diff
diff --git a/fastmcp_slim/fastmcp/utilities/json_schema.py b/fastmcp_slim/fastmcp/utilities/json_schema.py
index 4495320647..9cf7e22a46 100644
--- a/fastmcp_slim/fastmcp/utilities/json_schema.py
+++ b/fastmcp_slim/fastmcp/utilities/json_schema.py
@@ -102,6 +102,32 @@ def _resolve_local_ref(
     return node
 
 
+def ref_target_name(
+    ref: str, roots: Sequence[Sequence[str]] = (("$defs",),)
+) -> str | None:
+    """Return the definition name a local JSON Pointer ``$ref`` addresses.
+
+    The name is the first pointer segment after one of *roots* (``$defs`` by
+    default, ``components/schemas`` for raw OpenAPI documents), decoded the
+    way `_resolve_local_ref` decodes pointers: the fragment is percent-decoded
+    before it is split, and ``~1``/``~0`` are unescaped per RFC 6901. A
+    pointer may continue past the name into the definition's own contents, so
+    ``#/$defs/Container/properties/value`` still names ``Container``.
+
+    Returns ``None`` when the pointer does not name a definition under one of
+    *roots*. Reference collectors must use this instead of reading the raw
+    pointer text: a definition called ``a/b`` is referenced as ``a~1b``, one
+    called ``Alias One`` as ``Alias%20One``, and neither decoded name appears
+    in the raw text.
+    """
+    parts = unquote(ref[1:].lstrip("/")).split("/")
+    for root in roots:
+        depth = len(root)
+        if parts[:depth] == list(root) and len(parts) > depth and parts[depth]:
+            return parts[depth].replace("~1", "/").replace("~0", "~")
+    return None
+
+
 def _within_inline_limits(root: dict[str, Any], *, follow_refs: bool) -> bool:
     """Check the node count and depth of *root* once fully expanded.
 
@@ -758,13 +784,17 @@ def traverse_and_clean(
             if prune_defs:
                 ref = node.get("$ref")
                 if isinstance(ref, str) and ref.startswith("#/$defs/"):
-                    referenced_def = ref.split("/")[-1]
-                    if current_def_name:
-                        # We're inside a $def, so this is a def->def reference
-                        def_dependencies[referenced_def].append(current_def_name)
-                    else:
-                        # We're in the main schema, so this is a root reference
-                        root_refs.add(referenced_def)
+                    # Decode the pointer: escaped, percent-encoded, and
+                    # sub-pointer references resolve to a definition whose
+                    # name is not the raw text of the segment.
+                    referenced_def = ref_target_name(ref)
+                    if referenced_def is not None:
+                        if current_def_name:
+                            # We're inside a $def, so this is a def->def reference
+                            def_dependencies[referenced_def].append(current_def_name)
+                        else:
+                            # We're in the main schema, so this is a root reference
+                            root_refs.add(referenced_def)
 
             # Cleanups only run when we know this node is a schema, never on
             # user extension payloads (`json_schema_extra={"x-ui": {...}}`).
diff --git a/fastmcp_slim/fastmcp/utilities/openapi/schemas.py b/fastmcp_slim/fastmcp/utilities/openapi/schemas.py
index b0da4c4738..a8cb5984ff 100644
--- a/fastmcp_slim/fastmcp/utilities/openapi/schemas.py
+++ b/fastmcp_slim/fastmcp/utilities/openapi/schemas.py
@@ -4,6 +4,7 @@
 from collections import Counter
 from typing import Any
 
+from fastmcp.utilities.json_schema import ref_target_name
 from fastmcp.utilities.logging import get_logger
 
 from .json_schema_converter import (
@@ -94,13 +95,13 @@ def clean_schema_for_display(schema: JsonSchema | None) -> JsonSchema | None:
 def _ref_component_name(ref: str) -> str | None:
     """Return the component schema a local `$ref` points into, if any.
 
-    The name is the segment after `#/$defs/` or `#/components/schemas/`, so
-    `#/$defs/Pet/properties/status` needs the `Pet` definition.
+    The name is the decoded segment after `#/$defs/` or
+    `#/components/schemas/`, so `#/$defs/Pet/properties/status` needs the
+    `Pet` definition and `#/$defs/a~1b` needs `a/b`.
     """
-    for prefix in ("#/$defs/", "#/components/schemas/"):
-        if ref.startswith(prefix):
-            return ref.removeprefix(prefix).split("/")[0] or None
-    return None
+    if not ref.startswith("#/"):
+        return None
+    return ref_target_name(ref, roots=(("$defs",), ("components", "schemas")))
 
 
 def _replace_ref_with_defs(
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/tests/utilities/openapi/test_parser.py b/tests/utilities/openapi/test_parser.py
index 50eaf948eb..f80e10e9f8 100644
--- a/tests/utilities/openapi/test_parser.py
+++ b/tests/utilities/openapi/test_parser.py
@@ -585,3 +585,60 @@ def test_only_primary_and_bodiless_success_responses_are_extracted(self):
         assert route.responses["202"].content_schema == {}
         assert route.responses["204"].description == "No content"
         assert route.responses["204"].content_schema == {}
+
+
+class TestEscapedSchemaNameReferences:
+    """Component schema names with RFC 6901 escapes or spaces must resolve.
+
+    A schema named ``a/b`` is referenced as ``a~1b`` and one named
+    ``Alias One`` as ``Alias%20One``; reading the raw pointer text misses
+    both, so the schema is never collected and its references dangle.
+    """
+
+    def test_escaped_and_spaced_schema_names_survive_parsing(self):
+        spec = {
+            "openapi": "3.0.0",
+            "info": {"title": "Escaped names", "version": "1.0.0"},
+            "paths": {
+                "/things": {
+                    "post": {
+                        "operationId": "create_thing",
+                        "requestBody": {
+                            "content": {
+                                "application/json": {
+                                    "schema": {
+                                        "type": "object",
+                                        "properties": {
+                                            "slashed": {
+                                                "$ref": "#/components/schemas/a~1b"
+                                            },
+                                            "spaced": {
+                                                "$ref": "#/components/schemas/Alias%20One"
+                                            },
+                                        },
+                                    }
+                                }
+                            }
+                        },
+                        "responses": {"200": {"description": "OK"}},
+                    }
+                }
+            },
+            "components": {
+                "schemas": {
+                    "a/b": {"type": "integer"},
+                    "Alias One": {"type": "string"},
+                }
+            },
+        }
+
+        (route,) = parse_openapi_to_http_routes(spec)
+
+        # Both referenced schemas are collected under their decoded names.
+        assert set(route.request_schemas) == {"a/b", "Alias One"}
+
+        schema, _ = _combine_schemas_and_map_params(route)
+        assert schema["$defs"]["a/b"] == {"type": "integer"}
+        assert schema["$defs"]["Alias One"] == {"type": "string"}
+        assert schema["properties"]["slashed"] == {"$ref": "#/$defs/a~1b"}
+        assert schema["properties"]["spaced"] == {"$ref": "#/$defs/Alias%20One"}
diff --git a/tests/utilities/test_json_schema.py b/tests/utilities/test_json_schema.py
index c0195dc3dd..c3b15ca038 100644
--- a/tests/utilities/test_json_schema.py
+++ b/tests/utilities/test_json_schema.py
@@ -11,6 +11,7 @@
     _strip_remote_refs,
     compress_schema,
     dereference_refs,
+    ref_target_name,
     resolve_root_ref,
 )
 
@@ -927,6 +928,112 @@ def test_mcp_client_compatibility_requires_additional_properties(self):
         )
 
 
+class TestRefTargetName:
+    """Tests for decoding definition names out of local $ref pointers."""
+
+    def test_plain_name(self):
+        assert ref_target_name("#/$defs/Category") == "Category"
+
+    def test_rfc6901_escapes_are_decoded(self):
+        assert ref_target_name("#/$defs/a~1b") == "a/b"
+        assert ref_target_name("#/$defs/c~0d") == "c~d"
+        # ~0 must not be re-decoded: ~01 names the definition "~1".
+        assert ref_target_name("#/$defs/a~01b") == "a~1b"
+
+    def test_percent_encoding_is_decoded_before_splitting(self):
+        assert ref_target_name("#/$defs/Alias%20One") == "Alias One"
+
+    def test_sub_pointer_names_the_container_definition(self):
+        assert ref_target_name("#/$defs/Container/properties/value") == "Container"
+
+    def test_non_definition_pointers_return_none(self):
+        assert ref_target_name("#/$defs") is None
+        assert ref_target_name("#/$defs/") is None
+        assert ref_target_name("#/properties/category") is None
+        assert ref_target_name("#/definitions/Legacy") is None
+
+    def test_alternate_roots(self):
+        assert ref_target_name("#/$defs/Category") == "Category"
+        assert (
+            ref_target_name(
+                "#/components/schemas/a~1b",
+                roots=(("$defs",), ("components", "schemas")),
+            )
+            == "a/b"
+        )
+        assert ref_target_name("#/components/schemas/Category") is None
+
+
+class TestCompressSchemaEscapedRefNames:
+    """$defs pruning must understand the pointer encoding of $ref values.
+
+    A definition named ``a/b`` is referenced as ``a~1b``, one named
+    ``Alias One`` as ``Alias%20One``, and a sub-pointer continues past the
+    definition's name. Pruning those definitions leaves dangling $refs.
+    """
+
+    def test_escapes_percent_encoding_and_subpointers_are_preserved(self):
+        schema = {
+            "type": "object",
+            "properties": {
+                "spaced": {"$ref": "#/$defs/Alias%20One"},
+                "slashed": {"$ref": "#/$defs/a~1b"},
+                "tilded": {"$ref": "#/$defs/c~0d"},
+                "subpath": {"$ref": "#/$defs/Container/properties/value"},
+            },
+            "$defs": {
+                "Alias One": {"type": "string"},
+                "a/b": {"type": "integer"},
+                "c~d": {"type": "boolean"},
+                "Container": {
+                    "type": "object",
+                    "properties": {"value": {"type": "number"}},
+                },
+            },
+        }
+
+        result = compress_schema(schema)
+
+        assert result.get("$defs") == schema["$defs"]
+        # The references themselves are untouched.
+        assert result["properties"]["slashed"] == {"$ref": "#/$defs/a~1b"}
+        assert result["properties"]["subpath"] == {
+            "$ref": "#/$defs/Container/properties/value"
+        }
+
+    def test_def_to_def_escaped_reference_keeps_both_defs(self):
+        schema = {
+            "type": "object",
+            "properties": {"root": {"$ref": "#/$defs/a~1b"}},
+            "$defs": {
+                "a/b": {"$ref": "#/$defs/c~0d"},
+                "c~d": {"type": "string"},
+            },
+        }
+
+        result = compress_schema(schema)
+
+        assert result.get("$defs") == schema["$defs"]
+
+    def test_unused_escaped_defs_are_still_pruned(self):
+        schema = {
+            "type": "object",
+            "properties": {
+                "plain": {"type": "string"},
+                "flag": {"$ref": "#/$defs/used"},
+            },
+            "$defs": {
+                "a/b": {"type": "integer"},
+                "Alias One": {"type": "string"},
+                "used": {"type": "boolean"},
+            },
+        }
+
+        result = compress_schema(schema)
+
+        assert result.get("$defs") == {"used": {"type": "boolean"}}
+
+
 class TestCompressSchemaDereference:
     """Tests for the dereference parameter of compress_schema."""
```
</details>

---

## PrefectHQ__fastmcp-6187

**5/25** · [PR](https://github.com/PrefectHQ/fastmcp/pull/6187) · [issue #6150](https://github.com/PrefectHQ/fastmcp/issues/6150) · 15 FAIL_TO_PASS tests

### Issue

from_openapi lists resource templates for non-identifier path parameters (e.g. {$top}) that can never be read
### What happened?

With a route map that turns GET routes into resource templates, `FastMCP.from_openapi` lists a template for a path parameter whose name isn't a Python identifier, such as `{$top}` (also `x.y` or `1id`), but reading it always fails with "Resource not found". These names are legal in OpenAPI path templates. A name like `user-id` works, and the same route works when mapped to a tool.

I expected the template to be readable like `resource://plain/{top}`, or not to be listed.

Found with an automated property-based tester. This report was written with AI assistance.

### Example Code

```Python
import asyncio

try:
    import httpx2 as httpx  # fastmcp 4.x
except ImportError:
    import httpx  # fastmcp 3.x

from fastmcp import Client, FastMCP
from fastmcp.server.providers.openapi import MCPType, RouteMap


def get_op(op_id, param):
    return {
        "get": {
            "operationId": op_id,
            "parameters": [
                {"name": param, "in": "path", "required": True,
                 "schema": {"type": "string"}}
            ],
            "responses": {"200": {"description": "ok"}},
        }
    }


spec = {
    "openapi": "3.0.3",
    "info": {"title": "t", "version": "1"},
    "paths": {
        "/a/{top}": get_op("plain", "top"),  # works
        "/b/{$top}": get_op("dollar", "$top"),  # legal OpenAPI name, fails
    },
}


def handler(request):
    return httpx.Response(200, json={"path": request.url.path})


client = httpx.AsyncClient(
    base_url="https://api.example.com", transport=httpx.MockTransport(handler)
)
# The documented route map for GET routes with path parameters.
route_maps = [RouteMap(methods=["GET"], mcp_type=MCPType.RESOURCE_TEMPLATE)]
mcp = FastMCP.from_openapi(spec, client=client, route_maps=route_maps)


async def main():
    async with Client(mcp) as c:
        for t in await c.list_resource_templates():
            print("template:", getattr(t, "uri_template", None) or t.uriTemplate)
        for uri in ["resource://plain/x", "resource://dollar/x"]:
            try:
                print(uri, "->", (await c.read_resource(uri))[0].text)
            except Exception as e:
                print(uri, "-> error:", e)


asyncio.run(main())
```

Output:

```
template: resource://plain/{top}
template: resource://dollar/{$top}
resource://plain/x -> {"path": "/a/x"}
resource://dollar/x -> error: Resource not found: 'resource://dollar/x'
```

### Version Information

```Text
FastMCP version:   4.1.4 (also reproduces on main at 92c4c8d7 and on 3.4.11)
MCP version:       2.3.0
Python version:    3.12.15
Platform:          macOS-26.7-arm64
```

### Files changed by the gold patch

- `fastmcp_slim/fastmcp/resources/template.py` (+46 / -21)
- `fastmcp_slim/fastmcp/server/providers/openapi/components.py` (+5 / -1)

### Tests that must pass (names, deduplicated)

- `test_build_regex_compiles_non_identifier_group_names`
- `test_build_regex_handles_all_digit_names`
- `test_build_regex_sanitizes_leading_digit_group_names`
- `test_expand_resolves_sanitized_keys`
- `test_forward_uri_resolves_sanitized_keys`
- `test_match_uri_template_sanitizes_leading_digit_names`
- `test_matches_non_identifier_names`
- `test_non_identifier_path_params_listed_and_readable`
- `test_wildcard_with_non_identifier_name`

<details><summary>Gold patch</summary>

```diff
diff --git a/fastmcp_slim/fastmcp/resources/template.py b/fastmcp_slim/fastmcp/resources/template.py
index 1b7dfa9c77..f836996b81 100644
--- a/fastmcp_slim/fastmcp/resources/template.py
+++ b/fastmcp_slim/fastmcp/resources/template.py
@@ -165,6 +165,25 @@ def chars(run: str) -> str:
     return "".join(pattern)
 
 
+def template_param_key(name: str) -> str:
+    """Normalize a template variable name into the key used for matched params.
+
+    Regex group names must be valid Python identifiers, so every character a
+    legal template variable may carry that an identifier cannot (`$`, `.`, a
+    leading digit, ...) becomes `_`. Hyphens already normalized this way.
+    Consumers that map matched params back onto route parameters (OpenAPI
+    resource templates) use the same function for the lookup.
+    """
+    key = re.sub(r"\W", "_", name)
+    if not key.isidentifier():
+        # \w also matches Unicode word characters that identifiers reject
+        # (e.g. `²`), so fall back to ASCII-only sanitization.
+        key = re.sub(r"[^a-zA-Z0-9_]", "_", key)
+    if not key or key[0].isdigit():
+        key = f"_{key}"
+    return key
+
+
 @functools.lru_cache(maxsize=4096)
 def build_regex(template: str) -> re.Pattern[str] | None:
     """Build regex pattern for URI template, handling RFC 6570 syntax.
@@ -175,11 +194,12 @@ def build_regex(template: str) -> re.Pattern[str] | None:
     - `{?var1,var2}` - query parameters (ignored in path matching)
     - `?key={var}` - a query written out literally; `{var}` is that key's value
 
-    Hyphens in parameter names are normalized to underscores in regex group
-    names so that matched groups are valid Python identifiers.
+    Parameter names are normalized to valid Python identifiers through
+    `template_param_key` so matched groups are usable and OpenAPI names
+    like `{$top}` or `1id` still match instead of disabling the template.
 
-    Returns None if the template produces an invalid regex (e.g. parameter
-    names with leading digits or duplicates from a remote server).
+    Returns None if the template produces an invalid regex (e.g. two
+    parameter names that normalize to the same group).
     """
     # Remove query parameter syntax for path matching
     template_without_query = re.sub(r"\{\?[^}]+\}", "", template)
@@ -197,11 +217,9 @@ def build_regex(template: str) -> re.Pattern[str] | None:
                 pattern += f"(?P<{group}>[^&]*)"
             elif name.endswith("*"):
                 name = name[:-1]
-                group = name.replace("-", "_")
-                pattern += f"(?P<{group}>.+)"
+                pattern += f"(?P<{template_param_key(name)}>.+)"
             else:
-                group = name.replace("-", "_")
-                pattern += f"(?P<{group}>[^/]+)"
+                pattern += f"(?P<{template_param_key(name)}>[^/]+)"
         else:
             pattern += _literal_pattern(part)
             in_query = in_query or "?" in part
@@ -311,19 +329,23 @@ def expand_uri_template(uri_template: str, params: dict[str, Any]) -> str:
     # single segment ([^/]+), so reserved characters including "/" are encoded;
     # wildcard {name*} placeholders may span segments, so "/" is preserved.
     #
-    # Params use underscored keys (e.g. user_id) but templates may use
-    # hyphens (e.g. {user-id}), so try both forms.
-    for key, value in params.items():
-        value_str = str(value)
-        simple = quote(value_str, safe="")
-        wildcard = quote(value_str, safe="/")
-        forms = [key]
-        hyphenated = key.replace("_", "-")
-        if hyphenated != key:
-            forms.append(hyphenated)
-        for form in forms:
-            result = result.replace(f"{{{form}}}", simple)
-            result = result.replace(f"{{{form}*}}", wildcard)
+    # Params are keyed the way match_uri_template returns them — sanitized
+    # through template_param_key — but templates may spell the variable with
+    # hyphens or characters an identifier cannot carry (e.g. {$top}), so each
+    # placeholder resolves against the exact name, the hyphenated form, and
+    # the sanitized form, in that order. A placeholder with no matching param
+    # stays literal.
+    def substitute(match: re.Match[str]) -> str:
+        token = match.group(1)
+        wildcard = token.endswith("*")
+        name = token[:-1] if wildcard else token
+        for candidate in (name, name.replace("-", "_"), template_param_key(name)):
+            if candidate in params:
+                value_str = str(params[candidate])
+                return quote(value_str, safe="/" if wildcard else "")
+        return match.group(0)
+
+    result = re.sub(r"\{([^?}][^}]*)\}", substitute, result)
 
     # Expand {?param1,param2,...} query parameter blocks
     def _expand_query_block(match: re.Match[str]) -> str:
@@ -338,10 +360,13 @@ def _expand_query_block(match: re.Match[str]) -> str:
             exploded = name.endswith("*")
             name = name.removesuffix("*")
             underscored = name.replace("-", "_")
+            sanitized = template_param_key(name)
             if name in params:
                 value = params[name]
             elif underscored in params:
                 value = params[underscored]
+            elif sanitized in params:
+                value = params[sanitized]
             else:
                 continue
             if exploded and isinstance(value, (list, tuple)):
diff --git a/fastmcp_slim/fastmcp/server/providers/openapi/components.py b/fastmcp_slim/fastmcp/server/providers/openapi/components.py
index 83ead909bc..24c6b3b696 100644
--- a/fastmcp_slim/fastmcp/server/providers/openapi/components.py
+++ b/fastmcp_slim/fastmcp/server/providers/openapi/components.py
@@ -18,6 +18,7 @@
     ResourceResult,
     ResourceTemplate,
 )
+from fastmcp.resources.template import template_param_key
 from fastmcp.server.dependencies import get_http_headers
 from fastmcp.tools.base import Tool, ToolResult
 from fastmcp.tools.function_tool import _strict_input_validation
@@ -451,7 +452,10 @@ async def create_resource(
             if parameter.name in params:
                 arguments[argument_name] = params[parameter.name]
                 continue
-            normalized_name = parameter.name.replace("-", "_")
+            # The matcher keys params by the sanitized group name; try that
+            # for parameter names the URI grammar allows but Python does not
+            # (e.g. `{$top}` matches as `_top`).
+            normalized_name = template_param_key(parameter.name)
             if normalized_name in params:
                 arguments[argument_name] = params[normalized_name]
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/tests/resources/test_resource_template.py b/tests/resources/test_resource_template.py
index 9cb3bd4ef1..fd264b7958 100644
--- a/tests/resources/test_resource_template.py
+++ b/tests/resources/test_resource_template.py
@@ -14,6 +14,7 @@
 from fastmcp.resources.template import (
     build_regex,
     expand_uri_template,
+    forward_uri,
     match_uri_template,
 )
 from fastmcp.resources.types import BinaryResource, TextResource
@@ -810,19 +811,21 @@ async def decorated_template(ctx: Context, item_id: int) -> str:
 class TestMalformedURITemplates:
     """Test that malformed URI templates from remote servers don't crash."""
 
-    @pytest.mark.parametrize(
-        "template",
-        [
-            "test://{1leading}/path",
-            "test://{123}/path",
-        ],
-        ids=[
-            "leading_digit",
-            "all_digits",
-        ],
-    )
-    def test_build_regex_returns_none_for_invalid_group_names(self, template: str):
-        assert build_regex(template) is None
+    def test_build_regex_sanitizes_leading_digit_group_names(self):
+        """A leading digit is not a valid regex group name, so it is prefixed
+        with an underscore instead of disabling the whole template (#6150)."""
+        regex = build_regex("test://{1leading}/path")
+        assert regex is not None
+        match = regex.match("test://alice/path")
+        assert match is not None
+        assert match.group("_1leading") == "alice"
+
+    def test_build_regex_handles_all_digit_names(self):
+        regex = build_regex("test://{123}/path")
+        assert regex is not None
+        match = regex.match("test://alice/path")
+        assert match is not None
+        assert match.group("_123") == "alice"
 
     def test_build_regex_normalizes_hyphens(self):
         """Hyphens in param names produce valid regex with underscored groups."""
@@ -984,11 +987,9 @@ def test_build_regex_returns_none_for_duplicate_group_names(self):
         "template",
         [
             "test://{a}/{a}/path",
-            "test://{1leading}/path",
         ],
         ids=[
             "duplicate_groups",
-            "leading_digit",
         ],
     )
     def test_match_uri_template_returns_none_for_malformed_templates(
@@ -996,6 +997,13 @@ def test_match_uri_template_returns_none_for_malformed_templates(
     ):
         assert match_uri_template("test://anything/path", template) is None
 
+    def test_match_uri_template_sanitizes_leading_digit_names(self):
+        """`{1leading}` used to disable the whole template; it now matches
+        under the sanitized group name (#6150)."""
+        assert match_uri_template("test://alice/path", "test://{1leading}/path") == {
+            "_1leading": "alice"
+        }
+
     def test_match_uri_template_normalizes_hyphens(self):
         """Hyphenated params match and return underscored keys."""
         result = match_uri_template("test://alice/path", "test://{user-id}/path")
@@ -1895,3 +1903,78 @@ def multi(id: str) -> list[ResourceContent]:
             component_meta,
             {**component_meta, "own": 1},
         ]
+
+
+class TestNonIdentifierTemplateVariableNames:
+    """Template variable names that are not Python identifiers still match.
+
+    OpenAPI path templates legally use names like `{$top}`, `x.y` or `1id`;
+    the matcher must sanitize them into valid regex group names instead of
+    giving up on the whole template (#6150). Consumers map sanitized keys
+    back onto route parameters through `template_param_key`.
+    """
+
+    @pytest.mark.parametrize(
+        ("uri_template", "uri", "expected"),
+        [
+            ("resource://dollar/{$top}", "resource://dollar/x", {"_top": "x"}),
+            ("resource://dot/{x.y}", "resource://dot/x", {"x_y": "x"}),
+            ("resource://digit/{1id}", "resource://digit/x", {"_1id": "x"}),
+            ("resource://users/{user-id}", "resource://users/7", {"user_id": "7"}),
+            ("resource://plain/{top}", "resource://plain/x", {"top": "x"}),
+            # `²` is a Unicode word char (\w) but not valid in an identifier.
+            ("resource://uni/{a²}", "resource://uni/x", {"a_": "x"}),
+        ],
+    )
+    def test_matches_non_identifier_names(self, uri_template, uri, expected):
+        assert match_uri_template(uri, uri_template) == expected
+
+    def test_build_regex_compiles_non_identifier_group_names(self):
+        regex = build_regex("resource://dollar/{$top}")
+        assert regex is not None
+        match = regex.match("resource://dollar/x")
+        assert match is not None
+        assert match.group("_top") == "x"
+
+    def test_wildcard_with_non_identifier_name(self):
+        assert match_uri_template(
+            "resource://dollar/a/b", "resource://dollar/{$top*}"
+        ) == {"_top": "a/b"}
+
+
+class TestExpandNonIdentifierNames:
+    """Forwarding (mount/proxy) expands placeholders from sanitized param
+    keys: params come back from match_uri_template keyed by
+    template_param_key, so {$top} must resolve from `_top` instead of being
+    forwarded literally (#6150, triage-reviewer follow-up)."""
+
+    @pytest.mark.parametrize(
+        "template, params, expected",
+        [
+            ("resource://dollar/{$top}", {"_top": "alice"}, "resource://dollar/alice"),
+            ("resource://dot/{x.y}", {"x_y": "alice"}, "resource://dot/alice"),
+            ("resource://digit/{1id}", {"_1id": "alice"}, "resource://digit/alice"),
+            ("resource://uni/{a²}", {"a_": "alice"}, "resource://uni/alice"),
+            # Controls: plain and hyphenated names behave as before.
+            ("resource://plain/{top}", {"top": "alice"}, "resource://plain/alice"),
+            (
+                "resource://users/{user-id}",
+                {"user_id": "7"},
+                "resource://users/7",
+            ),
+        ],
+    )
+    def test_expand_resolves_sanitized_keys(
+        self, template: str, params: dict[str, str], expected: str
+    ):
+        assert expand_uri_template(template, params) == expected
+
+    def test_forward_uri_resolves_sanitized_keys(self):
+        result = forward_uri(
+            "resource://dollar/{$top}", {"_top": "alice"}, "resource://dollar/alice?q=1"
+        )
+        assert result == "resource://dollar/alice?q=1"
+
+    def test_forward_uri_keeps_literal_when_unresolved(self):
+        result = forward_uri("resource://dollar/{$top}", {}, "resource://dollar/x")
+        assert result == "resource://dollar/{$top}"
diff --git a/tests/server/providers/openapi/test_openapi_features.py b/tests/server/providers/openapi/test_openapi_features.py
index 9ec9920c7a..9aae87720c 100644
--- a/tests/server/providers/openapi/test_openapi_features.py
+++ b/tests/server/providers/openapi/test_openapi_features.py
@@ -1577,3 +1577,71 @@ def handler(request):
             "petType": "cat",
             "meowVolume": 11,
         }
+
+
+class TestNonIdentifierPathParameterNames:
+    """Resource templates for path parameters whose names are not Python
+    identifiers stay readable (#6150). OpenAPI allows names like `{$top}`,
+    `x.y`, or `1id` in path templates."""
+
+    @pytest.fixture
+    def non_identifier_spec(self):
+        def get_op(op_id, param):
+            return {
+                "get": {
+                    "operationId": op_id,
+                    "summary": op_id,
+                    "parameters": [
+                        {
+                            "name": param,
+                            "in": "path",
+                            "required": True,
+                            "schema": {"type": "string"},
+                        }
+                    ],
+                    "responses": {"200": {"description": "ok"}},
+                }
+            }
+
+        return {
+            "openapi": "3.0.3",
+            "info": {"title": "t", "version": "1"},
+            "servers": [{"url": "https://api.example.com"}],
+            "paths": {
+                "/a/{top}": get_op("plain", "top"),
+                "/b/{$top}": get_op("dollar", "$top"),
+                "/c/{x.y}": get_op("dot", "x.y"),
+                "/d/{1id}": get_op("digit", "1id"),
+            },
+        }
+
+    async def test_non_identifier_path_params_listed_and_readable(
+        self, non_identifier_spec
+    ):
+        route_maps = [RouteMap(methods=["GET"], mcp_type=MCPType.RESOURCE_TEMPLATE)]
+
+        def respond(request: httpx2.Request) -> httpx2.Response:
+            return httpx2.Response(200, json={"path": request.url.path})
+
+        async with httpx2.AsyncClient(
+            base_url="https://api.example.com",
+            transport=httpx2.MockTransport(respond),
+        ) as client:
+            provider = OpenAPIProvider(
+                openapi_spec=non_identifier_spec, client=client, route_maps=route_maps
+            )
+            mcp = FastMCP("Test")
+            mcp.add_provider(provider)
+            async with Client(mcp) as mcp_client:
+                templates = await mcp_client.list_resource_templates()
+                assert len(templates) == 4
+
+                expected_paths = {
+                    "resource://plain/x": "/a/x",
+                    "resource://dollar/x": "/b/x",
+                    "resource://dot/x": "/c/x",
+                    "resource://digit/x": "/d/x",
+                }
+                for uri, path in expected_paths.items():
+                    result = (await mcp_client.read_resource(uri))[0]
+                    assert json.loads(result.text) == {"path": path}
```
</details>

---

## celery__celery-10598

**6/25** · [PR](https://github.com/celery/celery/pull/10598) · [issue #10576](https://github.com/celery/celery/issues/10576) · 175 FAIL_TO_PASS tests · ⚠️ **tests import a name introduced by the fix**

### Issue

Two callables sharing __name__ in one module collapse into one registered task, silently, and the two registration paths disagree about which survives
## Summary

A task's registered name is `f"{fun.__module__}.{fun.__name__}"` — `__qualname__` is never consulted. Two distinct callables that share `__name__` within one module therefore collapse into a single registered task, and a caller invoking the second one receives `SUCCESS` and the **first function's result**.

The two registration paths resolve the collision in **opposite directions**, and both are silent.

## Where

`celery/app/base.py`, `_task_from_fun`:

```python
name = name or self.gen_task_name(fun.__name__, fun.__module__)
...
if name not in self._tasks:
    ...
else:
    task = self._tasks[name]      # silently returns the other function's task
```

`celery/utils/imports.py`, `gen_task_name`:

```python
return '.'.join(p for p in (module_name, name) if p)
```

`celery/app/registry.py`, `TaskRegistry.register`: a plain `self[task.name] = task`, no membership check.

## Reproduction

```python
from celery import Celery
app = Celery('repro', broker='memory://', backend='cache+memory://')
app.conf.task_always_eager = True

def make_scaler(factor):
    @app.task
    def scale(x):
        return x * factor
    return scale

double = make_scaler(2)
triple = make_scaler(3)

r = triple.delay(10)
print(double.name, triple.name)       # repro.scale repro.scale
print(double is triple)               # False  -- two distinct proxy objects
print(r.status, r.get())              # SUCCESS 20   expected 30
```

Observed on Celery 5.6.2 (`e48dc8e`):

```
repro.scale repro.scale
False
SUCCESS 20        expected 30
warnings raised during registration: []
```

Not an artefact of eager mode — the same through a real worker over the memory broker:

```
registered names ending .scale: ['wp.scale']
worker path: result=20 (expected 30)
```

A second form, without closures — two classes in one module with same-named methods:

```
Alpha.handler.name = repro.handler
Beta.handler.name  = repro.handler
Beta.handler.delay(1) = 'alpha:1'    expected 'beta:1'
__qualname__ differs: Alpha.handler != Beta.handler
```

## The two paths disagree

```python
class T1(Task):
    name = 'dup'
    def run(self, x): return 'first'

class T2(Task):
    name = 'dup'
    def run(self, x): return 'second'

app.register_task(T1()); app.register_task(T2())
app.tasks['dup'].delay(0).get()      # 'second'
```

The decorator path keeps the **first**; `register_task` keeps the **last**. Which function actually runs under a colliding name depends on which API registered it. Neither announces anything.

## Negative controls

```
# A: explicit name= -> correct pairing
t3.delay(10) = 30    correct

# B: distinct __name__ -> correct pairing (near miss)
scale_b.delay(10) = 30    correct
```

Control B is the near miss: identical factory shape, only `__name__` differs, and it correctly does not trigger — so the failure is attributable to the name key, not to closures.

## The silence

- `warnings.simplefilter('always')` with `catch_warnings(record=True)` around both registrations: `[]`
- `logging.basicConfig(level=DEBUG)` over the whole run: 68 lines, none matching `duplic|collis|overwrit|already|conflict`
- exit code 0, `r.status == 'SUCCESS'`
- the returned proxy is a *distinct object* from the first task while dispatching to its body, so an identity check by the caller does not reveal it either

## What the docs say

`docs/userguide/tasks.rst`:

> Every task class has a unique name, and this name is referenced in messages
>
> **Every task must have a unique name.**
>
> A best practice is to use the module name as a name-space, this way names won't collide if there's already a task with that name defined in another module.

Uniqueness is stated as a requirement of the system. The remedy offered addresses collisions *across* modules; the within-module case cannot be fixed by module namespacing and is silently mis-paired.

## Note

`celery/exceptions.py` defines a public, exported, documented exception for exactly this condition:

```python
class AlreadyRegistered(Exception):
    """The task is already registered."""   # XXX Unused
```

It is never raised anywhere in the tree.

`_task_from_fun` also copies `fun.__qualname__` onto the task object about twenty lines after computing the name without it, so the disambiguating information is present at the point where it would be needed.

## Scope

The collision requires two same-named callables in one module. That arises in practice with task factories, decorated methods on multiple classes, and generated or plugin task modules — it is not exotic, but it is not the common case either.

I have not checked whether this has been discussed before; a pointer to an existing issue is welcome and I am happy to close this in favour of one.

## Version

Celery 5.6.2, source at `e48dc8e`, Python 3.12, `memory://` broker, `cache+memory://` backend.

### Files changed by the gold patch

- `celery/app/base.py` (+92 / -3)
- `celery/exceptions.py` (+7 / -1)

### Tests that must pass (names, deduplicated)

- `test_AsyncResult`
- `test_Beat`
- `test_Windows_log_color_disabled`
- `test_WorkController`
- `test_Worker`
- `test_acquire_connection_raises_on_pool_exhaustion`
- `test_acquire_connection_success_with_pool`
- `test_acquire_connection_without_pool`
- `test_acquire_producer_raises_on_pool_exhaustion`
- `test_acquire_producer_success`
- `test_add_defaults`
- `test_add_periodic_task`
- `test_add_periodic_task_expected_override`
- `test_add_periodic_task_unexpected_override`
- `test_after_fork`
- `test_after_fork_cleanup_app__raises`
- `test_amqp_failover_strategy_selection`
- `test_amqp_get_broker_info`
- `test_annotate_decorator`
- `test_app_pickler_accepts_legacy_arg_count`
- … 152 more

<details><summary>Gold patch</summary>

```diff
diff --git a/celery/app/base.py b/celery/app/base.py
index ff056fff74b..63b3e36a3f1 100644
--- a/celery/app/base.py
+++ b/celery/app/base.py
@@ -28,14 +28,14 @@
 from celery import platforms, signals
 from celery._state import (_announce_app_finalized, _deregister_app, _register_app, _set_current_app, _task_stack,
                            connect_on_app_finalize, get_current_app, get_current_worker_task, set_default_app)
-from celery.exceptions import AlwaysEagerIgnored, ImproperlyConfigured, OperationalError
+from celery.exceptions import AlwaysEagerIgnored, DuplicateTaskNameWarning, ImproperlyConfigured, OperationalError
 from celery.loaders import get_loader_cls
 from celery.local import PromiseProxy, maybe_evaluate
 from celery.utils import abstract
 from celery.utils.collections import AttributeDictMixin
 from celery.utils.dispatch import Signal
 from celery.utils.functional import first, head_from_fun, maybe_list
-from celery.utils.imports import gen_task_name, instantiate, symbol_by_name
+from celery.utils.imports import gen_task_name, instantiate, qualname, symbol_by_name
 from celery.utils.log import get_logger
 from celery.utils.objects import FallbackContext, mro_lookup
 from celery.utils.time import maybe_make_aware, timezone, to_utc
@@ -99,6 +99,44 @@ def _get_annotations(fun):
 """
 
 
+W_DUPTASK = """\
+Task name {0!r} is already registered to a different callable.
+
+Existing: {1}
+New:      {2}
+
+{3}
+
+Every task must have a unique name. Pass an explicit name= to the task \
+decorator, or rename one of the callables.\
+"""
+
+
+def frame_is_celery(frame):
+    """Return true if *frame* is executing Celery's own code."""
+    module = frame.f_globals.get('__name__', '')
+    return module == 'celery' or module.startswith('celery.')
+
+
+def caller_stacklevel():
+    """Depth of the first frame outside Celery, for :func:`warnings.warn`.
+
+    A task can be registered straight from the decorator or later, when a
+    :class:`~celery.local.PromiseProxy` is first evaluated, and those two
+    paths sit at different depths -- so the level is found rather than
+    assumed. Only reached when a warning is actually emitted.
+    """
+    frame, level = sys._getframe(1), 1
+    while frame is not None and frame_is_celery(frame):
+        frame, level = frame.f_back, level + 1
+    return level
+
+
+def task_callable_qualname(task):
+    """Name the callable behind *task*, decorated or class-based."""
+    return qualname(getattr(task, '_decorated_fun', None) or type(task))
+
+
 def app_has_custom(app, attr):
     """Return true if app has customized method `attr`.
 
@@ -388,6 +426,7 @@ def __init__(self, main=None, loader=None, backend=None,
         self.finalized = False
         self._finalize_mutex = threading.RLock()
         self._pending = deque()
+        self._duplicate_task_names_warned = set()
         self._tasks = tasks
         if not isinstance(self._tasks, TaskRegistry):
             self._tasks = self.registry_cls(self._tasks or {})
@@ -609,6 +648,10 @@ def _task_from_fun(
     ):
         if not self.finalized and not self.autofinalize:
             raise RuntimeError('Contract breach: app not finalized')
+        # the callable as the caller passed it, kept before the pydantic
+        # rebind below and before ``run`` turns it into a descriptor, so
+        # that a re-registration can be recognised by identity.
+        decorated_fun = fun
         name = name or self.gen_task_name(fun.__name__, fun.__module__)
         base = base or self.Task
 
@@ -626,7 +669,8 @@ def _task_from_fun(
                 '__module__': fun.__module__,
                 '__annotations__': _get_annotations(fun),
                 '__header__': self.type_checker(fun, bound=bind),
-                '__wrapped__': run}, **options))()
+                '__wrapped__': run,
+                '_decorated_fun': staticmethod(decorated_fun)}, **options))()
             # for some reason __qualname__ cannot be set in type()
             # so we have to set it here.
             try:
@@ -638,6 +682,7 @@ def _task_from_fun(
             add_autoretry_behaviour(task, **options)
         else:
             task = self._tasks[name]
+            self._warn_if_duplicate_task_name(task, decorated_fun, name)
         return task
 
     def register_task(self, task, **options):
@@ -653,12 +698,56 @@ def register_task(self, task, **options):
             task_cls = type(task)
             task.name = self.gen_task_name(
                 task_cls.__name__, task_cls.__module__)
+        existing = self.tasks.get(task.name)
+        if existing is not None and existing is not task:
+            self._warn_duplicate_task_name(
+                task.name, task_callable_qualname(existing),
+                task_callable_qualname(task),
+                'The new callable replaced the existing one; calls under this '
+                'name now reach the new callable.',
+            )
         add_autoretry_behaviour(task, **options)
         self.tasks[task.name] = task
         task._app = self
         task.bind(self)
         return task
 
+    def _warn_if_duplicate_task_name(self, task, fun, name):
+        """Warn when *name* is taken by a callable other than *fun*.
+
+        A module imported twice hands the same function object back, so
+        identity -- not the name -- is what tells a re-registration apart
+        from two distinct callables colliding under one generated name.
+        The comparison uses the callable as the caller passed it, since
+        ``__wrapped__`` holds ``run``, which is a bound method under
+        ``bind=True`` and the wrapper under ``pydantic=True``.
+        """
+        existing_fun = getattr(task, '_decorated_fun', None)
+        if existing_fun is None or existing_fun is fun:
+            return
+        self._warn_duplicate_task_name(
+            name, qualname(existing_fun), qualname(fun),
+            'The new callable was not registered; calls under this name '
+            'reach the callable registered first.',
+        )
+
+    def _warn_duplicate_task_name(self, name, existing, new, consequence):
+        # One warning per name. A colliding name is a single mistake, and
+        # a module or test suite that trips it repeatedly should not bury
+        # everything else in output. The set only grows, and a concurrent
+        # registration could race on this check and warn twice; both are
+        # accepted, as registration is an import-time, single-threaded
+        # activity and the cost of either is one extra line of output.
+        if name in self._duplicate_task_names_warned:
+            return
+        self._duplicate_task_names_warned.add(name)
+        warnings.warn(
+            DuplicateTaskNameWarning(
+                W_DUPTASK.format(name, existing, new, consequence),
+            ),
+            stacklevel=caller_stacklevel(),
+        )
+
     def gen_task_name(self, name, module):
         return gen_task_name(self, name, module)
 
diff --git a/celery/exceptions.py b/celery/exceptions.py
index 3203e9f49ea..9055cc0c272 100644
--- a/celery/exceptions.py
+++ b/celery/exceptions.py
@@ -42,6 +42,7 @@
     - :class:`~celery.exceptions.CeleryWarning`
         - :class:`~celery.exceptions.AlwaysEagerIgnored`
         - :class:`~celery.exceptions.DuplicateNodenameWarning`
+        - :class:`~celery.exceptions.DuplicateTaskNameWarning`
         - :class:`~celery.exceptions.FixupWarning`
         - :class:`~celery.exceptions.NotConfigured`
         - :class:`~celery.exceptions.SecurityWarning`
@@ -62,7 +63,8 @@
     # Warnings
     'CeleryWarning',
     'AlwaysEagerIgnored', 'DuplicateNodenameWarning',
-    'FixupWarning', 'NotConfigured', 'SecurityWarning',
+    'DuplicateTaskNameWarning', 'FixupWarning', 'NotConfigured',
+    'SecurityWarning',
 
     # Core errors
     'CeleryError',
@@ -122,6 +124,10 @@ class DuplicateNodenameWarning(CeleryWarning):
     """Multiple workers are using the same nodename."""
 
 
+class DuplicateTaskNameWarning(CeleryWarning):
+    """Multiple callables are registered under the same task name."""
+
+
 class FixupWarning(CeleryWarning):
     """Fixup related warning."""
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/t/unit/app/test_app.py b/t/unit/app/test_app.py
index ec102844dd1..cac475028ce 100644
--- a/t/unit/app/test_app.py
+++ b/t/unit/app/test_app.py
@@ -7,6 +7,7 @@
 import sys
 import typing
 import uuid
+import warnings
 from copy import deepcopy
 from datetime import datetime, timedelta
 from datetime import timezone as datetime_timezone
@@ -18,7 +19,9 @@
 import pytest
 from kombu import Exchange, Queue
 from kombu.exceptions import LimitExceeded
-from pydantic import BaseModel, ValidationInfo, model_validator
+from pydantic import BaseModel
+from pydantic import BaseModel as PydanticBaseModel
+from pydantic import ValidationInfo, model_validator
 from vine import promise
 
 from celery import Celery, _state
@@ -29,7 +32,7 @@
 from celery.app.amqp import AMQP
 from celery.backends.base import Backend
 from celery.contrib.testing.mocks import ContextMock
-from celery.exceptions import ImproperlyConfigured, OperationalError
+from celery.exceptions import DuplicateTaskNameWarning, ImproperlyConfigured, OperationalError
 from celery.loaders.base import unconfigured
 from celery.platforms import pyimplementation
 from celery.utils.collections import DictAttribute
@@ -147,6 +150,220 @@ def test_setup_security(self, setup_security):
             {'json'}, 'key', None, 'cert', 'store', 'digest', 'serializer',
             app=self.app)
 
+    def test_duplicate_task_name_warns__closure(self):
+        """Two closures share __name__, __qualname__ and __code__."""
+        def make_scaler(factor):
+            @self.app.task(shared=False)
+            def scale(x):
+                return x * factor
+            return scale
+
+        with pytest.warns(DuplicateTaskNameWarning) as w:
+            double, triple = make_scaler(2), make_scaler(3)
+            assert double.name == triple.name
+
+        assert double.name in str(w[0].message)
+
+    def test_duplicate_task_name_warns__same_method_name(self):
+        with pytest.warns(DuplicateTaskNameWarning):
+            class Alpha:
+                @staticmethod
+                @self.app.task(shared=False)
+                def handler(x):
+                    return 'alpha'
+
+            class Beta:
+                @staticmethod
+                @self.app.task(shared=False)
+                def handler(x):
+                    return 'beta'
+
+            assert Alpha.handler.name == Beta.handler.name
+
+    def test_duplicate_task_name_warns__register_task(self):
+        from celery.app.task import Task
+
+        class T1(Task):
+            name = 'dup'
+
+            def run(self, x):
+                return 'first'
+
+        class T2(Task):
+            name = 'dup'
+
+            def run(self, x):
+                return 'second'
+
+        self.app.register_task(T1())
+        with pytest.warns(DuplicateTaskNameWarning) as w:
+            self.app.register_task(T2())
+        assert 'replaced' in str(w[0].message)
+
+    def test_duplicate_task_name_warns_once_per_name(self):
+        """A third callable under the same name must not warn again."""
+        def make_scaler(factor):
+            @self.app.task(shared=False)
+            def scale(x):
+                return x * factor
+            return scale
+
+        with pytest.warns(DuplicateTaskNameWarning) as w:
+            first, second = make_scaler(2), make_scaler(3)
+            assert first.name == second.name
+
+        with warnings.catch_warnings(record=True) as again:
+            warnings.simplefilter('always')
+            third = make_scaler(4)
+            assert third.name == first.name
+        assert len(w) == 1
+        assert not [x for x in again
+                    if isinstance(x.message, DuplicateTaskNameWarning)]
+
+    def test_duplicate_task_name_silent__no_recorded_callable(self):
+        """A task registered by class carries no callable to compare."""
+        from celery.app.task import Task
+
+        class T(Task):
+            name = 'shared.name'
+
+            def run(self, x):
+                return x
+
+        self.app.register_task(T())
+
+        def other(x):
+            return x
+
+        with warnings.catch_warnings(record=True) as w:
+            warnings.simplefilter('always')
+            task = self.app._task_from_fun(other, name='shared.name')
+            assert task.name == 'shared.name'
+        assert not [x for x in w
+                    if isinstance(x.message, DuplicateTaskNameWarning)]
+
+    def test_duplicate_task_name_register_task_names_the_function(self):
+        """register_task reports a decorated task by its function."""
+        @self.app.task(name='taken.name', shared=False)
+        def decorated(x):
+            return x
+
+        assert decorated.name == 'taken.name'
+
+        from celery.app.task import Task
+
+        class T(Task):
+            name = 'taken.name'
+
+            def run(self, x):
+                return x
+
+        with pytest.warns(DuplicateTaskNameWarning) as w:
+            self.app.register_task(T())
+        assert 'decorated' in str(w[0].message)
+
+    def test_duplicate_task_name_silent__explicit_names(self):
+        """Negative control: distinct explicit names must not warn."""
+        def make_scaler(factor):
+            @self.app.task(name=f'scale{factor}', shared=False)
+            def scale(x):
+                return x * factor
+            return scale
+
+        with warnings.catch_warnings(record=True) as w:
+            warnings.simplefilter('always')
+            double, triple = make_scaler(2), make_scaler(3)
+            assert double.name != triple.name
+        assert not [x for x in w
+                    if isinstance(x.message, DuplicateTaskNameWarning)]
+
+    def test_duplicate_task_name_silent__distinct_names(self):
+        """Negative control (near miss): only __name__ differs."""
+        with warnings.catch_warnings(record=True) as w:
+            warnings.simplefilter('always')
+
+            @self.app.task(shared=False)
+            def scale_a(x):
+                return x * 2
+
+            @self.app.task(shared=False)
+            def scale_b(x):
+                return x * 3
+
+            assert scale_a.name != scale_b.name
+        assert not [x for x in w
+                    if isinstance(x.message, DuplicateTaskNameWarning)]
+
+    def test_duplicate_task_name_silent__same_function_twice_bound(self):
+        """Negative control: ``run`` is a bound method under bind=True."""
+        def plain(x):
+            return x
+
+        with warnings.catch_warnings(record=True) as w:
+            warnings.simplefilter('always')
+            first = self.app._task_from_fun(plain, bind=True)
+            second = self.app._task_from_fun(plain, bind=True)
+            assert first is second
+        assert not [x for x in w
+                    if isinstance(x.message, DuplicateTaskNameWarning)]
+
+    def test_duplicate_task_name_silent__same_function_twice_pydantic(self):
+        """Negative control: ``fun`` is rebound by the pydantic wrapper."""
+        class Args(PydanticBaseModel):
+            x: int
+
+        def pydantic_fun(args: Args):
+            return args.x
+
+        with warnings.catch_warnings(record=True) as w:
+            warnings.simplefilter('always')
+            first = self.app._task_from_fun(pydantic_fun, pydantic=True)
+            second = self.app._task_from_fun(pydantic_fun, pydantic=True)
+            assert first is second
+        assert not [x for x in w
+                    if isinstance(x.message, DuplicateTaskNameWarning)]
+
+    def test_duplicate_task_name_warns__bound_closures(self):
+        """bind=True must still detect two distinct callables."""
+        def make_scaler(factor):
+            @self.app.task(shared=False, bind=True)
+            def scale(self, x):
+                return x * factor
+            return scale
+
+        with pytest.warns(DuplicateTaskNameWarning):
+            double, triple = make_scaler(2), make_scaler(3)
+            assert double.name == triple.name
+
+    def test_duplicate_task_name_warning_points_at_the_caller(self):
+        """The warning must name the caller's frame, not celery's."""
+        def make_scaler(factor):
+            @self.app.task(shared=False)
+            def scale(x):
+                return x * factor
+            return scale
+
+        with pytest.warns(DuplicateTaskNameWarning) as w:
+            double, triple = make_scaler(2), make_scaler(3)
+            assert double.name == triple.name
+
+        assert not w[0].filename.endswith(
+            os.path.join('celery', 'app', 'base.py'))
+        assert w[0].filename == __file__
+
+    def test_duplicate_task_name_silent__same_function_twice(self):
+        """Negative control: a re-imported module yields the same object."""
+        def plain(x):
+            return x
+
+        with warnings.catch_warnings(record=True) as w:
+            warnings.simplefilter('always')
+            first = self.app._task_from_fun(plain)
+            second = self.app._task_from_fun(plain)
+            assert first is second
+        assert not [x for x in w
+                    if isinstance(x.message, DuplicateTaskNameWarning)]
+
     def test_task_autofinalize_disabled(self):
         with self.Celery('xyzibari', autofinalize=False) as app:
             @app.task
```
</details>

---

## celery__celery-10605

**7/25** · [PR](https://github.com/celery/celery/pull/10605) · [issue #8887](https://github.com/celery/celery/issues/8887) · 7 FAIL_TO_PASS tests

### Issue

Stamping doesn't work with database result backend
<!--
Please fill this template entirely and do not erase parts of it.
We reserve the right to close without a response
bug reports which are incomplete.
-->
# Checklist
<!--
To check an item on the list replace [ ] with [x].
-->
- [x] I have verified that the issue exists against the `main` branch of Celery.
- [ ] This has already been asked to the [discussions forum](https://github.com/celery/celery/discussions) first.
- [x] I have read the relevant section in the
  [contribution guide](https://docs.celeryq.dev/en/main/contributing.html#other-bugs)
  on reporting bugs.
- [x] I have checked the [issues list](https://github.com/celery/celery/issues?q=is%3Aissue+label%3A%22Issue+Type%3A+Bug+Report%22+-label%3A%22Category%3A+Documentation%22)
  for similar or identical bug reports.
- [x] I have checked the [pull requests list](https://github.com/celery/celery/pulls?q=is%3Apr+label%3A%22PR+Type%3A+Bugfix%22+-label%3A%22Category%3A+Documentation%22)
  for existing proposed fixes.
- [ ] I have checked the [commit log](https://github.com/celery/celery/commits/main)
  to find out if the bug was already fixed in the main branch.
- [x] I have included all related issues and possible duplicate issues
  in this issue (If there are none, check this box anyway).

## Mandatory Debugging Information

- [x] I have included the output of ``celery -A proj report`` in the issue.
    (if you are not able to do this, then at least specify the Celery
     version affected).
- [x] I have verified that the issue exists against the `main` branch of Celery.
- [x] I have included the contents of ``pip freeze`` in the issue.
- [x] I have included all the versions of all the external dependencies required
  to reproduce this bug.

## Optional Debugging Information
<!--
Try some of the below if you think they are relevant.
It will help us figure out the scope of the bug and how many users it affects.
-->
- [ ] I have tried reproducing the issue on more than one Python version
  and/or implementation.
- [x] I have tried reproducing the issue on more than one message broker and/or
  result backend.
- [ ] I have tried reproducing the issue on more than one version of the message
  broker and/or result backend.
- [ ] I have tried reproducing the issue on more than one operating system.
- [ ] I have tried reproducing the issue on more than one workers pool.
- [ ] I have tried reproducing the issue with autoscaling, retries,
  ETA/Countdown & rate limits disabled.
- [ ] I have tried reproducing the issue after downgrading
  and/or upgrading Celery and its dependencies.

## Related Issues and Possible Duplicates
<!--
Please make sure to search and mention any related issues
or possible duplicates to this issue as requested by the checklist above.

This may or may not include issues in other repositories that the Celery project
maintains or other repositories that are dependencies of Celery.

If you don't know how to mention issues, please refer to Github's documentation
on the subject: https://help.github.com/en/articles/autolinked-references-and-urls#issues-and-pull-requests
-->

#### Related Issues

- None

#### Possible Duplicates

- None

## Environment & Settings
<!-- Include the contents of celery --version below -->
**Celery version**: 5.3.6, 5.4.0rc1 (opalescent)
<!-- Include the output of celery -A proj report below -->
<details>
<summary><b><code>celery report</code> Output:</b></summary>
<p>

```
software -> celery:5.4.0rc1 (opalescent) kombu:5.3.5 py:3.11.4
            billiard:4.2.0 py-amqp:5.2.0
platform -> system:Darwin arch:64bit
            kernel version:23.1.0 imp:CPython
loader   -> celery.loaders.app.AppLoader
settings -> transport:amqp results:db+postgresql:///stamp_issue

broker_url: 'amqp://guest:********@localhost:5672//'
deprecated_settings: None
task_default_queue: 'stamp_issue_queue'
result_extended: True
result_backend: 'db+postgresql:///stamp_issue'
```

</p>
</details>

# Steps to Reproduce

## Required Dependencies
<!-- Please fill the required dependencies to reproduce this issue -->
- **Minimal Python Version**: N/A or Unknown
- **Minimal Celery Version**: N/A or Unknown
- **Minimal Kombu Version**: N/A or Unknown
- **Minimal Broker Version**: N/A or Unknown
- **Minimal Result Backend Version**: N/A or Unknown
- **Minimal OS and/or Kernel Version**: N/A or Unknown
- **Minimal Broker Client Version**: N/A or Unknown
- **Minimal Result Backend Client Version**: N/A or Unknown

### Python Packages
<!-- Please fill the contents of pip freeze below -->
<details>
<summary><b><code>pip freeze</code> Output:</b></summary>
<p>

```
amqp==5.2.0
async-timeout==4.0.3
billiard==4.2.0
celery @ git+https://github.com/celery/celery.git@9edeab6b4526a59bf699df10f1b48ac65809eaea
click==8.1.7
click-didyoumean==0.3.0
click-plugins==1.1.1
click-repl==0.3.0
greenlet==3.0.3
kombu==5.3.5
prompt-toolkit==3.0.43
psycopg2==2.9.9
python-dateutil==2.9.0.post0
redis==5.0.2
six==1.16.0
SQLAlchemy==2.0.27
typing_extensions==4.10.0
tzdata==2024.1
vine==5.1.0
wcwidth==0.2.13
```

</p>
</details>

### Other Dependencies
<!--
Please provide system dependencies, configuration files
and other dependency information if applicable
-->
<details>
<p>
PostgreSQL database:

```
createdb stamp_issue
```

</p>
</details>

## Minimally Reproducible Test Case
<!--
Please provide a reproducible test case.
Refer to the Reporting Bugs section in our contribution guide.

We prefer submitting test cases in the form of a PR to our integration test suite.
If you can provide one, please mention the PR number below.
If not, please attach the most minimal code example required to reproduce the issue below.
If the test case is too large, please include a link to a gist or a repository below.
-->

<details>
<p>

Stamping works with the redis result backend, but not with the database backend or the rpc backend. (The rpc backend is not suitable for me, but I tested it for completeness).

`stamp_issue.py`:
```python
from celery import Celery
from celery.canvas import group

app = Celery("stamp_issue", broker="amqp://guest@localhost:5672/")
app.conf.task_default_queue = "stamp_issue_queue"
app.conf.result_extended = True
# app.conf.result_backend = "rpc://"                       # doesn't work
# app.conf.result_backend = "redis://localhost/0"          # works
app.conf.result_backend = "db+postgresql:///stamp_issue"   # doesn't work


@app.task
def add(x, y):
    return x + y


if __name__ == "__main__":
    sig1 = add.si(2, 2)
    sig1_res = sig1.freeze()
    g = group(sig1, add.si(3, 3))
    g.stamp(stamp="your_custom_stamp")
    res = g.apply_async()
    print(res.get())
    print(sig1_res._get_task_meta()["stamp"])
```

1. Start worker: `celery -A stamp_issue worker --loglevel=INFO --hostname stamp_issue`
2. Run example: `python stamp_issue.py`

</p>
</details>

# Expected Behavior
The output

```
[4, 6]
your_custom_stamp
```

# Actual Behavior
<!--
Describe in detail what actually happened.
Please include a backtrace and surround it with triple backticks (```).
In addition, include the Celery daemon logs, the broker logs,
the result backend logs and system logs below if they will help us debug
the issue.
-->
```
[4, 6]
Traceback (most recent call last):
  File "/Users/.../stamp_issue.py", line 24, in <module>
    print(sig1_res._get_task_meta()["stamp"])
          ~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^
KeyError: 'stamp'
```

### Files changed by the gold patch

- `celery/backends/database/__init__.py` (+42 / -11)
- `celery/backends/database/models.py` (+6 / -0)
- `docs/userguide/configuration.rst` (+12 / -1)

### Tests that must pass (names, deduplicated)

- `test_stamped_signature_roundtrip_with_async_result`
- `test_store_result_stamps_header_missing_from_meta`
- `test_store_result_stamps_missing_column_graceful_fallback`
- `test_store_result_stamps_only_headers_without_stamps`
- `test_store_result_stamps_only_stamps_without_headers`
- `test_store_result_with_stamps`
- `test_task_extended_to_dict_tolerant_of_stamps_error`

<details><summary>Gold patch</summary>

```diff
diff --git a/celery/backends/database/__init__.py b/celery/backends/database/__init__.py
index d2a50fe2a09..81a41f4efbc 100644
--- a/celery/backends/database/__init__.py
+++ b/celery/backends/database/__init__.py
@@ -17,6 +17,7 @@
 
 try:
     from sqlalchemy.exc import DatabaseError, InterfaceError, InvalidRequestError
+    from sqlalchemy.orm import defer
     from sqlalchemy.orm.exc import StaleDataError
 except ImportError:
     raise ImproperlyConfigured(
@@ -137,21 +138,26 @@ def ResultSession(self, session_manager=None):
             **self.engine_options)
 
     def _query_task(self, session, task_id):
-        """Query task by id, falling back to deferring children if missing from database."""
+        """Query task by id, falling back to deferring missing columns from database."""
         try:
             tasks = list(session.query(self.task_cls).filter(self.task_cls.task_id == task_id))
             return tasks and tasks[0]
         except DatabaseError as exc:
-            if 'children' in str(exc).lower():
-                from sqlalchemy.orm import defer
-                tasks = list(session.query(self.task_cls).options(
-                    defer(self.task_cls.children)
-                ).filter(self.task_cls.task_id == task_id))
+            exc_str = str(exc).lower()
+            defers = []
+            if 'children' in exc_str and hasattr(self.task_cls, 'children'):
+                defers.append(defer(self.task_cls.children))
+            if 'stamps' in exc_str and hasattr(self.task_cls, 'stamps'):
+                defers.append(defer(self.task_cls.stamps))
+            if defers:
+                tasks = list(session.query(self.task_cls).options(*defers).filter(
+                    self.task_cls.task_id == task_id
+                ))
                 return tasks and tasks[0]
             raise
 
-    def _store_result(self, task_id, result, state,
-                      traceback=None, request=None, **kwargs):
+    def _store_result(self, task_id, result, state, traceback=None,
+                      request=None, **kwargs):
         """Store return value and state of an executed task."""
         session = self.ResultSession()
         with session_cleanup(session):
@@ -172,10 +178,10 @@ def _update_result(self, task, result, state, traceback=None,
                                      traceback=traceback, request=request,
                                      format_date=False, encode=True)
 
-        # Exclude the primary key id, task_id, and children columns
-        # as we should not set it None or handle children separately
+        # Exclude the primary key id, task_id, children, and stamps columns
+        # as we should not set it None or handle them separately
         columns = [column.name for column in self.task_cls.__table__.columns
-                   if column.name not in {'id', 'task_id', 'children'}]
+                   if column.name not in {'id', 'task_id', 'children', 'stamps'}]
 
         # Iterate through the columns name of the table
         # to set the value from meta.
@@ -191,6 +197,20 @@ def _update_result(self, task, result, state, traceback=None,
             else:
                 setattr(task, 'children', None)
 
+        if hasattr(task, 'stamps') and 'stamps' in self.task_cls.__table__.columns:
+            stamped_headers = meta.get('stamped_headers')
+            if stamped_headers:
+                stamps_data = {
+                    h: meta.get(h) for h in stamped_headers if h in meta
+                }
+                stamps_info = {
+                    'stamped_headers': stamped_headers,
+                    'stamps': stamps_data,
+                }
+                setattr(task, 'stamps', ensure_bytes(self.encode(stamps_info)))
+            elif getattr(task, 'stamps', None) is None:
+                setattr(task, 'stamps', None)
+
     def _get_task_meta_for(self, task_id):
         """Get task meta-data for a task by id."""
         session = self.ResultSession()
@@ -208,6 +228,17 @@ def _get_task_meta_for(self, task_id):
                 data['kwargs'] = self.decode(data['kwargs'])
             if data.get('children', None) is not None:
                 data['children'] = self.decode(data['children'])
+            raw_stamps = data.pop('stamps', None)
+            if raw_stamps is not None:
+                try:
+                    stamps_info = self.decode(raw_stamps)
+                    if isinstance(stamps_info, dict):
+                        if 'stamped_headers' in stamps_info:
+                            data['stamped_headers'] = stamps_info['stamped_headers']
+                        if 'stamps' in stamps_info and isinstance(stamps_info['stamps'], dict):
+                            data.update(stamps_info['stamps'])
+                except Exception:
+                    pass
             return self.meta_from_decoded(data)
 
     def _decode_stored_result(self, payload):
diff --git a/celery/backends/database/models.py b/celery/backends/database/models.py
index 4bcf90ef8dd..3c6e0fc9969 100644
--- a/celery/backends/database/models.py
+++ b/celery/backends/database/models.py
@@ -78,9 +78,14 @@ class TaskExtended(Task):
     worker = sa.Column(sa.String(155), nullable=True)
     retries = sa.Column(sa.Integer, nullable=True)
     queue = sa.Column(sa.String(155), nullable=True)
+    stamps = sa.Column(sa.LargeBinary, nullable=True)
 
     def to_dict(self):
         task_dict = super().to_dict()
+        try:
+            stamps = self.stamps
+        except Exception:
+            stamps = None
         task_dict.update({
             'name': self.name,
             'args': self.args,
@@ -88,6 +93,7 @@ def to_dict(self):
             'worker': self.worker,
             'retries': self.retries,
             'queue': self.queue,
+            'stamps': stamps,
         })
         return task_dict
 
diff --git a/docs/userguide/configuration.rst b/docs/userguide/configuration.rst
index 5c18241ae71..e4d4cbb548d 100644
--- a/docs/userguide/configuration.rst
+++ b/docs/userguide/configuration.rst
@@ -1003,7 +1003,18 @@ and client first and turn the setting on afterwards.
 Default: ``False``
 
 Enables extended task result attributes (name, args, kwargs, worker,
-retries, queue) to be written to backend.
+retries, queue, stamps) to be written to backend.
+
+.. versionadded:: 5.7
+    Added storing task stamping metadata (``stamps``) in the database backend.
+
+.. note::
+
+    When using the database backend with :setting:`result_extended` set to ``True``,
+    task stamping metadata is stored in a ``stamps`` column. For existing database deployments
+    upgrading with an already-created ``celery_taskmeta`` table, operators must execute the
+    appropriate DDL migration to add the column before upgrading (e.g., ``ALTER TABLE celery_taskmeta ADD COLUMN stamps BLOB;``
+    or ``BYTEA`` on PostgreSQL); this migration is required as result writes will otherwise fail.
 
 .. setting:: result_expires
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/t/unit/backends/test_database.py b/t/unit/backends/test_database.py
index 3c45aa3cd83..e404d01c3fc 100644
--- a/t/unit/backends/test_database.py
+++ b/t/unit/backends/test_database.py
@@ -5,6 +5,7 @@
 from unittest.mock import Mock, patch
 
 import pytest
+from kombu.utils.encoding import ensure_bytes
 
 from celery import states, uuid
 from celery.app.task import Context
@@ -937,6 +938,207 @@ def test_store_none_result(self, result_serializer, args, kwargs):
         assert meta['retries'] == 2
         assert meta['worker'] == "celery@worker_1"
 
+    @pytest.mark.parametrize(
+        'result_serializer',
+        ['pickle', 'json'],
+        ids=['using pickle', 'using json']
+    )
+    def test_store_result_with_stamps(self, result_serializer):
+        self.app.conf.result_serializer = result_serializer
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+
+        request = Context(args=(1, 2), kwargs={'foo': 'bar'},
+                          task='mytask', retries=2,
+                          hostname='celery@worker_1',
+                          delivery_info={'routing_key': 'celery'},
+                          stamped_headers=['stamp1', 'stamp2'],
+                          stamps={'stamp1': ['val1'], 'stamp2': 'val2'})
+
+        tb.store_result(tid, {'fizz': 'buzz'}, states.SUCCESS, request=request)
+        meta = tb.get_task_meta(tid)
+
+        assert meta['result'] == {'fizz': 'buzz'}
+        assert meta['stamped_headers'] == ['stamp1', 'stamp2']
+        assert meta['stamp1'] == ['val1']
+        assert meta['stamp2'] == 'val2'
+        # Matches BaseBackend: stamps are flattened, and 'stamps' key is never leaked
+        assert 'stamps' not in meta
+
+    def test_store_result_without_stamps(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+
+        request = Context(args=(1, 2), kwargs={'foo': 'bar'},
+                          task='mytask', retries=2,
+                          hostname='celery@worker_1',
+                          delivery_info={'routing_key': 'celery'})
+
+        tb.store_result(tid, {'fizz': 'buzz'}, states.SUCCESS, request=request)
+        meta = tb.get_task_meta(tid)
+
+        assert meta['result'] == {'fizz': 'buzz'}
+        assert 'stamps' not in meta
+        assert 'stamped_headers' not in meta
+
+    def test_store_result_stamps_header_missing_from_meta(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        request = Context(args=(), kwargs={}, task='mytask',
+                          stamped_headers=['stamp1', 'stamp_missing'],
+                          stamps={'stamp1': 'val1'})
+        tb.store_result(tid, 'res', states.SUCCESS, request=request)
+        meta = tb.get_task_meta(tid)
+        assert meta['stamp1'] == 'val1'
+        assert 'stamp_missing' not in meta
+        assert meta['stamped_headers'] == ['stamp1', 'stamp_missing']
+        assert 'stamps' not in meta
+
+    def test_store_result_stamps_corrupt_non_dict_payload(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        request = Context(args=(), kwargs={}, task='mytask',
+                          stamped_headers=['stamp1'],
+                          stamps={'stamp1': 'val1'})
+        tb.store_result(tid, 'res', states.SUCCESS, request=request)
+        session = tb.ResultSession()
+        task = session.query(tb.task_cls).filter(tb.task_cls.task_id == tid).first()
+        task.stamps = ensure_bytes(tb.encode("not-a-dict"))
+        session.commit()
+        session.close()
+        tb._cache.clear()
+        meta = tb.get_task_meta(tid)
+        assert meta['result'] == 'res'
+        # Corrupt / non-dict payload fails closed and never leaks raw bytes into meta
+        assert 'stamps' not in meta
+
+    def test_store_result_stamps_only_stamps_without_headers(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        request = Context(args=(), kwargs={}, task='mytask')
+        tb.store_result(tid, 'res', states.SUCCESS, request=request)
+        session = tb.ResultSession()
+        task = session.query(tb.task_cls).filter(tb.task_cls.task_id == tid).first()
+        task.stamps = ensure_bytes(tb.encode({'stamps': {'only_stamps': 'value'}}))
+        session.commit()
+        session.close()
+        tb._cache.clear()
+        meta = tb.get_task_meta(tid)
+        assert meta['only_stamps'] == 'value'
+        assert 'stamped_headers' not in meta
+        assert 'stamps' not in meta
+
+    def test_store_result_stamps_only_headers_without_stamps(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        request = Context(args=(), kwargs={}, task='mytask')
+        tb.store_result(tid, 'res', states.SUCCESS, request=request)
+        session = tb.ResultSession()
+        task = session.query(tb.task_cls).filter(tb.task_cls.task_id == tid).first()
+        task.stamps = ensure_bytes(tb.encode({'stamped_headers': ['only_header']}))
+        session.commit()
+        session.close()
+        tb._cache.clear()
+        meta = tb.get_task_meta(tid)
+        assert meta['stamped_headers'] == ['only_header']
+        assert 'stamps' not in meta
+
+    def test_store_result_stamps_disabled_when_result_extended_false(self):
+        self.app.conf.result_extended = False
+        tb = DatabaseBackend(self.uri, app=self.app)
+        assert tb.task_cls is Task
+        assert not hasattr(Task, 'stamps')
+        tid = uuid()
+        request = Context(stamped_headers=['stamp1'], stamps={'stamp1': 'val1'})
+        tb.store_result(tid, 'res', states.SUCCESS, request=request)
+        meta = tb.get_task_meta(tid)
+        assert 'stamp1' not in meta
+        assert 'stamped_headers' not in meta
+        assert 'stamps' not in meta
+
+    def test_store_result_stamps_missing_column_graceful_fallback(self):
+        from sqlalchemy.exc import DatabaseError
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        tb.store_result(tid, 'res', states.SUCCESS)
+
+        session = tb.ResultSession()
+
+        # When DatabaseError occurs with 'stamps', _query_task defers the column
+        with patch.object(session, 'query') as mock_query:
+            first_mock = Mock()
+            first_mock.filter.side_effect = DatabaseError(
+                "SELECT celery_taskmeta.stamps", None, Exception("no such column: celery_taskmeta.stamps")
+            )
+            second_mock = Mock()
+            second_filter = Mock()
+            second_filter.return_value = [tb.task_cls(tid)]
+            second_mock.filter = second_filter
+            first_mock.options.side_effect = lambda opt: second_mock
+
+            mock_query.return_value = first_mock
+            task = tb._query_task(session, tid)
+            assert task is not None
+            assert task.task_id == tid
+
+    def test_stamped_signature_roundtrip_with_async_result(self):
+        from celery.canvas import signature
+        from celery.result import AsyncResult
+
+        tb = DatabaseBackend(self.uri, app=self.app)
+        sig = signature('mytask')
+        sig.stamp(stamp_key='stamp_value', custom_run_id=123)
+
+        tid = uuid()
+        request = Context(
+            task='mytask',
+            stamped_headers=sig.options['stamped_headers'],
+            stamps={h: sig.options[h] for h in sig.options['stamped_headers'] if h in sig.options}
+        )
+
+        tb.store_result(tid, {'status': 'completed'}, states.SUCCESS, request=request)
+        async_res = AsyncResult(tid, backend=tb)
+        assert async_res.result == {'status': 'completed'}
+        assert async_res.state == states.SUCCESS
+
+        meta = tb.get_task_meta(tid)
+        assert meta['stamp_key'] == 'stamp_value'
+        assert meta['custom_run_id'] == 123
+        assert set(meta['stamped_headers']) == {'stamp_key', 'custom_run_id'}
+        assert 'stamps' not in meta
+
+    def test_store_result_stamps_corrupt_unpicklable_decode_error(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        request = Context(args=(), kwargs={}, task='mytask')
+        tb.store_result(tid, 'res', states.SUCCESS, request=request)
+        session = tb.ResultSession()
+        task = session.query(tb.task_cls).filter(tb.task_cls.task_id == tid).first()
+        task.stamps = b'corrupt-unpicklable-blob'
+        session.commit()
+        session.close()
+        tb._cache.clear()
+        meta = tb.get_task_meta(tid)
+        assert meta['result'] == 'res'
+        assert 'stamps' not in meta
+
+    def test_task_extended_to_dict_tolerant_of_stamps_error(self):
+        from unittest.mock import PropertyMock
+
+        from celery.backends.database.models import TaskExtended
+        task = TaskExtended('test-task')
+        with patch.object(TaskExtended, 'stamps', new_callable=PropertyMock, side_effect=Exception("error")):
+            d = task.to_dict()
+            assert d['stamps'] is None
+
+    def test_query_task_unrelated_database_error_raises(self):
+        from sqlalchemy.exc import DatabaseError
+        tb = DatabaseBackend(self.uri, app=self.app)
+        session = Mock()
+        session.query.side_effect = DatabaseError("SELECT", {}, Exception("unrelated connection lost"))
+        with pytest.raises(DatabaseError):
+            tb._query_task(session, 'some-id')
+
     @pytest.mark.parametrize(
         'result_serializer, args, kwargs',
         [
```
</details>

---

## celery__celery-10606

**8/25** · [PR](https://github.com/celery/celery/pull/10606) · [issue #8336](https://github.com/celery/celery/issues/8336) · 8 FAIL_TO_PASS tests

### Issue

database backend does not store children
The [`Task`](https://github.com/celery/celery/blob/main/celery/backends/database/models.py#L20-L27) and [`TaskExtended`](https://github.com/celery/celery/blob/main/celery/backends/database/models.py#L57-L62) models for the `database` backend do not include `children`. This means that when using any `database` backend, [`AsyncResult.children`](https://github.com/celery/celery/blob/main/celery/result.py#L424) is always empty, even if a task does have children.

### Files changed by the gold patch

- `celery/backends/database/__init__.py` (+30 / -9)
- `celery/backends/database/models.py` (+6 / -0)
- `celery/backends/database/session.py` (+36 / -1)
- `docs/userguide/configuration.rst` (+13 / -0)

### Tests that must pass (names, deduplicated)

- `test_async_result_children`
- `test_migrate_missing_columns`
- `test_migrate_missing_columns_failure_logs_warning_and_degrades_gracefully`
- `test_migrate_missing_columns_ignores_exceptions`
- `test_migrate_missing_columns_when_table_not_exists`
- `test_query_task_fallback_on_operational_error`
- `test_store_result_no_children`
- `test_store_result_with_children`

<details><summary>Gold patch</summary>

```diff
diff --git a/celery/backends/database/__init__.py b/celery/backends/database/__init__.py
index 330f6682b5d..d2a50fe2a09 100644
--- a/celery/backends/database/__init__.py
+++ b/celery/backends/database/__init__.py
@@ -136,13 +136,26 @@ def ResultSession(self, session_manager=None):
             short_lived_sessions=self.short_lived_sessions,
             **self.engine_options)
 
-    def _store_result(self, task_id, result, state, traceback=None,
-                      request=None, **kwargs):
+    def _query_task(self, session, task_id):
+        """Query task by id, falling back to deferring children if missing from database."""
+        try:
+            tasks = list(session.query(self.task_cls).filter(self.task_cls.task_id == task_id))
+            return tasks and tasks[0]
+        except DatabaseError as exc:
+            if 'children' in str(exc).lower():
+                from sqlalchemy.orm import defer
+                tasks = list(session.query(self.task_cls).options(
+                    defer(self.task_cls.children)
+                ).filter(self.task_cls.task_id == task_id))
+                return tasks and tasks[0]
+            raise
+
+    def _store_result(self, task_id, result, state,
+                      traceback=None, request=None, **kwargs):
         """Store return value and state of an executed task."""
         session = self.ResultSession()
         with session_cleanup(session):
-            task = list(session.query(self.task_cls).filter(self.task_cls.task_id == task_id))
-            task = task and task[0]
+            task = self._query_task(session, task_id)
             if not task:
                 task = self.task_cls(task_id)
                 task.task_id = task_id
@@ -159,10 +172,10 @@ def _update_result(self, task, result, state, traceback=None,
                                      traceback=traceback, request=request,
                                      format_date=False, encode=True)
 
-        # Exclude the primary key id and task_id columns
-        # as we should not set it None
+        # Exclude the primary key id, task_id, and children columns
+        # as we should not set it None or handle children separately
         columns = [column.name for column in self.task_cls.__table__.columns
-                   if column.name not in {'id', 'task_id'}]
+                   if column.name not in {'id', 'task_id', 'children'}]
 
         # Iterate through the columns name of the table
         # to set the value from meta.
@@ -171,12 +184,18 @@ def _update_result(self, task, result, state, traceback=None,
             value = meta.get(column)
             setattr(task, column, value)
 
+        if hasattr(task, 'children') and 'children' in self.task_cls.__table__.columns:
+            children = meta.get('children')
+            if children:
+                setattr(task, 'children', ensure_bytes(self.encode(children)))
+            else:
+                setattr(task, 'children', None)
+
     def _get_task_meta_for(self, task_id):
         """Get task meta-data for a task by id."""
         session = self.ResultSession()
         with session_cleanup(session):
-            task = list(session.query(self.task_cls).filter(self.task_cls.task_id == task_id))
-            task = task and task[0]
+            task = self._query_task(session, task_id)
             if not task:
                 task = self.task_cls(task_id)
                 task.status = states.PENDING
@@ -187,6 +206,8 @@ def _get_task_meta_for(self, task_id):
                 data['args'] = self.decode(data['args'])
             if data.get('kwargs', None) is not None:
                 data['kwargs'] = self.decode(data['kwargs'])
+            if data.get('children', None) is not None:
+                data['children'] = self.decode(data['children'])
             return self.meta_from_decoded(data)
 
     def _decode_stored_result(self, payload):
diff --git a/celery/backends/database/models.py b/celery/backends/database/models.py
index 56fa9054883..4bcf90ef8dd 100644
--- a/celery/backends/database/models.py
+++ b/celery/backends/database/models.py
@@ -37,17 +37,23 @@ class Task(ResultModelBase):
     date_done = sa.Column(sa.DateTime, default=_get_utc_now,
                           onupdate=_get_utc_now, nullable=True, index=True)
     traceback = sa.Column(sa.Text, nullable=True)
+    children = sa.Column(sa.LargeBinary, nullable=True)
 
     def __init__(self, task_id):
         self.task_id = task_id
 
     def to_dict(self):
+        try:
+            children = self.children
+        except Exception:
+            children = None
         return {
             'task_id': self.task_id,
             'status': self.status,
             'result': self.result,
             'traceback': self.traceback,
             'date_done': self.date_done,
+            'children': children,
         }
 
     def __repr__(self):
diff --git a/celery/backends/database/session.py b/celery/backends/database/session.py
index 0aeceb86466..3fb1d77b77b 100644
--- a/celery/backends/database/session.py
+++ b/celery/backends/database/session.py
@@ -2,11 +2,12 @@
 import time
 
 from kombu.utils.compat import register_after_fork
-from sqlalchemy import create_engine
+from sqlalchemy import create_engine, inspect, text
 from sqlalchemy.exc import DatabaseError
 from sqlalchemy.orm import sessionmaker
 from sqlalchemy.pool import NullPool
 
+from celery.utils.log import get_logger
 from celery.utils.time import get_exponential_backoff_interval
 
 try:
@@ -21,6 +22,8 @@
 
 PREPARE_MODELS_MAX_RETRIES = 10
 
+logger = get_logger(__name__)
+
 
 def _after_fork_cleanup_session(session):
     session._after_fork()
@@ -98,8 +101,40 @@ def prepare_models(self, engine):
                         raise
                 else:
                     break
+            self._migrate_missing_columns(engine)
             self.prepared = True
 
+    def _migrate_missing_columns(self, engine):
+        """Add missing nullable columns to existing tables if needed."""
+        try:
+            inspector = inspect(engine)
+            preparer = engine.dialect.identifier_preparer
+            for table in ResultModelBase.metadata.tables.values():
+                actual_name = table.name
+                schema = table.schema
+                if not inspector.has_table(actual_name, schema=schema):
+                    continue
+                existing_cols = {
+                    col['name'] for col in inspector.get_columns(actual_name, schema=schema)
+                }
+                for col in table.columns:
+                    if col.name not in existing_cols and col.nullable:
+                        col_type = col.type.compile(engine.dialect)
+                        table_name = preparer.format_table(table)
+                        col_name = preparer.quote_identifier(col.name)
+                        alter_stmt = f"ALTER TABLE {table_name} ADD COLUMN {col_name} {col_type}"
+                        try:
+                            with engine.begin() as conn:
+                                conn.execute(text(alter_stmt))
+                        except Exception as exc:
+                            logger.warning(
+                                "Failed to add missing column %r to table %r. "
+                                "To enable storing task children, execute: %s. Error: %s",
+                                col.name, actual_name, alter_stmt, exc,
+                            )
+        except Exception as exc:
+            logger.warning("Failed to inspect or migrate database tables: %s", exc)
+
     def session_factory(self, dburi, **kwargs):
         engine, session = self.create_session(dburi, **kwargs)
         self.prepare_models(engine)
diff --git a/docs/userguide/configuration.rst b/docs/userguide/configuration.rst
index 107e86d4f76..5c18241ae71 100644
--- a/docs/userguide/configuration.rst
+++ b/docs/userguide/configuration.rst
@@ -1298,6 +1298,19 @@ you to customize the table names:
         'group': 'myapp_groupmeta',
     }
 
+.. note::
+
+    Starting in Celery 5.7, the database result backend supports storing task
+    children in the ``children`` column of ``celery_taskmeta``.
+    Celery automatically attempts to add this missing column to existing tables
+    at startup. If your database user does not have DDL / ``ALTER TABLE`` permissions,
+    you can execute the migration manually:
+
+    .. code-block:: sql
+
+        ALTER TABLE celery_taskmeta ADD COLUMN children BLOB;  -- SQLite / MySQL
+        ALTER TABLE celery_taskmeta ADD COLUMN children BYTEA; -- PostgreSQL
+
 .. setting:: database_engine_callback
 
 ``database_engine_callback``
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/t/unit/backends/test_database.py b/t/unit/backends/test_database.py
index 7bf1b3f89f6..3c45aa3cd83 100644
--- a/t/unit/backends/test_database.py
+++ b/t/unit/backends/test_database.py
@@ -9,6 +9,7 @@
 from celery import states, uuid
 from celery.app.task import Context
 from celery.exceptions import ImproperlyConfigured
+from celery.result import result_from_tuple
 
 pytest.importorskip('sqlalchemy')
 
@@ -593,6 +594,165 @@ def test_result_decode_does_not_unpickle_non_pickle_garbage(self):
         with pytest.raises(Exception):
             tb.get_task_meta(tid)
 
+    @pytest.mark.parametrize(
+        'result_serializer',
+        ['pickle', 'json'],
+        ids=['using pickle', 'using json']
+    )
+    def test_store_result_with_children(self, result_serializer):
+        self.app.conf.result_serializer = result_serializer
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        child1 = self.app.AsyncResult(uuid())
+        child2 = self.app.AsyncResult(uuid())
+
+        request = Context()
+        request.children.extend([child1, child2])
+        tb.store_result(tid, 42, states.SUCCESS, request=request)
+        meta = tb.get_task_meta(tid)
+
+        assert meta['result'] == 42
+        assert len(meta['children']) == 2
+        deserialized = [result_from_tuple(c, self.app) for c in meta['children']]
+        assert [c.id for c in deserialized] == [child1.id, child2.id]
+
+    def test_async_result_children(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        child_id = uuid()
+        child = self.app.AsyncResult(child_id)
+
+        request = Context()
+        request.children.append(child)
+        tb.store_result(tid, 42, states.SUCCESS, request=request)
+
+        result = self.app.AsyncResult(tid, backend=tb)
+        children = result.children
+        assert children is not None
+        assert len(children) == 1
+        assert children[0].id == child_id
+
+    def test_store_result_no_children(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        tb.store_result(tid, 42, states.SUCCESS)
+        meta = tb.get_task_meta(tid)
+        assert meta['children'] is None
+        result = self.app.AsyncResult(tid)
+        assert result.children is None
+
+    def test_migrate_missing_columns(self):
+        import sqlalchemy as sa
+        engine = sa.create_engine('sqlite:///:memory:')
+        metadata = sa.MetaData()
+        sa.Table(
+            'celery_taskmeta', metadata,
+            sa.Column('id', sa.Integer, primary_key=True),
+            sa.Column('task_id', sa.String(155), unique=True),
+            sa.Column('status', sa.String(50)),
+            sa.Column('result', sa.LargeBinary, nullable=True),
+            sa.Column('date_done', sa.DateTime, nullable=True),
+            sa.Column('traceback', sa.Text, nullable=True),
+        )
+        metadata.create_all(engine)
+
+        session_mgr = SessionManager()
+        session_mgr.prepare_models(engine)
+
+        from sqlalchemy import inspect
+        inspector = inspect(engine)
+        cols = {c['name'] for c in inspector.get_columns('celery_taskmeta')}
+        assert 'children' in cols
+
+    def test_store_result_task_without_children_attribute(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+
+        class TaskWithoutChildren:
+            pass
+
+        dummy = TaskWithoutChildren()
+        tb._update_result(dummy, 42, states.SUCCESS)
+        assert not hasattr(dummy, 'children')
+
+    def test_migrate_missing_columns_failure_logs_warning_and_degrades_gracefully(self):
+        import sqlalchemy as sa
+        engine = sa.create_engine('sqlite:///:memory:')
+        metadata = sa.MetaData()
+        sa.Table(
+            'celery_taskmeta', metadata,
+            sa.Column('id', sa.Integer, primary_key=True),
+            sa.Column('task_id', sa.String(155), unique=True),
+            sa.Column('status', sa.String(50)),
+            sa.Column('result', sa.LargeBinary, nullable=True),
+            sa.Column('date_done', sa.DateTime, nullable=True),
+            sa.Column('traceback', sa.Text, nullable=True),
+        ).create(engine)
+
+        session_mgr = SessionManager()
+        failing_conn = Mock()
+        failing_conn.execute.side_effect = Exception("permission denied: ALTER TABLE")
+
+        class FailingBegin:
+            def __enter__(self):
+                return failing_conn
+
+            def __exit__(self, *args):
+                pass
+
+        with patch.object(engine, 'begin', return_value=FailingBegin()):
+            with patch('celery.backends.database.session.logger.warning') as mock_warn:
+                session_mgr.prepare_models(engine)
+                assert mock_warn.called
+                logged_msg = mock_warn.call_args[0][0]
+                assert "Failed to add missing column" in logged_msg
+
+        # Test backend tolerant read path on this database:
+        tb = DatabaseBackend('sqlite:///:memory:', app=self.app)
+        with engine.begin() as conn:
+            conn.execute(sa.text(
+                "INSERT INTO celery_taskmeta (task_id, status, result) VALUES ('test-tid', 'SUCCESS', :res)"
+            ), {'res': tb.encode(42)})
+
+        tb.session_manager.session_factory = lambda *a, **kw: sa.orm.sessionmaker(bind=engine)()
+        meta = tb.get_task_meta('test-tid')
+        assert meta['result'] == 42
+        assert meta['children'] is None
+
+    def test_query_task_fallback_on_operational_error(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        session = Mock()
+
+        # Simulate first query failing with 'no such column: celery_taskmeta.children'
+        from sqlalchemy.exc import DatabaseError
+        err = DatabaseError("SELECT", {}, Exception("no such column: celery_taskmeta.children"))
+        query_mock = Mock()
+        query_mock.filter.side_effect = [err, [Mock(task_id=tid, to_dict=lambda: {'task_id': tid})]]
+        query_mock.options.return_value = query_mock
+        session.query.return_value = query_mock
+
+        res = tb._query_task(session, tid)
+        assert res.task_id == tid
+        assert query_mock.options.called
+
+    def test_migrate_missing_columns_ignores_exceptions(self):
+        session_mgr = SessionManager()
+        mock_engine = Mock()
+        with patch('celery.backends.database.session.inspect', side_effect=Exception("inspect error")):
+            with patch('celery.backends.database.session.logger.warning') as mock_warn:
+                # Must not raise and must log warning
+                session_mgr._migrate_missing_columns(mock_engine)
+                assert mock_warn.called
+
+    def test_migrate_missing_columns_when_table_not_exists(self):
+        session_mgr = SessionManager()
+        mock_engine = Mock()
+        mock_inspector = Mock()
+        mock_inspector.has_table.return_value = False
+        with patch('celery.backends.database.session.inspect', return_value=mock_inspector):
+            session_mgr._migrate_missing_columns(mock_engine)
+        mock_inspector.get_columns.assert_not_called()
+
     def test_mark_as_started(self):
         tb = DatabaseBackend(self.uri, app=self.app)
         tid = uuid()
```
</details>

---

## celery__celery-10668

**9/25** · [PR](https://github.com/celery/celery/pull/10668) · [issue #4300](https://github.com/celery/celery/issues/4300) · 9 FAIL_TO_PASS tests

### Issue

Revoked task still executes?
This issue is a continuation of issues https://github.com/celery/celery/issues/4295 (see for Celery details) and https://github.com/celery/celery/issues/4299.

I am trying to [cancel a scheduled task](http://docs.celeryproject.org/en/latest/faq.html#can-i-cancel-the-execution-of-a-task) using [revoke()](http://docs.celeryproject.org/en/latest/reference/celery.result.html#celery.result.AsyncResult.revoke), but the task still executes. Here’s the Celery log:


```
[2017-09-28 17:52:18,811: INFO/MainProcess] Received task: app.tasks._do_singlething[0e4f0131-b4e6-4209-865e-e91b73e92f28]  ETA:[2017-09-28 07:53:18.766382+00:00] 
[2017-09-28 17:52:32,091: INFO/MainProcess] Tasks flagged as revoked: 0e4f0131b4e64209865ee91b73e92f28
[2017-09-28 17:53:18,831: WARNING/ForkPoolWorker-1] Hello from executing task 0e4f0131-b4e6-4209-865e-e91b73e92f28
[2017-09-28 17:53:18,841: INFO/ForkPoolWorker-1] Task app.tasks._do_singlething[0e4f0131-b4e6-4209-865e-e91b73e92f28] succeeded in 0.06189309403998777s: None
```

Code snippet that revokes is the same as in issue https://github.com/celery/celery/issues/4299.

### Files changed by the gold patch

- `celery/utils/collections.py` (+41 / -14)
- `celery/worker/consumer/mingle.py` (+7 / -3)
- `celery/worker/control.py` (+4 / -2)
- `celery/worker/state.py` (+33 / -9)
- `docs/userguide/workers.rst` (+6 / -2)

### Tests that must pass (names, deduplicated)

- `test_add_at_time_zero`
- `test_add_orders_items_within_the_clock_resolution`
- `test_eq`
- `test_hello_stamps_received_revoked_items_locally`
- `test_ids_only`
- `test_merge_stamps_saved_items_locally`
- `test_nothing`
- `test_start`
- `test_start_stamps_received_revoked_items_locally`

<details><summary>Gold patch</summary>

```diff
diff --git a/celery/utils/collections.py b/celery/utils/collections.py
index 090752e461a..04474b89431 100644
--- a/celery/utils/collections.py
+++ b/celery/utils/collections.py
@@ -464,6 +464,15 @@ class LimitedSet:
     ``maxlen`` is enforced at all times, so if the limit is reached
     we'll also remove non-expired items.
 
+    Items are stamped with :func:`time.monotonic`, which counts from the
+    boot of the host, so the stamps of a set built on another host (or
+    before a reboot) are not comparable with the local ones: a stamp
+    ahead of the local clock never expires here, and once such stamps
+    fill the set up to ``maxlen``, every item added later is the oldest
+    one and is purged the moment it is added.  Merge such a set by
+    passing its items (an iterable, not the set or its dict), which
+    stamps them with the local clock.
+
     You can also configure ``minlen``: this is the minimal residual size
     of the set.
 
@@ -516,8 +525,11 @@ def __init__(self, maxlen=0, expires=0, data=None, minlen=0):
         self.maxlen = 0 if maxlen is None else maxlen
         self.minlen = 0 if minlen is None else minlen
         self.expires = 0 if expires is None else expires
-        self._data = {}
+        self._data = {}  # item -> (inserted, sequence number, item)
         self._heap = []
+        # Orders the items inserted within the clock resolution and keeps
+        # the heap from ever comparing the items themselves.
+        self._seq = count()
 
         if data:
             # import items from data
@@ -548,11 +560,18 @@ def clear(self):
 
     def add(self, item, now=None):
         # type: (Any, float) -> None
-        """Add a new item, or reset the expiry time of an existing item."""
-        now = now or time.monotonic()
+        """Add a new item, or reset the expiry time of an existing item.
+
+        Arguments:
+            now (float): Insertion time of the item, as read from
+                :func:`time.monotonic` -- by default right now.
+        """
+        # A float, whatever is given: update(dict), which pickling goes
+        # through, takes nothing else.
+        now = time.monotonic() if now is None else float(now)
         if item in self._data:
             self.discard(item)
-        entry = (now, item)
+        entry = (now, next(self._seq), item)
         self._data[item] = entry
         heappush(self._heap, entry)
         if self.maxlen and len(self._data) >= self.maxlen:
@@ -568,10 +587,10 @@ def update(self, other):
             self._refresh_heap()
             self.purge()
         elif isinstance(other, dict):
-            # revokes are sent as a dict
+            # {item: insertion time}, or {item: (insertion time, ...)}
+            # in case someone uses ._data directly for sending update
             for key, inserted in other.items():
                 if isinstance(inserted, (tuple, list)):
-                    # in case someone uses ._data directly for sending update
                     inserted = inserted[0]
                 if not isinstance(inserted, float):
                     raise ValueError(
@@ -579,8 +598,12 @@ def update(self, other):
                         f'{type(inserted)!r} with value: {inserted}')
                 self.add(key, inserted)
         else:
-            # XXX AVOID THIS, it could keep old data if more parties
-            # exchange them all over and over again
+            # The items are stamped with the local clock: the way to merge
+            # a set built on another host, whose stamps are not comparable
+            # with ours (see the class docstring).  Note that an item lives
+            # ``expires`` from now on rather than from its insertion there,
+            # so it could be kept alive if more parties exchange their sets
+            # all over and over again.
             for obj in other:
                 self.add(obj)
 
@@ -599,7 +622,7 @@ def purge(self, now=None):
             now (float): Time of purging -- by default right now.
                 This can be useful for unit testing.
         """
-        now = now or time.monotonic()
+        now = time.monotonic() if now is None else now
         now = now() if isinstance(now, Callable) else now
         if self.maxlen:
             while len(self._data) > self.maxlen:
@@ -607,7 +630,7 @@ def purge(self, now=None):
         # time based expiring:
         if self.expires:
             while len(self._data) > self.minlen >= 0:
-                inserted_time, _ = self._heap[0]
+                inserted_time = self._heap[0][0]
                 if inserted_time + self.expires > now:
                     break  # oldest item hasn't expired yet
                 self.pop()
@@ -615,7 +638,7 @@ def purge(self, now=None):
     def pop(self, default: Any = None) -> Any:
         """Remove and return the oldest item, or :const:`None` when empty."""
         while self._heap:
-            _, item = heappop(self._heap)
+            _, _, item = heappop(self._heap)
             try:
                 self._data.pop(item)
             except KeyError:
@@ -638,11 +661,13 @@ def as_dict(self):
             >>> r == s
             True
         """
-        return {key: inserted for inserted, key in self._data.values()}
+        return {key: inserted for inserted, _, key in self._data.values()}
 
     def __eq__(self, other):
         # type: (Any) -> bool
-        return self._data == other._data
+        if not isinstance(other, LimitedSet):
+            return NotImplemented
+        return self.as_dict() == other.as_dict()
 
     def __repr__(self):
         # type: () -> str
@@ -652,7 +677,7 @@ def __repr__(self):
 
     def __iter__(self):
         # type: () -> Iterable
-        return (i for _, i in sorted(self._data.values()))
+        return (i for _, _, i in sorted(self._data.values()))
 
     def __len__(self):
         # type: () -> int
@@ -664,6 +689,8 @@ def __contains__(self, key):
 
     def __reduce__(self):
         # type: () -> Any
+        # The sequence numbers are not kept: the items are added again in
+        # their order, from the insertion times.
         return self.__class__, (
             self.maxlen, self.expires, self.as_dict(), self.minlen)
 
diff --git a/celery/worker/consumer/mingle.py b/celery/worker/consumer/mingle.py
index d3f626e702b..ec2b0a46c8d 100644
--- a/celery/worker/consumer/mingle.py
+++ b/celery/worker/consumer/mingle.py
@@ -50,8 +50,12 @@ def sync(self, c):
 
     def send_hello(self, c):
         inspect = c.app.control.inspect(timeout=1.0, connection=c.connection)
-        our_revoked = c.controller.state.revoked
-        replies = inspect.hello(c.hostname, our_revoked._data) or {}
+        # The ids only: the other workers stamp them with their own clocks
+        # (see merge_revoked()), so the stamps would be dead weight.  Oldest
+        # first, so that a receiver whose set is full evicts our oldest ids
+        # first.
+        our_revoked = list(c.controller.state.revoked)
+        replies = inspect.hello(c.hostname, our_revoked) or {}
         replies.pop(c.hostname, None)  # delete my own response
         return replies
 
@@ -73,4 +77,4 @@ def on_clock_event(self, c, clock):
 
     def on_revoked_received(self, c, revoked):
         if revoked:
-            c.controller.state.revoked.update(revoked)
+            c.controller.state.merge_revoked(revoked)
diff --git a/celery/worker/control.py b/celery/worker/control.py
index 41244f3eaea..6d3e17bfc8b 100644
--- a/celery/worker/control.py
+++ b/celery/worker/control.py
@@ -396,11 +396,13 @@ def hello(state, from_node, revoked=None, **kwargs):
     if from_node != state.hostname:
         logger.info('sync with %s', from_node)
         if revoked:
-            worker_state.revoked.update(revoked)
+            worker_state.merge_revoked(revoked)
         # Do not send expired items to the other worker.
         worker_state.revoked.purge()
         return {
-            'revoked': worker_state.revoked._data,
+            # The ids only, see merge_revoked(): oldest first, so that
+            # a receiver whose set is full evicts our oldest ids first.
+            'revoked': list(worker_state.revoked),
             'clock': state.app.clock.forward(),
         }
 
diff --git a/celery/worker/state.py b/celery/worker/state.py
index 2cce5f988a4..6374f10cbf8 100644
--- a/celery/worker/state.py
+++ b/celery/worker/state.py
@@ -22,7 +22,7 @@
     'SOFTWARE_INFO', 'reserved_requests', 'active_requests',
     'scheduled_requests', 'total_count', 'revoked', 'task_reserved',
     'task_scheduled', 'maybe_shutdown', 'task_accepted', 'task_ready',
-    'Persistent',
+    'merge_revoked', 'Persistent',
 )
 
 
@@ -112,6 +112,32 @@ def _float_env(name: str, default: float) -> float:
 #: Mapping of stamped headers flagged for revoking.
 revoked_stamps = {}
 
+
+def merge_revoked(task_ids):
+    """Add task ids revoked elsewhere: on another worker, or before a restart.
+
+    Only the ids are taken, stamped with the local clock; the stamps they
+    may come with are dropped.  :data:`revoked` stamps its items with
+    :func:`time.monotonic`, which counts from the boot of the host, so a
+    stamp taken on another host (received on mingle) or before a reboot
+    (read from the state db) is not comparable with the local ones: a
+    stamp ahead of the local clock never expires here, and once such
+    stamps fill the set up to its limit, every id revoked here is purged
+    as the oldest one the moment it is added.  The ids received live
+    ``REVOKE_EXPIRES`` seconds from now on rather than from the time they
+    were revoked.
+
+    Arguments:
+        task_ids (Iterable): the ids, or a mapping/:class:`LimitedSet`
+            of them, in which case its stamps are ignored.  The order
+            matters when the local set is full: the ids are added in it,
+            and the first ones are then the first to be purged.
+    """
+    if not task_ids:
+        return
+    revoked.update(list(task_ids))
+
+
 should_stop = None
 should_terminate = None
 
@@ -335,18 +361,16 @@ def _merge_revoked(self, d):
 
     def _merge_revoked_v3(self, zrevoked):
         if zrevoked:
-            self._revoked_tasks.update(pickle.loads(self.decompress(zrevoked)))
+            self._merge_revoked_v1(pickle.loads(self.decompress(zrevoked)))
 
     def _merge_revoked_v2(self, saved):
-        if not isinstance(saved, LimitedSet):
-            # (pre 3.0.18) used to be stored as a dict
-            return self._merge_revoked_v1(saved)
-        self._revoked_tasks.update(saved)
+        # a LimitedSet, or a dict before 3.0.18
+        self._merge_revoked_v1(saved)
 
     def _merge_revoked_v1(self, saved):
-        add = self._revoked_tasks.add
-        for item in saved:
-            add(item)
+        # The saved stamps are dropped whatever the format: they may come
+        # from before a reboot, see merge_revoked().
+        self.state.merge_revoked(saved)
 
     def _dumps(self, obj):
         return pickle.dumps(obj, protocol=self.protocol)
diff --git a/docs/userguide/workers.rst b/docs/userguide/workers.rst
index 63c96b051fa..ffd6262d9bf 100644
--- a/docs/userguide/workers.rst
+++ b/docs/userguide/workers.rst
@@ -636,12 +636,16 @@ Persistent revokes
 
 Revoking tasks works by sending a broadcast message to all the workers,
 the workers then keep a list of revoked tasks in memory. When a worker starts
-up it will synchronize revoked tasks with other workers in the cluster.
+up it will synchronize revoked tasks with other workers in the cluster: the
+ids received this way count as revoked from that moment on, and expire
+``CELERY_WORKER_REVOKE_EXPIRES`` seconds later.
 
 The list of revoked tasks is in-memory so if all workers restart the list
 of revoked ids will also vanish. If you want to preserve this list between
 restarts you need to specify a file for these to be stored in by using the `--statedb`
-argument to :program:`celery worker`:
+argument to :program:`celery worker` (the ids read from the file count as
+revoked from the start of the worker, and expire
+``CELERY_WORKER_REVOKE_EXPIRES`` seconds later):
 
 .. code-block:: console
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/t/integration/test_inspect.py b/t/integration/test_inspect.py
index 8bd7012cc43..7993be27224 100644
--- a/t/integration/test_inspect.py
+++ b/t/integration/test_inspect.py
@@ -1,12 +1,14 @@
 import os
 import re
 from datetime import datetime, timedelta, timezone
-from time import sleep
+from time import monotonic, sleep
 from unittest.mock import ANY
 
 import pytest
 
+from celery import uuid
 from celery.utils.nodenames import anon_nodename
+from celery.worker import state as worker_state
 
 from .tasks import add, sleeping
 
@@ -253,6 +255,31 @@ def test_revoked(self, inspect):
         assert len(ret) == 1
         assert result.task_id in ret[NODENAME]
 
+    @flaky
+    def test_hello_stamps_received_revoked_ids_locally(self, inspect):
+        """The revoked ids of another worker are taken as ids, stamped here."""
+        # Stamps ahead of the local clock, as from a host with a longer
+        # uptime: taken as they are, they would never expire (#4300).
+        ahead = monotonic() + 10 ** 6
+        received = [uuid() for _ in range(2)]
+        try:
+            ret = inspect.hello(
+                'other@host',
+                revoked={task_id: [ahead, seq, task_id] for seq, task_id in enumerate(received)},
+            )
+            assert len(ret) == 1
+            # The session worker runs in this process: its set is right here.
+            stamps = worker_state.revoked.as_dict()
+            for task_id in received:
+                assert stamps[task_id] <= monotonic()
+            # The reply carries the ids alone.
+            reply = ret[NODENAME]['revoked']
+            assert isinstance(reply, list)
+            assert set(received) <= set(reply)
+        finally:
+            for task_id in received:
+                worker_state.revoked.discard(task_id)
+
     @flaky
     def test_conf(self, inspect):
         """Tests getting configuration"""
diff --git a/t/smoke/tests/test_revoked_sync.py b/t/smoke/tests/test_revoked_sync.py
new file mode 100644
index 00000000000..8e3f6e58563
--- /dev/null
+++ b/t/smoke/tests/test_revoked_sync.py
@@ -0,0 +1,116 @@
+"""Revoked ids received from another worker, on mingle or through ``hello``.
+
+They are stamped with the receiving worker's own clock, whatever stamps
+they come with (#4300): a set filled with stamps ahead of the local clock
+would otherwise purge every id revoked from then on the moment it is
+added, and the task would run.
+"""
+from __future__ import annotations
+
+from time import monotonic
+
+import pytest
+from pytest_celery import (CeleryBrokerCluster, CeleryTestSetup, CeleryTestWorker, CeleryWorkerCluster,
+                           RedisTestBroker)
+from tenacity import retry, stop_after_attempt, wait_fixed
+
+from celery import uuid
+from t.smoke.tasks import noop
+
+REVOKES_MAX = 3
+
+
+def revoked_ids(setup: CeleryTestSetup, worker: CeleryTestWorker) -> list[str]:
+    reply = setup.app.control.inspect(
+        destination=[worker.hostname()], timeout=5,
+    ).revoked() or {}
+    return reply.get(worker.hostname(), [])
+
+
+@retry(stop=stop_after_attempt(60), wait=wait_fixed(1), reraise=True)
+def assert_revoked(setup: CeleryTestSetup, worker: CeleryTestWorker, task_id: str) -> None:
+    assert task_id in revoked_ids(setup, worker), f"{task_id} is not revoked on {worker.hostname()}"
+
+
+class test_hello:
+    @pytest.fixture
+    def default_worker_env(self, default_worker_env: dict) -> dict:
+        # A set this small is full after one hello.
+        default_worker_env.update({"CELERY_WORKER_REVOKES_MAX": str(REVOKES_MAX)})
+        return default_worker_env
+
+    def test_received_ids_are_stamped_locally(self, celery_setup: CeleryTestSetup):
+        app = celery_setup.app
+        worker = celery_setup.worker
+
+        # Play a worker on a host with a longer uptime: its stamps are ahead
+        # of the clock of the worker under test.
+        ahead = monotonic() + 10 ** 6
+        received = [uuid() for _ in range(REVOKES_MAX)]
+        reply = app.control.inspect(
+            destination=[worker.hostname()], timeout=5,
+        ).hello(
+            "neighbour@elsewhere",
+            revoked={task_id: [ahead, seq, task_id] for seq, task_id in enumerate(received)},
+        )
+
+        # The set is full: an id revoked now must stay, the received ids
+        # being the oldest by the local clock -- or the newest, as sent.
+        revoked = uuid()
+        app.control.revoke(revoked, destination=[worker.hostname()])
+        assert_revoked(celery_setup, worker, revoked)
+
+        # And a task with an ETA revoked while the worker holds it is
+        # discarded rather than run.
+        result = noop.s().apply_async(queue=worker.worker_queue, countdown=10)
+        worker.assert_log_exists(f"noop[{result.id}] received")
+        result.revoke()
+        worker.assert_log_exists(f"Discarding revoked task: t.smoke.tasks.noop[{result.id}]")
+        worker.assert_log_does_not_exist(f"noop[{result.id}] succeeded", timeout=5)
+
+        # The reply to the hello carried the ids alone.
+        ours = reply[worker.hostname()]["revoked"]
+        assert isinstance(ours, list)
+        assert set(received) <= set(ours)
+
+
+class test_mingle:
+    @pytest.fixture
+    def celery_broker_cluster(self, celery_redis_broker: RedisTestBroker) -> CeleryBrokerCluster:
+        # The last release cannot mingle on RabbitMQ 4.3, which refuses
+        # its transient non-exclusive pidbox reply queue.
+        cluster = CeleryBrokerCluster(celery_redis_broker)
+        yield cluster
+        cluster.teardown()
+
+    @pytest.fixture
+    def celery_worker_cluster(
+        self,
+        celery_worker: CeleryTestWorker,
+        celery_latest_worker: CeleryTestWorker,
+    ) -> CeleryWorkerCluster:
+        # The last release and the current source in one cluster: each
+        # side receives the other's format on mingle.
+        cluster = CeleryWorkerCluster(celery_worker, celery_latest_worker)
+        yield cluster
+        cluster.teardown()
+
+    def test_sync_with_another_version(self, celery_setup: CeleryTestSetup):
+        app = celery_setup.app
+        dev, latest = celery_setup.worker_cluster
+
+        # A worker restarting takes the revoked ids of its neighbour.
+        revoked_on_dev = uuid()
+        app.control.revoke(revoked_on_dev, destination=[dev.hostname()])
+        assert_revoked(celery_setup, dev, revoked_on_dev)
+        latest.restart()
+        assert_revoked(celery_setup, latest, revoked_on_dev)
+
+        revoked_on_latest = uuid()
+        app.control.revoke(revoked_on_latest, destination=[latest.hostname()])
+        assert_revoked(celery_setup, latest, revoked_on_latest)
+        dev.restart()
+        assert_revoked(celery_setup, dev, revoked_on_latest)
+        # ...and gets back the id it had revoked before its restart, which
+        # the other release took on its own.
+        assert_revoked(celery_setup, dev, revoked_on_dev)
diff --git a/t/unit/utils/test_collections.py b/t/unit/utils/test_collections.py
index b4a9acbe15e..7934a8bc396 100644
--- a/t/unit/utils/test_collections.py
+++ b/t/unit/utils/test_collections.py
@@ -341,6 +341,42 @@ def test_purge(self):
         assert len(s._heap) <= s.maxlen * (
             100. + s.max_heap_percent_overload) / 100
 
+    def test_add_orders_items_within_the_clock_resolution(self):
+        s = LimitedSet(maxlen=10)
+        s.add('b', now=1.0)
+        s.add(1, now=1.0)  # no comparison between the items themselves
+        s.add('a', now=1.0)
+        assert list(s) == ['b', 1, 'a']
+        assert s.pop() == 'b'
+
+    def test_add_at_time_zero(self):
+        s = LimitedSet(maxlen=10, expires=1)
+        s.add('foo', now=0)
+        assert s.as_dict()['foo'] == 0
+        assert pickle.loads(pickle.dumps(s)) == s
+        s.purge(now=2)
+        assert 'foo' not in s
+
+    def test_update_from_another_clock(self):
+        # The stamps of a set built on another host are not comparable
+        # with ours; merging its items stamps them with the local clock,
+        # merging the set or its dict keeps the stamps.
+        other = LimitedSet(maxlen=10)
+        other.add('foo', now=monotonic() + 10 ** 6)
+        s = LimitedSet(maxlen=10)
+        s.update(list(other))
+        assert s.as_dict()['foo'] <= monotonic()
+        s = LimitedSet(maxlen=10)
+        s.update(other)
+        assert s.as_dict()['foo'] == other.as_dict()['foo']
+
+    def test_eq(self):
+        s = LimitedSet(maxlen=2)
+        s.add('foo')
+        assert s == pickle.loads(pickle.dumps(s))
+        assert s != LimitedSet(maxlen=2)
+        assert s != {'foo'}
+
     def test_pickleable(self):
         s = LimitedSet(maxlen=2)
         s.add('foo')
diff --git a/t/unit/worker/test_consumer.py b/t/unit/worker/test_consumer.py
index d132b0c0271..b9ebfee743b 100644
--- a/t/unit/worker/test_consumer.py
+++ b/t/unit/worker/test_consumer.py
@@ -2,6 +2,7 @@
 import logging
 import socket
 from collections import deque
+from time import monotonic
 from types import SimpleNamespace
 from unittest.mock import MagicMock, Mock, call, patch
 
@@ -17,6 +18,7 @@
 from celery.utils.collections import LimitedSet
 from celery.utils.quorum_queues import detect_quorum_queues
 from celery.utils.time import utcoffset
+from celery.worker import state as worker_state
 from celery.worker.consumer.agent import Agent
 from celery.worker.consumer.consumer import (CANCEL_TASKS_BY_DEFAULT, CLOSE, COLLECT_SOCKET_TIMEOUT, TERMINATE,
                                              Consumer)
@@ -1647,6 +1649,7 @@ def test_start_no_replies(self):
         c = Mock()
         c.app.connection_for_read = _amqp_connection()
         mingle = Mingle(c)
+        c.controller.state.revoked = LimitedSet()
         I = c.app.control.inspect.return_value = Mock()
         I.hello.return_value = {}
         mingle.start(c)
@@ -1678,10 +1681,12 @@ def test_start(self):
             },
         }
 
-        our_revoked = c.controller.state.revoked = LimitedSet()
-
-        mingle.start(c)
-        I.hello.assert_called_with(c.hostname, our_revoked._data)
+        our_revoked = LimitedSet()
+        our_revoked.add('ours')
+        with patch.object(worker_state, 'revoked', our_revoked):
+            c.controller.state = worker_state
+            mingle.start(c)
+        I.hello.assert_called_with(c.hostname, ['ours'])
         c.app.clock.adjust.assert_has_calls([
             call(312), call(29),
         ], any_order=True)
@@ -1689,6 +1694,33 @@ def test_start(self):
         assert 'Aig-2' in our_revoked
         assert 'Big-1' in our_revoked
 
+    def test_start_stamps_received_revoked_items_locally(self):
+        # The stamps of a neighbour count from the boot of its host; taken
+        # as they are, the ones ahead of the local clock never expire and,
+        # once they fill the set, evict every id revoked here as the
+        # oldest one the moment it is added (#4300).
+        c = Mock()
+        c.app.connection_for_read = _amqp_connection()
+        mingle = Mingle(c)
+
+        Aig = LimitedSet()
+        Aig.add('Aig-1', now=monotonic() + 10 ** 6)
+        I = c.app.control.inspect.return_value = Mock()
+        I.hello.return_value = {
+            'A@example.com': {'clock': 312, 'revoked': Aig._data},
+        }
+
+        our_revoked = LimitedSet(maxlen=1, expires=3600)
+        with patch.object(worker_state, 'revoked', our_revoked):
+            c.controller.state = worker_state
+            mingle.start(c)
+        assert 'Aig-1' in our_revoked
+        assert our_revoked.as_dict()['Aig-1'] <= monotonic()
+
+        our_revoked.add('ours')
+        assert 'ours' in our_revoked
+        assert 'Aig-1' not in our_revoked
+
 
 def _amqp_connection():
     connection = ContextMock(name='Connection')
diff --git a/t/unit/worker/test_control.py b/t/unit/worker/test_control.py
index 9a0afd9a3f7..7df2e94db1a 100644
--- a/t/unit/worker/test_control.py
+++ b/t/unit/worker/test_control.py
@@ -283,6 +283,38 @@ def test_hello_does_not_send_expired_revoked_items(self):
         })
         assert 'expired_in_past' not in x['revoked']
 
+    def test_hello_stamps_received_revoked_items_locally(self):
+        # The set of the other worker comes with its own monotonic stamps,
+        # counting from the boot of its host.  Merged as they are, stamps
+        # ahead of the local clock would never expire, and once they fill
+        # the set every id revoked here would be purged as the oldest one
+        # the moment it is added (#4300).
+        consumer = Consumer(self.app)
+        panel = self.create_panel(consumer=consumer)
+        panel.state.hostname = 'elaine@vandelay.com'
+        ahead = time.monotonic() + 10 ** 6
+        try:
+            panel.handle('hello', {
+                'from_node': 'george@vandelay.com',
+                'revoked': {
+                    'ahead1': [ahead, 0, 'ahead1'],
+                    'ahead2': [ahead, 1, 'ahead2'],
+                },
+            })
+            assert 'ahead1' in worker_state.revoked
+            assert 'ahead2' in worker_state.revoked
+            stamps = worker_state.revoked.as_dict()
+            assert stamps['ahead1'] <= time.monotonic()
+            assert stamps['ahead2'] <= time.monotonic()
+            worker_state.revoked.purge(
+                now=time.monotonic() + REVOKE_EXPIRES + 1
+            )
+            assert 'ahead1' not in worker_state.revoked
+            assert 'ahead2' not in worker_state.revoked
+        finally:
+            worker_state.revoked.discard('ahead1')
+            worker_state.revoked.discard('ahead2')
+
     def test_conf(self):
         consumer = Consumer(self.app)
         panel = self.create_panel(consumer=consumer)
diff --git a/t/unit/worker/test_state.py b/t/unit/worker/test_state.py
index e89af815001..193cbd50a5a 100644
--- a/t/unit/worker/test_state.py
+++ b/t/unit/worker/test_state.py
@@ -2,7 +2,7 @@
 import pickle
 import sys
 from importlib import import_module
-from time import time
+from time import monotonic, time
 from unittest.mock import Mock, patch
 
 import pytest
@@ -89,6 +89,28 @@ def test_should_terminate(self, should_stop):
 
 
 @pytest.mark.usefixtures('reset_state')
+class test_merge_revoked:
+
+    def test_nothing(self):
+        size = len(state.revoked)
+        state.merge_revoked(None)
+        state.merge_revoked([])
+        state.merge_revoked({})
+        assert len(state.revoked) == size
+
+    def test_ids_only(self):
+        ahead = monotonic() + 10 ** 6
+        try:
+            state.merge_revoked({'from-dict': [ahead, 0, 'from-dict']})
+            state.merge_revoked(['from-list'])
+            stamps = state.revoked.as_dict()
+            assert stamps['from-dict'] <= monotonic()
+            assert stamps['from-list'] <= monotonic()
+        finally:
+            state.revoked.discard('from-dict')
+            state.revoked.discard('from-list')
+
+
 class test_Persistent:
 
     @pytest.fixture
@@ -119,6 +141,17 @@ def test_merge(self, p, data=['foo', 'bar', 'baz']):
         for item in data:
             assert item in state.revoked
 
+    def test_merge_stamps_saved_items_locally(self, p):
+        # The stamps in the state db count from the boot of the host the
+        # worker ran on; after a reboot they are ahead of the clock.
+        saved = LimitedSet()
+        saved.add('rebooted', now=monotonic() + 10 ** 6)
+        p.db['zrevoked'] = p.compress(p._dumps(saved))
+        p.merge()
+        assert 'rebooted' in state.revoked
+        assert state.revoked.as_dict()['rebooted'] <= monotonic()
+        state.revoked.discard('rebooted')
+
     def test_merge_dict(self, p):
         p.clock = Mock()
         p.clock.adjust.return_value = 626
```
</details>

---

## celery__celery-10714

**10/25** · [PR](https://github.com/celery/celery/pull/10714) · [issue #10713](https://github.com/celery/celery/issues/10713) · 6 FAIL_TO_PASS tests

### Issue

forget() is not idempotent on azureblockblob and cosmosdb result backends
### Summary

`result.forget()` on a missing result should be a no-op on every KV result backend. PR #10697 made `forget()` idempotent for the Elasticsearch and CouchDB backends (matching the existing `DocumentNotFoundException` handling in `couchbase.py` and the no-op behavior of Redis, cache, DynamoDB, ArangoDB, and S3's non-raising `delete_object`). Two backends still let a missing-key error through:

- `celery/backends/azureblockblob.py`: `blob_client.delete_blob()` raises `azure.core.exceptions.ResourceNotFoundError` for a missing blob.
- `celery/backends/cosmosdbsql.py`: `DeleteDocument()` raises `azure.cosmos.exceptions.HTTPFailure` (or the legacy `HTTPFailure`) with status 404 for a missing document.

(`gcs.py` checks `blob.exists()` first, so it already behaves as a no-op.)

### Suggested fix

Catch the missing-key exception in each backend's `delete()` (mirroring #10697), so `forget()` behaves consistently across KV backends.

Found during review of #10697 — filing separately per the reviewer's suggestion.

### Files changed by the gold patch

- `celery/backends/azureblockblob.py` (+6 / -1)
- `celery/backends/cosmosdbsql.py` (+10 / -3)

### Tests that must pass (names, deduplicated)

- `test_forget_missing_task_is_noop`
- `test_forget_twice_is_noop`

<details><summary>Gold patch</summary>

```diff
diff --git a/celery/backends/azureblockblob.py b/celery/backends/azureblockblob.py
index 071c4d2c78a..3ab0a9fc8e6 100644
--- a/celery/backends/azureblockblob.py
+++ b/celery/backends/azureblockblob.py
@@ -174,7 +174,12 @@ def delete(self, key):
             blob=f'{self.base_path}{key}',
         )
 
-        blob_client.delete_blob()
+        try:
+            blob_client.delete_blob()
+        except ResourceNotFoundError:
+            # deleting an already-expired, already-forgotten or never-stored
+            # result must keep forget() idempotent, like the other KV backends
+            pass
 
     def as_uri(self, include_password=False):
         if include_password:
diff --git a/celery/backends/cosmosdbsql.py b/celery/backends/cosmosdbsql.py
index e32b13f2e78..01d625c1349 100644
--- a/celery/backends/cosmosdbsql.py
+++ b/celery/backends/cosmosdbsql.py
@@ -213,6 +213,13 @@ def delete(self, key):
         LOGGER.debug("Deleting CosmosDB document %s/%s/%s",
                      self._database_name, self._collection_name, key)
 
-        self._client.DeleteDocument(
-            self._get_document_link(key),
-            self._get_partition_key(key))
+        try:
+            self._client.DeleteDocument(
+                self._get_document_link(key),
+                self._get_partition_key(key))
+        except HTTPFailure as ex:
+            if ex.status_code != ERROR_NOT_FOUND:
+                raise
+            # deleting an already-expired, already-forgotten or never-stored
+            # result must keep forget() idempotent, like the other KV backends
+            return
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/t/unit/backends/test_azureblockblob.py b/t/unit/backends/test_azureblockblob.py
index af1523a6c89..a5b1ecbae80 100644
--- a/t/unit/backends/test_azureblockblob.py
+++ b/t/unit/backends/test_azureblockblob.py
@@ -187,6 +187,25 @@ def test_delete(self, mock_client, base_path):
         mock_client.get_blob_client.return_value \
             .delete_blob.assert_called_once()
 
+    @patch(MODULE_TO_MOCK + ".AzureBlockBlobBackend._blob_service_client")
+    def test_forget_missing_task_is_noop(self, mock_client, base_path):
+        self.backend.base_path = base_path
+        mock_client.get_blob_client.return_value \
+            .delete_blob.side_effect = azureblockblob.ResourceNotFoundError
+
+        # forget() on a result that was expired, already forgotten or never
+        # stored must not raise ResourceNotFoundError
+        self.backend.delete(b"mykey")
+
+    @patch(MODULE_TO_MOCK + ".AzureBlockBlobBackend._blob_service_client")
+    def test_forget_twice_is_noop(self, mock_client, base_path):
+        self.backend.base_path = base_path
+        mock_client.get_blob_client.return_value \
+            .delete_blob.side_effect = [None, azureblockblob.ResourceNotFoundError]
+
+        self.backend.delete(b"mykey")
+        self.backend.delete(b"mykey")
+
     def test_base_path_conf(self, base_path):
         self.app.conf.azureblockblob_base_path = base_path
         backend = AzureBlockBlobBackend(
diff --git a/t/unit/backends/test_cosmosdbsql.py b/t/unit/backends/test_cosmosdbsql.py
index bfd0d0d1e1f..34766cc9056 100644
--- a/t/unit/backends/test_cosmosdbsql.py
+++ b/t/unit/backends/test_cosmosdbsql.py
@@ -137,3 +137,30 @@ def test_delete(self, mock_client):
         mock_client.DeleteDocument.assert_called_once_with(
             "dbs/celerydb/colls/celerycol/docs/mykey",
             {"partitionKey": "mykey"})
+
+    @patch(MODULE_TO_MOCK + ".CosmosDBSQLBackend._client")
+    def test_forget_missing_task_is_noop(self, mock_client):
+        mock_client.DeleteDocument.side_effect = \
+            cosmosdbsql.HTTPFailure(cosmosdbsql.ERROR_NOT_FOUND)
+
+        # forget() on a result that was expired, already forgotten or never
+        # stored must not raise HTTPFailure
+        self.backend.delete(b"mykey")
+
+    @patch(MODULE_TO_MOCK + ".CosmosDBSQLBackend._client")
+    def test_forget_twice_is_noop(self, mock_client):
+        mock_client.DeleteDocument.side_effect = [
+            None,
+            cosmosdbsql.HTTPFailure(cosmosdbsql.ERROR_NOT_FOUND),
+        ]
+
+        self.backend.delete(b"mykey")
+        self.backend.delete(b"mykey")
+
+    @patch(MODULE_TO_MOCK + ".CosmosDBSQLBackend._client")
+    def test_delete_reraises_other_http_failures(self, mock_client):
+        mock_client.DeleteDocument.side_effect = \
+            cosmosdbsql.HTTPFailure(500)
+
+        with pytest.raises(cosmosdbsql.HTTPFailure):
+            self.backend.delete(b"mykey")
```
</details>

---

## modelcontextprotocol__python-sdk-3485

**11/25** · [PR](https://github.com/modelcontextprotocol/python-sdk/pull/3485) · [issue #3486](https://github.com/modelcontextprotocol/python-sdk/issues/3486) · 98 FAIL_TO_PASS tests · ⚠️ **tests import a name introduced by the fix**

### Issue

Add SEP-2640 (Skills Extension) protocol support
[SEP-2640 (Skills Extension)](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2640)
is Accepted, but the Python SDK has no support for it. It adds `skills/list`,
`skills/get`, and optional `resources/directory/read`, negotiated under the
`io.modelcontextprotocol/skills` extension.

We need to add the **protocol primitives** — a `Skills(...)` server extension
plus thin client wrappers and SEP-2640 validation — built on the existing
`Extension`/`MethodBinding` mechanism (like the shipped `Apps` extension), with no
schema or dependency changes. Filesystem discovery/caching would stay out of scope
for a higher-level provider.

### Files changed by the gold patch

- `docs/advanced/extensions.md` (+25 / -0)
- `docs/advanced/skills.md` (+134 / -0)
- `docs_src/skills/__init__.py` (+0 / -0)
- `docs_src/skills/tutorial001.py` (+54 / -0)
- `docs_src/skills/tutorial001_client.py` (+18 / -0)
- `mkdocs.yml` (+1 / -0)
- `src/mcp/client/client.py` (+17 / -1)
- `src/mcp/client/extension.py` (+11 / -0)
- `src/mcp/client/extensions/__init__.py` (+3 / -0)
- `src/mcp/client/extensions/skills.py` (+170 / -0)
- `src/mcp/server/skills.py` (+172 / -0)
- `src/mcp/shared/skills.py` (+297 / -0)

### Tests that must pass (names, deduplicated)

- `test_directory_read_is_advertised_when_a_handler_is_supplied`
- `test_directory_read_is_not_advertised_without_a_handler`
- `test_directory_read_is_not_registered_without_a_handler`
- `test_directory_read_rejects_a_handler_result_with_a_grandchild`
- `test_directory_read_rejects_a_trailing_slash_uri`
- `test_directory_read_returns_the_handlers_children`
- `test_extension_rejects_an_unregistered_type`
- `test_extension_requires_a_connected_client`
- `test_extension_returns_a_custom_extensions_typed_binding`
- `test_get_skill_answers_by_uri`
- `test_get_skill_propagates_the_servers_unknown_skill_error`
- `test_get_skill_rejects_a_mismatched_uri_from_a_non_conformant_server`
- `test_get_skill_rejects_an_unknown_uri`
- `test_get_skill_returns_the_matching_entry`
- `test_get_skill_round_trips_a_dynamic_skill`
- `test_list_result_accepts_an_empty_listing`
- `test_list_result_rejects_duplicate_skill_uris_across_entries`
- `test_list_skills_collapses_a_skill_repeated_across_pages`
- `test_list_skills_detects_a_server_repeating_the_caller_supplied_cursor`
- `test_list_skills_follows_next_cursor_to_completion`
- … 60 more

<details><summary>Gold patch</summary>

```diff
diff --git a/docs/advanced/extensions.md b/docs/advanced/extensions.md
index b8372da3df..e8793b8cb1 100644
--- a/docs/advanced/extensions.md
+++ b/docs/advanced/extensions.md
@@ -190,6 +190,31 @@ that did not declare it (error -32021), and a claimed shape from a server that
 skips the gate fails validation, exactly as the spec requires for an
 unrecognized `resultType`. Off by default, on both ends of the wire.
 
+An extension can also expose methods of its own. Pass its type to `client.extension()`
+after connecting to get the API bound to that connection. Run the
+[Skills server](skills.md#serving-a-skill) at `http://localhost:8000/mcp` for this example:
+
+```python
+import anyio
+
+from mcp import Client
+from mcp.client.extensions.skills import Skills
+
+
+async def main() -> None:
+    async with Client("http://localhost:8000/mcp", extensions=[Skills()]) as client:
+        for skill in await client.extension(Skills).list_skills():
+            print(skill.uri)
+
+
+if __name__ == "__main__":
+    anyio.run(main)
+```
+
+`client.extension(Skills)` returns the type produced by `Skills.bind(session)`. Your own
+extension can define the same hook. The client raises `ValueError` when the type was not
+registered and `RuntimeError` when it is not connected.
+
 To advertise an identifier with **no** client-side behaviour (the server gates on
 the capability, the client does nothing, as in the search client above), use
 `advertise()`:
diff --git a/docs/advanced/skills.md b/docs/advanced/skills.md
new file mode 100644
index 0000000000..56f95cfa40
--- /dev/null
+++ b/docs/advanced/skills.md
@@ -0,0 +1,134 @@
+# Skills
+
+[SEP-2640](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2640) defines a
+convention for serving [Agent Skills](https://agentskills.io/) over MCP. A skill is just a
+directory of files — at minimum a `SKILL.md` with YAML frontmatter — that you expose as ordinary
+MCP resources, conventionally under a `skill://` URI.
+
+A server enumerates its skills with `skills/list`, answers for any single one by URI with
+`skills/get`, and — optionally — lists a directory's direct children with
+`resources/directory/read`.
+
+The SDK ships this as the built-in `Skills` extension (`io.modelcontextprotocol/skills`). There's
+one on the server side and one on the client side. If [Extensions](extensions.md) are new to you,
+skim that page first.
+
+!!! info
+    `Skills` gives you the **protocol** primitives: request/response handling, capability
+    advertisement, and SEP-2640 conformance validation.
+
+    It does **not** discover, read, or hash skills from a filesystem. You supply handlers that
+    answer from wherever your catalog actually lives — a database, a generated index, an in-memory
+    list, or a directory you walk yourself — and you serve each skill's files as ordinary resources
+    through `MCPServer.add_resource` or an `@mcp.resource(...)` template handler.
+
+## Serving a skill
+
+Here's a server that serves one skill:
+
+```python title="server.py" hl_lines="31-41 44-51 55"
+--8<-- "docs_src/skills/tutorial001.py"
+```
+
+There are three moves here:
+
+* `Skill(uri=..., frontmatter=..., resources=[...])` is one entry. It has the same shape whether it
+  comes back from `skills/list` or `skills/get`. `resources` is the skill's complete file
+  manifest — every file, `SKILL.md` included, each with a `sha256:...` digest and byte size — or
+  the string `"dynamic"` for content generated on demand.
+* `list_skills` and `get_skill` are plain async callables, invoked once per request. `get_skill`
+  **must** answer for a skill even if your `list_skills` left it out — SEP-2640 requires a server
+  to answer by URI for every skill it serves, listed or not.
+* `mcp.add_resource(TextResource(uri=SKILL_URI, ...))` registers the skill's actual file content,
+  served through the SDK's ordinary resource machinery. `Skills` never reads or writes resource
+  content itself.
+
+And that's it. `Skills(list_skills=..., get_skill=...)` is all a server needs;
+`resources/directory/read` is optional (more on that below).
+
+## Inspecting a skill
+
+On the client side, `Skills` is a [`ClientExtension`](extensions.md). You register it the same way
+you register any other one — by passing it to `Client(extensions=[...])` — and then call `extension` to
+get the verbs tied to that connection:
+
+```python title="client.py" hl_lines="9-11"
+--8<-- "docs_src/skills/tutorial001_client.py"
+```
+
+`client.extension(Skills)` hands you a `SkillsClient` with the SEP-2640 methods:
+
+* `list_skills` and `read_directory` follow `nextCursor` to completion, so a single call gives you
+  every page's skills or resources.
+* `get_skill` costs exactly one request.
+
+These three validate the server's response against the SEP-2640 conformance rules before returning
+it. A name that doesn't match its URI, a digest in the wrong shape, or an incomplete manifest raises
+`ValueError` rather than reaching your code.
+
+Read a skill file with `Client.read_resource(uri)`, the same method you use for any MCP resource.
+It returns raw content without checking it against the skill's manifest.
+
+!!! warning "Verify files before loading"
+    A host that loads a skill must hold its `Skill` entry. Before using a fetched file, check that
+    its URI appears in that entry's `resources` and that its bytes match the advertised size and
+    SHA-256 digest. A `"dynamic"` skill has no digest to check. Refreshing the entry to accept
+    changed bytes also changes the content to which any prior approval applied.
+
+    Skill content is untrusted model input, exactly like any other server-provided text. SEP-2640
+    requires a host to tag it with its originating server before it reaches the model, and to
+    never grant the frontmatter's `allowed-tools` field (or any other permission-widening field)
+    without explicit per-skill user approval.
+
+    A matching digest confirms the *bytes*, not the *frontmatter*: it doesn't prove the
+    `frontmatter` the server advertised in `skills/get` matches the frontmatter inside the fetched
+    `SKILL.md`. If you act on `skill.frontmatter` — especially `allowed-tools` — parse the fetched
+    file and compare its frontmatter yourself.
+
+    These are host responsibilities the SDK cannot discharge for you — read the SEP's
+    [Security Implications](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2640)
+    section before building a host on top of this extension.
+
+## Directory reads
+
+A skill's instructions often point at a directory rather than a file ("pick the matching
+template from `templates/`"). `resources/list` can't answer that — it enumerates a server's
+entire resource space, not one subtree — so SEP-2640 adds `resources/directory/read`, gated
+behind the `directoryRead` capability setting:
+
+```python
+mcp = MCPServer(
+    "catalog",
+    extensions=[
+        Skills(
+            list_skills=list_skills,
+            get_skill=get_skill,
+            read_directory=read_directory,  # lists uri's direct children
+        )
+    ],
+)
+```
+
+Supplying `read_directory` advertises `{"directoryRead": true}` under the extension's
+capabilities. Omitting it advertises neither the setting nor the method — a client calling
+`resources/directory/read` against such a server gets `METHOD_NOT_FOUND`. On the client side,
+`read_directory` raises before it sends anything if the connected server hasn't advertised the
+setting.
+
+## Protocol version and caching
+
+In protocol version `2026-07-28` and later, `skills/list` and `skills/get` results carry the base
+protocol's caching fields, [`ttlMs` and `cacheScope`](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2549) —
+the same freshness hint `tools/list`, `resources/list`, and `resources/read` carry. `Skills` fills
+`cacheScope` with `"private"` when your handler leaves it unset, and omits both fields entirely on an
+older connection. Set `cache_scope="public"` only when the result is the same for every user.
+You don't have to branch on protocol version yourself.
+
+## What this SDK doesn't do
+
+`Skills` is a protocol adapter, not a skills provider. It has no opinion on where a skill's bytes
+live, how they're indexed, or when a catalog is refreshed — that's for a higher-level library, or
+your own handler, to decide.
+
+If you're looking for "scan this directory and serve whatever's in it," you're looking for a
+provider built on top of `Skills`, not `Skills` itself.
diff --git a/docs_src/skills/__init__.py b/docs_src/skills/__init__.py
new file mode 100644
index 0000000000..e69de29bb2
diff --git a/docs_src/skills/tutorial001.py b/docs_src/skills/tutorial001.py
new file mode 100644
index 0000000000..61cc43c2e8
--- /dev/null
+++ b/docs_src/skills/tutorial001.py
@@ -0,0 +1,54 @@
+import hashlib
+from typing import Any
+
+from mcp.server.context import ServerRequestContext
+from mcp.server.mcpserver import MCPServer
+from mcp.server.mcpserver.resources import TextResource
+from mcp.server.skills import Skills
+from mcp.shared.exceptions import MCPError
+from mcp.shared.skills import (
+    GetSkillParams,
+    GetSkillResult,
+    ListSkillsParams,
+    ListSkillsResult,
+    Skill,
+    SkillResource,
+)
+from mcp.types import INVALID_PARAMS
+
+SKILL_URI = "skill://git-workflow/SKILL.md"
+SKILL_MD = """\
+---
+name: git-workflow
+description: Follow this team's Git conventions for branching and commits
+---
+
+Branch from `main` using `type/short-description`. Write commit subjects in the
+imperative mood, under 72 characters.
+"""
+
+GIT_WORKFLOW = Skill(
+    uri=SKILL_URI,
+    frontmatter={"name": "git-workflow", "description": "Follow this team's Git conventions for branching and commits"},
+    resources=[
+        SkillResource(
+            uri=SKILL_URI,
+            digest=f"sha256:{hashlib.sha256(SKILL_MD.encode()).hexdigest()}",
+            size=len(SKILL_MD.encode()),
+        )
+    ],
+)
+
+
+async def list_skills(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+    return ListSkillsResult(skills=[GIT_WORKFLOW])
+
+
+async def get_skill(ctx: ServerRequestContext[Any, Any], params: GetSkillParams) -> GetSkillResult:
+    if params.uri != SKILL_URI:
+        raise MCPError(code=INVALID_PARAMS, message=f"unknown skill: {params.uri}")
+    return GetSkillResult(skill=GIT_WORKFLOW)
+
+
+mcp = MCPServer("catalog", extensions=[Skills(list_skills=list_skills, get_skill=get_skill)])
+mcp.add_resource(TextResource(uri=SKILL_URI, name="SKILL.md", mime_type="text/markdown", text=SKILL_MD))
diff --git a/docs_src/skills/tutorial001_client.py b/docs_src/skills/tutorial001_client.py
new file mode 100644
index 0000000000..27f51fd2f1
--- /dev/null
+++ b/docs_src/skills/tutorial001_client.py
@@ -0,0 +1,18 @@
+import anyio
+
+from mcp import Client
+from mcp.client.extensions.skills import Skills
+
+
+async def main() -> None:
+    async with Client("http://localhost:8000/mcp", extensions=[Skills()]) as client:
+        catalog = client.extension(Skills)
+        for skill in await catalog.list_skills():
+            print(skill.uri, skill.frontmatter["description"])
+
+        skill = await catalog.get_skill("skill://git-workflow/SKILL.md")
+        print(skill.resources)
+
+
+if __name__ == "__main__":
+    anyio.run(main)
diff --git a/mkdocs.yml b/mkdocs.yml
index 1874a04050..62f0640366 100644
--- a/mkdocs.yml
+++ b/mkdocs.yml
@@ -69,6 +69,7 @@ nav:
       - Header parameters: advanced/header-parameters.md
       - Extensions: advanced/extensions.md
       - MCP Apps: advanced/apps.md
+      - Skills: advanced/skills.md
   - Troubleshooting: troubleshooting.md
   - Translations: translations.md
   - Migration Guide: migration.md
diff --git a/src/mcp/client/client.py b/src/mcp/client/client.py
index 8c7d372431..099dcbb874 100644
--- a/src/mcp/client/client.py
+++ b/src/mcp/client/client.py
@@ -49,7 +49,7 @@
 from mcp.client._probe import negotiate_auto
 from mcp.client._transport import Transport
 from mcp.client.caching import CacheConfig, CacheMode, ClientResponseCache, InMemoryResponseCacheStore
-from mcp.client.extension import ClaimContext, ClientExtension, NotificationBinding, ResultClaim
+from mcp.client.extension import ClaimContext, ClientExtension, ClientExtensionBinding, NotificationBinding, ResultClaim
 from mcp.client.session import (
     ClientRequestContext,
     ClientSession,
@@ -87,6 +87,7 @@
 _T = TypeVar("_T")
 _ResultT = TypeVar("_ResultT")
 _CacheableT = TypeVar("_CacheableT", bound=CacheableResult)
+_BoundT = TypeVar("_BoundT")
 
 _Connector = Callable[[AsyncExitStack, ConnectMode, bool], Awaitable["Dispatcher[Any]"]]
 """Resolved at ``__post_init__`` from the shape of ``server`` alone: enter whatever resources
@@ -376,6 +377,7 @@ async def main():
     _connect: _Connector = field(init=False, repr=False, compare=False)
     _response_cache: ClientResponseCache | None = field(init=False, default=None, repr=False, compare=False)
     _folded_extensions: _FoldedExtensions = field(init=False, repr=False, compare=False)
+    _registered_extensions: tuple[ClientExtension, ...] = field(init=False, repr=False, compare=False)
 
     def __post_init__(self) -> None:
         if self.mode not in ("legacy", "auto") and self.mode not in MODERN_PROTOCOL_VERSIONS:
@@ -389,6 +391,7 @@ def __post_init__(self) -> None:
             )
 
         self._folded_extensions = _fold_extensions(self.extensions)
+        self._registered_extensions = tuple(self.extensions or ())
 
         srv = self.server
         if isinstance(srv, MCPServer):
@@ -493,6 +496,19 @@ def session(self) -> ClientSession:
             raise RuntimeError("Client must be used within an async context manager")
         return self._session
 
+    def extension(self, extension_type: type[ClientExtensionBinding[_BoundT]]) -> _BoundT:
+        """Return the typed API of a registered extension for this connection.
+
+        Raises:
+            RuntimeError: If the client is not connected.
+            ValueError: If no extension of this type was registered.
+        """
+        session = self.session
+        for extension in self._registered_extensions:
+            if isinstance(extension, extension_type):
+                return cast(ClientExtensionBinding[_BoundT], extension).bind(session)
+        raise ValueError(f"client extension {extension_type.__name__!r} is not registered")
+
     # TODO(maxisbey): the by-construction shape is for __aenter__ to return a connected-view
     # type whose protocol_version/server_capabilities are non-Optional fields,
     # eliminating these guards (and the one in .session). Same family as resolving the
diff --git a/src/mcp/client/extension.py b/src/mcp/client/extension.py
index a813475e5e..59d08b1bfc 100644
--- a/src/mcp/client/extension.py
+++ b/src/mcp/client/extension.py
@@ -15,6 +15,7 @@
 from mcp_types.version import MODERN_PROTOCOL_VERSIONS
 from pydantic import AliasChoices, AliasPath, BaseModel
 from pydantic.fields import FieldInfo
+from typing_extensions import Protocol
 
 from mcp.shared.extension import validate_extension_identifier
 
@@ -24,6 +25,7 @@
 __all__ = [
     "ClaimContext",
     "ClientExtension",
+    "ClientExtensionBinding",
     "NotificationBinding",
     "ResultClaim",
     "UnexpectedClaimedResult",
@@ -54,6 +56,15 @@ def _wire_keys(name: str, field: FieldInfo) -> frozenset[str]:
 
 ClaimedT = TypeVar("ClaimedT", bound=Result)
 NotifyParamsT = TypeVar("NotifyParamsT", bound=BaseModel)
+BoundT_co = TypeVar("BoundT_co", covariant=True)
+
+
+class ClientExtensionBinding(Protocol[BoundT_co]):
+    """An extension that exposes a typed API for one connected client."""
+
+    def bind(self, session: ClientSession) -> BoundT_co:
+        """Return the extension API bound to `session`."""
+        ...
 
 
 @dataclass(frozen=True, kw_only=True)
diff --git a/src/mcp/client/extensions/__init__.py b/src/mcp/client/extensions/__init__.py
new file mode 100644
index 0000000000..ef91475f99
--- /dev/null
+++ b/src/mcp/client/extensions/__init__.py
@@ -0,0 +1,3 @@
+from mcp.client.extensions.skills import Skills, SkillsClient
+
+__all__ = ["Skills", "SkillsClient"]
diff --git a/src/mcp/client/extensions/skills.py b/src/mcp/client/extensions/skills.py
new file mode 100644
index 0000000000..11c78db816
--- /dev/null
+++ b/src/mcp/client/extensions/skills.py
@@ -0,0 +1,170 @@
+"""Client-side Skills extension (SEP-2640).
+
+`Skills` is an opt-in [`ClientExtension`](../advanced/extensions.md) for talking
+to a skills catalog server. Register it with `Client(extensions=[Skills()])`,
+then call `client.extension(Skills)` for the SEP-2640 verbs — `list_skills`, `get_skill`,
+and `read_directory` — tied to that connection:
+
+    async with Client("http://localhost:8000/mcp", extensions=[Skills()]) as client:
+        for skill in await client.extension(Skills).list_skills():
+            print(skill.uri, skill.frontmatter["description"])
+
+`client.extension(Skills)` returns a `SkillsClient`. Its catalog verbs — `list_skills`,
+`get_skill`, and `read_directory` — check that the server advertises the
+extension and validate its response; `list_skills` and `read_directory` follow
+`nextCursor` to completion, so one call returns every page's results.
+"""
+
+from __future__ import annotations
+
+from mcp_types import Resource
+
+from mcp.client.extension import ClientExtension
+from mcp.client.session import ClientSession
+from mcp.shared.skills import (
+    EXTENSION_ID,
+    GetSkillParams,
+    GetSkillRequest,
+    GetSkillResult,
+    ListSkillsParams,
+    ListSkillsRequest,
+    ListSkillsResult,
+    ReadDirectoryParams,
+    ReadDirectoryRequest,
+    ReadDirectoryResult,
+    Skill,
+    validate_directory_result,
+)
+
+__all__ = ["Skills", "SkillsClient"]
+
+
+class Skills(ClientExtension):
+    """The client-side Skills extension: register, then access its typed verbs.
+
+    Pass an instance to `Client(extensions=[Skills()])` — this advertises
+    `io.modelcontextprotocol/skills` under the client's capabilities — and call
+    `client.extension(Skills)` once connected for a `SkillsClient` handle.
+    """
+
+    identifier = EXTENSION_ID
+
+    def bind(self, session: ClientSession) -> SkillsClient:
+        """Return the SEP-2640 verbs bound to `session`."""
+        return SkillsClient(session)
+
+
+class SkillsClient:
+    """The SEP-2640 verbs bound to one connected session.
+
+    Obtain it from `client.extension(Skills)`. The catalog verbs — `list_skills`,
+    `get_skill`, and `read_directory` — check that the server advertises the
+    extension and validate its response against the SEP-2640 conformance rules
+    before returning; `list_skills` and `read_directory` also follow
+    `nextCursor` to completion. Read a skill's files with the ordinary
+    `Client.read_resource` method.
+    """
+
+    def __init__(self, session: ClientSession) -> None:
+        self._session = session
+
+    def _require_extension(self, *, directory_read: bool = False) -> None:
+        capabilities = self._session.server_capabilities
+        settings = (capabilities.extensions or {}).get(EXTENSION_ID) if capabilities else None
+        if settings is None:
+            raise ValueError(f"server does not advertise the {EXTENSION_ID!r} extension")
+        if directory_read and not settings.get("directoryRead"):
+            raise ValueError(f"server does not advertise {EXTENSION_ID!r}'s directoryRead setting")
+
+    async def list_skills(self, params: ListSkillsParams | None = None) -> list[Skill]:
+        """Call `skills/list`, following `nextCursor` to completion, and validate the result.
+
+        A skill a changing catalog surfaces on more than one page is returned once, in the order
+        first seen.
+
+        Raises:
+            ValueError: If the server doesn't advertise the Skills extension, its response is not
+                SEP-2640 conformant, or it repeats a pagination cursor.
+            MCPError: If the server returns an error response.
+        """
+        self._require_extension()
+        base = params if params is not None else ListSkillsParams()
+        cursor = base.cursor
+        skills: list[Skill] = []
+        seen_cursors: set[str] = {cursor} if cursor is not None else set()
+        seen_uris: set[str] = set()
+        while True:
+            # `send_request` parses each page into `ListSkillsResult`, whose validators reject a
+            # non-conformant skill or a duplicate URI — no separate conformance call is needed.
+            page = await self._session.send_request(
+                ListSkillsRequest(params=base.model_copy(update={"cursor": cursor})), ListSkillsResult
+            )
+            # A server stuck repeating its cursor is a loop; catch that before the content checks.
+            if page.next_cursor is not None and page.next_cursor in seen_cursors:
+                raise ValueError(f"server repeated skills/list pagination cursor {page.next_cursor!r}")
+            # A catalog that changes between page fetches can legitimately repeat a skill across
+            # pages; keep the first occurrence rather than treating it as an error.
+            for skill in page.skills:
+                if skill.uri not in seen_uris:
+                    seen_uris.add(skill.uri)
+                    skills.append(skill)
+            if page.next_cursor is None:
+                return skills
+            seen_cursors.add(page.next_cursor)
+            cursor = page.next_cursor
+
+    async def get_skill(self, uri: str) -> Skill:
+        """Call `skills/get` for `uri` and validate the result.
+
+        Unlike `list_skills`, this succeeds for a skill absent from any listing —
+        per SEP-2640, a server MUST answer `skills/get` for every skill it serves.
+
+        Raises:
+            ValueError: If the server doesn't advertise the Skills extension, its
+                response names a different skill, or the skill is not conformant.
+            MCPError: If the server returns an error response, such as `-32602`
+                for a URI it does not serve.
+        """
+        self._require_extension()
+        # Parsing `GetSkillResult` validates the skill's own conformance; the requested-URI match
+        # is the one rule the skill body can't carry, so it stays an explicit check here.
+        result = await self._session.send_request(GetSkillRequest(params=GetSkillParams(uri=uri)), GetSkillResult)
+        if result.skill.uri != uri:
+            raise ValueError(f"server returned skill {result.skill.uri!r} for requested {uri!r}")
+        return result.skill
+
+    async def read_directory(self, uri: str, params: ReadDirectoryParams | None = None) -> list[Resource]:
+        """Call `resources/directory/read` for `uri`, following `nextCursor` to completion.
+
+        A child a changing directory surfaces on more than one page is returned once, in the order
+        first seen.
+
+        Raises:
+            ValueError: If the server doesn't advertise the `directoryRead` setting, its response
+                is not a valid child listing of `uri`, or it repeats a pagination cursor.
+            MCPError: If the server returns an error response.
+        """
+        self._require_extension(directory_read=True)
+        base = params if params is not None else ReadDirectoryParams(uri=uri)
+        cursor = base.cursor
+        resources: list[Resource] = []
+        seen_cursors: set[str] = {cursor} if cursor is not None else set()
+        seen_uris: set[str] = set()
+        while True:
+            page = await self._session.send_request(
+                ReadDirectoryRequest(params=base.model_copy(update={"uri": uri, "cursor": cursor})),
+                ReadDirectoryResult,
+            )
+            # A server stuck repeating its cursor is a loop; catch that before the content checks.
+            if page.next_cursor is not None and page.next_cursor in seen_cursors:
+                raise ValueError(f"server repeated resources/directory/read pagination cursor {page.next_cursor!r}")
+            validate_directory_result(uri, page)
+            # A changing directory can legitimately repeat a child across pages; keep the first.
+            for resource in page.resources:
+                if resource.uri not in seen_uris:
+                    seen_uris.add(resource.uri)
+                    resources.append(resource)
+            if page.next_cursor is None:
+                return resources
+            seen_cursors.add(page.next_cursor)
+            cursor = page.next_cursor
diff --git a/src/mcp/server/skills.py b/src/mcp/server/skills.py
new file mode 100644
index 0000000000..0c0fac05c4
--- /dev/null
+++ b/src/mcp/server/skills.py
@@ -0,0 +1,172 @@
+"""The Skills extension (`io.modelcontextprotocol/skills`, SEP-2640).
+
+SEP-2640 defines a convention for serving Agent Skills over MCP using the
+Resources primitive: a skill is a directory of files, conventionally exposed
+under the `skill://` scheme, and enumerated and fetched through two required
+methods (`skills/list`, `skills/get`) plus one optional one
+(`resources/directory/read`). See
+https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2640.
+
+This module provides the protocol-level plumbing only: request/response
+handling, SEP-2640 conformance validation, and capability advertisement. It
+does not discover, read, or hash skills from a filesystem — a server author
+supplies handlers that answer `skills/list`/`skills/get`/`resources/directory/read`
+however their catalog is stored, and serves the underlying `skill://` file
+content through the server's ordinary resource-registration APIs
+(`MCPServer.add_resource`, or an `@mcp.resource(...)` template).
+
+    async def list_skills(ctx, params):
+        return ListSkillsResult(skills=[...])
+
+    async def get_skill(ctx, params):
+        if params.uri != "skill://git-workflow/SKILL.md":
+            raise MCPError(code=INVALID_PARAMS, message="unknown skill")
+        return GetSkillResult(skill=...)
+
+    mcp = MCPServer("catalog", extensions=[Skills(list_skills=list_skills, get_skill=get_skill)])
+"""
+
+from __future__ import annotations
+
+from collections.abc import Awaitable, Callable, Sequence
+from typing import Any
+
+from mcp_types import CacheableResult
+from mcp_types.jsonrpc import INTERNAL_ERROR, INVALID_PARAMS
+from mcp_types.version import MODERN_PROTOCOL_VERSIONS
+from pydantic import ValidationError
+
+from mcp.server.context import HandlerResult, ServerRequestContext
+from mcp.server.extension import Extension, MethodBinding
+from mcp.shared.exceptions import MCPError
+from mcp.shared.skills import (
+    EXTENSION_ID,
+    METHOD_GET,
+    METHOD_LIST,
+    METHOD_READ_DIRECTORY,
+    GetSkillParams,
+    GetSkillResult,
+    ListSkillsParams,
+    ListSkillsResult,
+    ReadDirectoryParams,
+    ReadDirectoryResult,
+    parse_directory_uri,
+    skill_name_from_uri,
+    validate_directory_result,
+)
+
+__all__ = ["Skills"]
+
+ListSkillsHandler = Callable[[ServerRequestContext[Any, Any], ListSkillsParams], Awaitable[ListSkillsResult]]
+GetSkillHandler = Callable[[ServerRequestContext[Any, Any], GetSkillParams], Awaitable[GetSkillResult]]
+ReadDirectoryHandler = Callable[[ServerRequestContext[Any, Any], ReadDirectoryParams], Awaitable[ReadDirectoryResult]]
+
+
+class Skills(Extension):
+    """The Skills extension: serve `skills/list`, `skills/get`, and directory reads.
+
+    `list_skills` and `get_skill` are required; a server MUST answer both per
+    SEP-2640, whether or not a skill appears in the listing. `read_directory`
+    is optional — supplying it advertises the `directoryRead` capability
+    setting and serves `resources/directory/read`; omitting it advertises
+    neither. Handlers run per request, so a catalog that changes over time
+    (or is too large to enumerate) can return a partial or empty listing.
+
+    Handler error contract: raise `MCPError` to return a specific error to the
+    caller (e.g. `INVALID_PARAMS` from `get_skill` for a URI it doesn't serve).
+    A result that isn't SEP-2640 conformant is caught here and reported as
+    `INTERNAL_ERROR` — a server fault, not the caller's bad params.
+    """
+
+    identifier = EXTENSION_ID
+
+    def __init__(
+        self,
+        *,
+        list_skills: ListSkillsHandler,
+        get_skill: GetSkillHandler,
+        read_directory: ReadDirectoryHandler | None = None,
+    ) -> None:
+        self._list_skills = list_skills
+        self._get_skill = get_skill
+        self._read_directory = read_directory
+
+    def settings(self) -> dict[str, Any]:
+        return {"directoryRead": True} if self._read_directory is not None else {}
+
+    def methods(self) -> Sequence[MethodBinding]:
+        bindings = [
+            MethodBinding(METHOD_LIST, ListSkillsParams, self._handle_list),
+            MethodBinding(METHOD_GET, GetSkillParams, self._handle_get),
+        ]
+        if self._read_directory is not None:
+            bindings.append(MethodBinding(METHOD_READ_DIRECTORY, ReadDirectoryParams, self._handle_read_directory))
+        return bindings
+
+    async def _handle_list(self, ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> HandlerResult:
+        # `ListSkillsResult`/`Skill` self-validate on construction, so a handler that builds a
+        # non-conformant listing raises `ValidationError` here — a server fault, surfaced as an
+        # Internal error rather than the framework's default Invalid params for a bad body. The
+        # models stay mutable, so re-validate the outbound payload too: a handler that mutates a
+        # skill after building the result can't ship a non-conformant listing past this point.
+        try:
+            result = await self._list_skills(ctx, params)
+            ListSkillsResult.model_validate(result.model_dump())
+        except ValidationError:
+            raise MCPError(code=INTERNAL_ERROR, message="Handler returned an invalid result") from None
+        return _finalize_cacheable(result, ctx.protocol_version)
+
+    async def _handle_get(self, ctx: ServerRequestContext[Any, Any], params: GetSkillParams) -> HandlerResult:
+        _require_skill_md_uri(params.uri)
+        # `Skill` self-validates on construction, and the re-validation guards post-construction
+        # mutation, both as in `_handle_list`.
+        try:
+            result = await self._get_skill(ctx, params)
+            GetSkillResult.model_validate(result.model_dump())
+        except ValidationError:
+            raise MCPError(code=INTERNAL_ERROR, message="Handler returned an invalid result") from None
+        if result.skill.uri != params.uri:
+            raise MCPError(code=INTERNAL_ERROR, message="Handler returned an invalid result")
+        return _finalize_cacheable(result, ctx.protocol_version)
+
+    async def _handle_read_directory(
+        self, ctx: ServerRequestContext[Any, Any], params: ReadDirectoryParams
+    ) -> HandlerResult:
+        assert self._read_directory is not None
+        _require_directory_uri(params.uri)
+        result = await self._read_directory(ctx, params)
+        try:
+            validate_directory_result(params.uri, result)
+        except ValueError:
+            raise MCPError(code=INTERNAL_ERROR, message="Handler returned an invalid result") from None
+        return result
+
+
+def _require_skill_md_uri(uri: str) -> None:
+    try:
+        skill_name_from_uri(uri)
+    except ValueError as exc:
+        raise MCPError(code=INVALID_PARAMS, message=str(exc)) from exc
+
+
+def _require_directory_uri(uri: str) -> None:
+    try:
+        parse_directory_uri(uri)
+    except ValueError as exc:
+        raise MCPError(code=INVALID_PARAMS, message=str(exc)) from exc
+
+
+def _finalize_cacheable(result: CacheableResult, protocol_version: str) -> HandlerResult:
+    """Gate SEP-2549's `ttlMs`/`cacheScope` to protocol version 2026-07-28+.
+
+    `skills/list` and `skills/get` are extension methods, so — unlike a core spec
+    method — the runner's per-version surface sieve never runs on their results;
+    nothing else strips these fields for a legacy connection. `CacheableResult`
+    defaults to `cache_scope="private"`, keeping user-specific entries out of shared caches.
+    """
+    if protocol_version in MODERN_PROTOCOL_VERSIONS:
+        return result
+    dumped = result.model_dump(by_alias=True, mode="json", exclude_none=True)
+    dumped.pop("ttlMs", None)
+    dumped.pop("cacheScope", None)
+    return dumped
diff --git a/src/mcp/shared/skills.py b/src/mcp/shared/skills.py
new file mode 100644
index 0000000000..eb6dbe51ca
--- /dev/null
+++ b/src/mcp/shared/skills.py
@@ -0,0 +1,297 @@
+"""Wire types and SEP-2640 conformance checks for the Skills extension.
+
+Shared by the server (`mcp.server.skills`) and client (`mcp.client.extensions.skills`)
+surfaces, mirroring how `mcp.shared.extension` hosts the identifier grammar
+both tiers need. See https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2640.
+"""
+
+from __future__ import annotations
+
+import re
+from typing import Annotated, Any, Literal
+from urllib.parse import urlsplit
+
+from mcp_types import CacheableResult, PaginatedRequestParams, PaginatedResult, Request, RequestParams, Resource
+from pydantic import AfterValidator, BaseModel, ConfigDict, Field, model_validator
+from pydantic.alias_generators import to_camel
+
+__all__ = [
+    "Frontmatter",
+    "SkillResource",
+    "SkillResources",
+    "Skill",
+    "ListSkillsParams",
+    "ListSkillsResult",
+    "GetSkillParams",
+    "GetSkillResult",
+    "ReadDirectoryParams",
+    "ReadDirectoryResult",
+]
+
+EXTENSION_ID = "io.modelcontextprotocol/skills"
+"""The Skills extension identifier, advertised under `ServerCapabilities.extensions`."""
+
+METHOD_LIST = "skills/list"
+METHOD_GET = "skills/get"
+METHOD_READ_DIRECTORY = "resources/directory/read"
+
+MAX_RESOURCES_PER_SKILL = 512
+"""SEP-2640 per-skill resource-count threshold (`SKILL.md` included).
+
+A SHOULD NOT limit, not a hard cap: the spec requires a host to support skills
+*up to and including* 512 entries and permits it to support larger ones, so a
+`Skill` does not reject an over-count manifest."""
+
+MAX_TOTAL_SIZE = 16 * 1024 * 1024
+"""SEP-2640 per-skill total-byte-size threshold (16 MiB), summed over `resources[].size`.
+
+A SHOULD NOT limit, not a hard cap (see `MAX_RESOURCES_PER_SKILL`); an over-size
+manifest is not rejected."""
+
+_NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
+_DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
+
+
+def _check_digest(value: str) -> str:
+    if not _DIGEST_RE.fullmatch(value):
+        raise ValueError(f"invalid SHA-256 digest {value!r}; expected 'sha256:' + 64 lowercase hex characters")
+    return value
+
+
+class _SkillModel(BaseModel):
+    """Base for Skills value types: matches `mcp_types`' internal `MCPModel` config.
+
+    `MCPModel` itself isn't public; every field defined below is already a
+    single word, so this only matters if a future field needs camelCase.
+    """
+
+    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)
+
+
+class SkillResource(_SkillModel):
+    """One file in a skill's manifest: `{uri, digest, size}`.
+
+    Shape rules are intrinsic: a `digest` that isn't `sha256:` + 64 lowercase
+    hex characters, or a negative `size`, is rejected at construction.
+    """
+
+    uri: str
+    digest: Annotated[str, AfterValidator(_check_digest)]
+    """SHA-256 digest of the file's raw bytes, formatted `sha256:{64 hex chars}`."""
+    size: Annotated[int, Field(ge=0)]
+    """Length in bytes of the file's raw content."""
+
+
+Frontmatter = dict[str, Any]
+"""A skill's `SKILL.md` YAML frontmatter, rendered verbatim as JSON."""
+
+SkillResources = list[SkillResource] | Literal["dynamic"]
+"""A skill's complete resource manifest, or the `"dynamic"` marker (SEP-2640 Resources)."""
+
+
+class Skill(_SkillModel):
+    """An entry returned by `skills/list` or `skills/get`.
+
+    SEP-2640 conformance is intrinsic: constructing (or parsing) a `Skill`
+    validates the frontmatter `name`/`description`, and — unless `resources` is
+    `"dynamic"` — that every entry names a file within the skill's own directory,
+    with no duplicates and `SKILL.md` present. The `MAX_RESOURCES_PER_SKILL`
+    (512-entry) and `MAX_TOTAL_SIZE` (16-MiB) limits are SHOULD NOT thresholds,
+    not MUST NOT, so an over-limit manifest is accepted.
+    """
+
+    uri: str
+    """Resource URI of the skill's `SKILL.md`."""
+    frontmatter: Frontmatter
+    resources: SkillResources
+
+    @model_validator(mode="after")
+    def _check_conformance(self) -> Skill:
+        name = skill_name_from_uri(self.uri)
+        frontmatter_name = self.frontmatter.get("name")
+        if (
+            not isinstance(frontmatter_name, str)
+            or not _NAME_RE.fullmatch(frontmatter_name)
+            or len(frontmatter_name) > 64
+        ):
+            raise ValueError(f"skill {self.uri!r} frontmatter name must be 1-64 lowercase, digits, or hyphens")
+        if frontmatter_name != name:
+            raise ValueError(
+                f"skill {self.uri!r} frontmatter name {frontmatter_name!r} does not match URI name {name!r}"
+            )
+        description = self.frontmatter.get("description")
+        if not isinstance(description, str) or not (1 <= len(description) <= 1024):
+            raise ValueError(f"skill {self.uri!r} frontmatter description must contain 1 to 1024 characters")
+        if self.resources == "dynamic":
+            return self
+        seen: set[str] = set()
+        for resource in self.resources:
+            _validate_resource_uri_in_skill(self.uri, resource.uri)
+            if resource.uri in seen:
+                raise ValueError(f"skill {self.uri!r} lists resource {resource.uri!r} more than once")
+            seen.add(resource.uri)
+        if self.uri not in seen:
+            raise ValueError(f"skill {self.uri!r} resources does not include its own SKILL.md")
+        return self
+
+
+class ListSkillsParams(PaginatedRequestParams):
+    """Parameters for `skills/list`."""
+
+
+class ListSkillsResult(PaginatedResult, CacheableResult):
+    """Result of `skills/list`.
+
+    Each skill self-validates; on top of that, constructing (or parsing) this
+    result rejects two entries that share a `uri`.
+
+    `ttl_ms`/`cache_scope` are SEP-2549 fields inherited from `CacheableResult`;
+    unlike a core spec method, nothing sieves them off the wire for a
+    pre-2026-07-28 connection automatically (see `mcp.server.skills`), so
+    callers constructing this directly for such a connection must omit them.
+    """
+
+    skills: list[Skill]
+
+    @model_validator(mode="after")
+    def _check_unique_uris(self) -> ListSkillsResult:
+        seen: set[str] = set()
+        for skill in self.skills:
+            if skill.uri in seen:
+                raise ValueError(f"skills/list result lists skill {skill.uri!r} more than once")
+            seen.add(skill.uri)
+        return self
+
+
+class GetSkillParams(RequestParams):
+    """Parameters for `skills/get`."""
+
+    uri: str
+    """URI of the skill's `SKILL.md`."""
+
+
+class GetSkillResult(CacheableResult):
+    """Result of `skills/get`.
+
+    Like `ListSkillsResult`, this extends `CacheableResult`: the stable spec page
+    makes `GetSkillResult` carry SEP-2549's `ttl_ms`/`cache_scope`, the same
+    freshness hint `resources/read` gives. As on `skills/list`, nothing sieves
+    these fields off the wire for a pre-2026-07-28 connection automatically (see
+    `mcp.server.skills`), so a caller constructing this directly for such a
+    connection must omit them.
+    """
+
+    skill: Skill
+
+
+class ReadDirectoryParams(PaginatedRequestParams):
+    """Parameters for `resources/directory/read`."""
+
+    uri: str
+    """URI of the directory resource whose direct children are listed."""
+
+
+class ReadDirectoryResult(PaginatedResult):
+    """Result of `resources/directory/read`."""
+
+    resources: list[Resource]
+
+
+class ListSkillsRequest(Request[ListSkillsParams | None, Literal["skills/list"]]):
+    method: Literal["skills/list"] = "skills/list"
+    params: ListSkillsParams | None = None
+
+
+class GetSkillRequest(Request[GetSkillParams, Literal["skills/get"]]):
+    method: Literal["skills/get"] = "skills/get"
+    params: GetSkillParams
+
+
+class ReadDirectoryRequest(Request[ReadDirectoryParams, Literal["resources/directory/read"]]):
+    method: Literal["resources/directory/read"] = "resources/directory/read"
+    params: ReadDirectoryParams
+
+
+def skill_name_from_uri(uri: str) -> str:
+    """Return the skill `name` encoded in a `SKILL.md` resource URI.
+
+    Per SEP-2640 Resource Mapping, the final `<skill-path>` segment equals the
+    skill's `name`; for a bare `skill://<name>/SKILL.md` (no organizational
+    prefix) that segment is the authority.
+
+    Raises:
+        ValueError: If `uri` is not an absolute URI ending in `/SKILL.md`.
+    """
+    parts = urlsplit(uri)
+    if not parts.scheme or parts.query or parts.fragment:
+        raise ValueError(f"skill URI {uri!r} is not a valid absolute resource URI")
+    if not parts.path.endswith("/SKILL.md"):
+        raise ValueError(f"skill URI {uri!r} must end in /SKILL.md")
+    directory = parts.path[: -len("/SKILL.md")].strip("/")
+    if directory:
+        name = directory.rsplit("/", 1)[-1]
+    else:
+        name = parts.hostname or ""
+    if not name:
+        raise ValueError(f"skill URI {uri!r} has no skill name")
+    return name
+
+
+def _validate_resource_uri_in_skill(skill_uri: str, resource_uri: str) -> None:
+    """Raise `ValueError` unless `resource_uri` names a file within `skill_uri`'s directory."""
+    skill_parts = urlsplit(skill_uri)
+    resource_parts = urlsplit(resource_uri)
+    if not resource_parts.scheme or resource_parts.query or resource_parts.fragment:
+        raise ValueError(f"resource URI {resource_uri!r} is invalid")
+    if resource_uri.endswith("/"):
+        raise ValueError(f"resource URI {resource_uri!r} names a directory, not a file")
+    if skill_parts.scheme != resource_parts.scheme or skill_parts.netloc != resource_parts.netloc:
+        raise ValueError(f"resource URI {resource_uri!r} is outside the skill root {skill_uri!r}")
+    root = skill_parts.path[: -len("/SKILL.md")]
+    if resource_parts.path != skill_parts.path and not resource_parts.path.startswith(root + "/"):
+        raise ValueError(f"resource URI {resource_uri!r} is outside the skill root {skill_uri!r}")
+    if any(segment in (".", "..") for segment in resource_parts.path.split("/")):
+        raise ValueError(f"resource URI {resource_uri!r} contains a traversal segment")
+
+
+def parse_directory_uri(uri: str) -> tuple[str, str, str]:
+    """Split a directory resource URI into `(scheme, netloc, path)`.
+
+    Raises:
+        ValueError: If `uri` has a trailing slash, or is otherwise not a valid
+            absolute resource URI.
+    """
+    if uri.endswith("/"):
+        raise ValueError(f"directory URI {uri!r} must not have a trailing slash")
+    parts = urlsplit(uri)
+    if not parts.scheme or parts.query or parts.fragment:
+        raise ValueError(f"directory URI {uri!r} is not a valid absolute resource URI")
+    return parts.scheme, parts.netloc, parts.path
+
+
+def validate_directory_result(uri: str, result: ReadDirectoryResult) -> None:
+    """Validate that each entry in `result.resources` is a unique direct child of `uri`.
+
+    Checks containment and shape only — that every listed resource is a direct
+    child of `uri` with a unique `uri`. It cannot confirm the listing
+    is exhaustive, since it has no independent view of the directory's contents.
+
+    Raises:
+        ValueError: If `uri` is malformed, or any entry is not a direct child,
+            or two entries share a `uri`.
+    """
+    scheme, netloc, parent_path = parse_directory_uri(uri)
+    seen_uris: set[str] = set()
+    prefix = parent_path.rstrip("/") + "/" if parent_path.rstrip("/") else "/"
+    for resource in result.resources:
+        child = urlsplit(resource.uri)
+        if not child.scheme or child.query or child.fragment:
+            raise ValueError(f"directory {uri!r} child has invalid URI {resource.uri!r}")
+        if child.scheme != scheme or child.netloc != netloc:
+            raise ValueError(f"resource {resource.uri!r} is not a child of directory {uri!r}")
+        relative = child.path.removeprefix(prefix)
+        if relative == child.path or not relative or "/" in relative or relative in (".", ".."):
+            raise ValueError(f"resource {resource.uri!r} is not a direct child of directory {uri!r}")
+        if resource.uri in seen_uris:
+            raise ValueError(f"directory {uri!r} contains a duplicate child {resource.uri!r}")
+        seen_uris.add(resource.uri)
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/tests/client/extensions/test_skills.py b/tests/client/extensions/test_skills.py
new file mode 100644
index 0000000000..c6d044ea09
--- /dev/null
+++ b/tests/client/extensions/test_skills.py
@@ -0,0 +1,350 @@
+"""Tests for the client-side Skills extension (SEP-2640, `mcp.client.extensions.skills`)."""
+
+import hashlib
+from collections.abc import AsyncIterator
+from contextlib import asynccontextmanager
+from typing import Any
+
+import pytest
+from mcp_types import INVALID_PARAMS, Resource
+
+from mcp.client.client import Client
+from mcp.client.extensions.skills import Skills as ClientSkills
+from mcp.client.extensions.skills import SkillsClient
+from mcp.server.context import ServerRequestContext
+from mcp.server.extension import Extension, MethodBinding
+from mcp.server.mcpserver import MCPServer
+from mcp.server.mcpserver.resources import TextResource
+from mcp.server.skills import Skills
+from mcp.shared.exceptions import MCPError
+from mcp.shared.skills import (
+    EXTENSION_ID,
+    METHOD_GET,
+    GetSkillParams,
+    GetSkillResult,
+    ListSkillsParams,
+    ListSkillsResult,
+    ReadDirectoryParams,
+    ReadDirectoryResult,
+    Skill,
+    SkillResource,
+)
+
+pytestmark = pytest.mark.anyio
+
+_SKILL_URI = "skill://git-workflow/SKILL.md"
+_SKILL_CONTENT = "# git-workflow\n"
+_SKILL_DIGEST = f"sha256:{hashlib.sha256(_SKILL_CONTENT.encode()).hexdigest()}"
+
+
+def _skill() -> Skill:
+    return Skill(
+        uri=_SKILL_URI,
+        frontmatter={"name": "git-workflow", "description": "d"},
+        resources=[SkillResource(uri=_SKILL_URI, digest=_SKILL_DIGEST, size=len(_SKILL_CONTENT))],
+    )
+
+
+async def _get_skill(ctx: ServerRequestContext[Any, Any], params: GetSkillParams) -> GetSkillResult:
+    if params.uri != _SKILL_URI:
+        raise MCPError(code=INVALID_PARAMS, message="unknown skill")
+    return GetSkillResult(skill=_skill())
+
+
+def _paginated_list_handler() -> Any:
+    """A `list_skills` handler serving two skills across two pages, by URI order."""
+    pages = {
+        None: ([_skill()], "page-2"),
+        "page-2": (
+            [
+                Skill(
+                    uri="skill://other/SKILL.md", frontmatter={"name": "other", "description": "d"}, resources="dynamic"
+                )
+            ],
+            None,
+        ),
+    }
+
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+        skills, next_cursor = pages[params.cursor]
+        return ListSkillsResult(skills=skills, next_cursor=next_cursor)
+
+    return handler
+
+
+def _repeating_cursor_list_handler() -> Any:
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+        return ListSkillsResult(skills=[_skill()], next_cursor="same-cursor-forever")
+
+    return handler
+
+
+class _NonConformantGetSkill(Extension):
+    """A server that advertises the extension but answers `skills/get` with the wrong skill -
+    the case the SDK's own `Skills` extension already rules out server-side, so this
+    exercises `mcp.client.extensions.skills.SkillsClient.get_skill`'s own defense-in-depth check."""
+
+    identifier = EXTENSION_ID
+
+    def methods(self) -> Any:
+        async def handler(ctx: ServerRequestContext[Any, Any], params: GetSkillParams) -> GetSkillResult:
+            return GetSkillResult(skill=_skill())
+
+        return [MethodBinding(METHOD_GET, GetSkillParams, handler)]
+
+
+def _repeating_cursor_directory_handler() -> Any:
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ReadDirectoryParams) -> ReadDirectoryResult:
+        return ReadDirectoryResult(
+            resources=[Resource(uri="skill://git-workflow/references/A.md", name="A.md")],
+            next_cursor="same-cursor-forever",
+        )
+
+    return handler
+
+
+def _paginated_directory_handler() -> Any:
+    pages = {
+        None: (
+            [Resource(uri="skill://git-workflow/references/A.md", name="A.md")],
+            "page-2",
+        ),
+        "page-2": (
+            [Resource(uri="skill://git-workflow/references/B.md", name="B.md")],
+            None,
+        ),
+    }
+
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ReadDirectoryParams) -> ReadDirectoryResult:
+        resources, next_cursor = pages[params.cursor]
+        return ReadDirectoryResult(resources=resources, next_cursor=next_cursor)
+
+    return handler
+
+
+def _server(*, with_directory_read: bool = False) -> MCPServer:
+    server = MCPServer(
+        "catalog",
+        extensions=[
+            Skills(
+                list_skills=_paginated_list_handler(),
+                get_skill=_get_skill,
+                read_directory=_paginated_directory_handler() if with_directory_read else None,
+            )
+        ],
+    )
+    server.add_resource(TextResource(uri=_SKILL_URI, name="SKILL.md", text=_SKILL_CONTENT))
+    return server
+
+
+@asynccontextmanager
+async def _skills(server: MCPServer) -> AsyncIterator[SkillsClient]:
+    """Register the client `Skills` extension, connect, and yield the bound verbs."""
+    extension = ClientSkills()
+    async with Client(server, extensions=[extension]) as client:
+        yield client.extension(ClientSkills)
+
+
+async def test_list_skills_follows_next_cursor_to_completion() -> None:
+    async with _skills(_server()) as skills:
+        result = await skills.list_skills()
+    assert [s.uri for s in result] == [_SKILL_URI, "skill://other/SKILL.md"]
+
+
+async def test_list_skills_raises_on_a_server_that_repeats_its_cursor() -> None:
+    server = MCPServer(
+        "catalog", extensions=[Skills(list_skills=_repeating_cursor_list_handler(), get_skill=_get_skill)]
+    )
+    async with _skills(server) as skills:
+        with pytest.raises(ValueError, match="repeated"):
+            await skills.list_skills()
+
+
+async def test_list_skills_collapses_a_skill_repeated_across_pages() -> None:
+    """A catalog that changes between page fetches can surface the same skill on two pages; the
+    client returns it once (first occurrence) rather than failing or duplicating it."""
+
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+        if params.cursor is None:
+            return ListSkillsResult(skills=[_skill()], next_cursor="page-2")
+        return ListSkillsResult(skills=[_skill()], next_cursor=None)
+
+    server = MCPServer("catalog", extensions=[Skills(list_skills=handler, get_skill=_get_skill)])
+    async with _skills(server) as skills:
+        result = await skills.list_skills()
+    assert [s.uri for s in result] == [_SKILL_URI]
+
+
+async def test_list_skills_requires_the_extension_to_be_advertised() -> None:
+    """No `Skills` extension at all: the server never advertises `io.modelcontextprotocol/skills`."""
+    async with _skills(MCPServer("plain")) as skills:
+        with pytest.raises(ValueError, match="does not advertise"):
+            await skills.list_skills()
+
+
+async def test_get_skill_returns_the_matching_entry() -> None:
+    async with _skills(_server()) as skills:
+        skill = await skills.get_skill(_SKILL_URI)
+    assert skill.uri == _SKILL_URI
+
+
+async def test_get_skill_propagates_the_servers_unknown_skill_error() -> None:
+    async with _skills(_server()) as skills:
+        with pytest.raises(MCPError) as exc_info:
+            await skills.get_skill("skill://missing/SKILL.md")
+    assert exc_info.value.code == INVALID_PARAMS
+
+
+async def test_read_directory_follows_next_cursor_to_completion() -> None:
+    async with _skills(_server(with_directory_read=True)) as skills:
+        resources = await skills.read_directory("skill://git-workflow/references")
+    assert [r.uri for r in resources] == [
+        "skill://git-workflow/references/A.md",
+        "skill://git-workflow/references/B.md",
+    ]
+
+
+async def test_read_directory_accepts_distinct_children_with_the_same_name() -> None:
+    """SEP-2640 Directory Listing: child identity comes from URI, not Resource.name."""
+
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ReadDirectoryParams) -> ReadDirectoryResult:
+        return ReadDirectoryResult(
+            resources=[
+                Resource(uri="skill://git-workflow/references/a.md", name="example"),
+                Resource(uri="skill://git-workflow/references/b.md", name="example"),
+            ]
+        )
+
+    server = MCPServer(
+        "catalog",
+        extensions=[Skills(list_skills=_paginated_list_handler(), get_skill=_get_skill, read_directory=handler)],
+    )
+    async with _skills(server) as skills:
+        resources = await skills.read_directory("skill://git-workflow/references")
+    assert [resource.uri for resource in resources] == [
+        "skill://git-workflow/references/a.md",
+        "skill://git-workflow/references/b.md",
+    ]
+
+
+async def test_read_directory_requires_the_directory_read_setting() -> None:
+    """The extension is advertised, but without `directoryRead: true`."""
+    async with _skills(_server(with_directory_read=False)) as skills:
+        with pytest.raises(ValueError, match="directoryRead"):
+            await skills.read_directory("skill://git-workflow/references")
+
+
+async def test_read_directory_raises_on_a_server_that_repeats_its_cursor() -> None:
+    server = MCPServer(
+        "catalog",
+        extensions=[
+            Skills(
+                list_skills=_paginated_list_handler(),
+                get_skill=_get_skill,
+                read_directory=_repeating_cursor_directory_handler(),
+            )
+        ],
+    )
+    async with _skills(server) as skills:
+        with pytest.raises(ValueError, match="repeated"):
+            await skills.read_directory("skill://git-workflow/references")
+
+
+async def test_read_directory_collapses_a_child_repeated_across_pages() -> None:
+    """A changing directory can surface the same child on two pages; the client returns it once."""
+    child = Resource(uri="skill://git-workflow/references/A.md", name="A.md")
+
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ReadDirectoryParams) -> ReadDirectoryResult:
+        if params.cursor is None:
+            return ReadDirectoryResult(resources=[child], next_cursor="page-2")
+        return ReadDirectoryResult(resources=[child], next_cursor=None)
+
+    server = MCPServer(
+        "catalog",
+        extensions=[Skills(list_skills=_paginated_list_handler(), get_skill=_get_skill, read_directory=handler)],
+    )
+    async with _skills(server) as skills:
+        resources = await skills.read_directory("skill://git-workflow/references")
+    assert [r.uri for r in resources] == ["skill://git-workflow/references/A.md"]
+
+
+async def test_get_skill_rejects_a_mismatched_uri_from_a_non_conformant_server() -> None:
+    server = MCPServer("catalog", extensions=[_NonConformantGetSkill()])
+    async with _skills(server) as skills:
+        with pytest.raises(ValueError, match="returned skill"):
+            await skills.get_skill("skill://other/SKILL.md")
+
+
+async def test_get_skill_round_trips_a_dynamic_skill() -> None:
+    """SEP-2640 Resources: the `"dynamic"` marker survives the full server -> wire -> client
+    path — validated on both ends — with the union type intact, not coerced to a list or null."""
+    dynamic = Skill(
+        uri="skill://generated/SKILL.md",
+        frontmatter={"name": "generated", "description": "instructions generated on demand"},
+        resources="dynamic",
+    )
+
+    async def get_dynamic(ctx: ServerRequestContext[Any, Any], params: GetSkillParams) -> GetSkillResult:
+        # The server's own _handle_get already enforces the requested-uri match; this test only
+        # ever asks for `dynamic.uri`, so the handler just returns it.
+        return GetSkillResult(skill=dynamic)
+
+    server = MCPServer("catalog", extensions=[Skills(list_skills=_paginated_list_handler(), get_skill=get_dynamic)])
+    async with _skills(server) as skills:
+        skill = await skills.get_skill(dynamic.uri)
+    assert skill.resources == "dynamic"
+    assert skill.frontmatter["name"] == "generated"
+
+
+async def test_list_skills_starts_from_a_caller_supplied_cursor() -> None:
+    """A host resuming from a saved cursor: `list_skills` begins at that cursor rather than the
+    top, so only the pages after it come back (here, page 1's skill is skipped)."""
+    async with _skills(_server()) as skills:
+        result = await skills.list_skills(ListSkillsParams(cursor="page-2"))
+    assert [s.uri for s in result] == ["skill://other/SKILL.md"]
+
+
+async def test_list_skills_detects_a_server_repeating_the_caller_supplied_cursor() -> None:
+    """The starting cursor seeds the seen-cursor set: a server that hands back the very cursor
+    the caller resumed from is caught as a repeat on the first page, not chased a second time."""
+    calls = 0
+
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+        nonlocal calls
+        calls += 1
+        return ListSkillsResult(skills=[_skill()], next_cursor="resume-here")
+
+    server = MCPServer("catalog", extensions=[Skills(list_skills=handler, get_skill=_get_skill)])
+    async with _skills(server) as skills:
+        with pytest.raises(ValueError, match="repeated"):
+            await skills.list_skills(ListSkillsParams(cursor="resume-here"))
+    assert calls == 1
+
+
+async def test_list_skills_threads_request_meta_onto_every_page() -> None:
+    """A caller-supplied `_meta` rides along with each page request, not just the first."""
+    seen_meta: list[Any] = []
+
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+        seen_meta.append(params.meta)
+        if params.cursor is None:
+            return ListSkillsResult(skills=[_skill()], next_cursor="page-2")
+        return ListSkillsResult(
+            skills=[
+                Skill(
+                    uri="skill://other/SKILL.md", frontmatter={"name": "other", "description": "d"}, resources="dynamic"
+                )
+            ],
+            next_cursor=None,
+        )
+
+    server = MCPServer("catalog", extensions=[Skills(list_skills=handler, get_skill=_get_skill)])
+    async with _skills(server) as skills:
+        params = ListSkillsParams.model_validate({"_meta": {"progressToken": "t"}})
+        await skills.list_skills(params)
+    # `_meta` crosses the wire camelCase (`progressToken`), but the server deserializes it back
+    # through the meta model, which exposes the known field snake_case as `progress_token`; the
+    # transport also enriches `_meta` with its own keys. What matters is the caller's token
+    # reaching the server on both the first page and the cursor-following second one.
+    assert len(seen_meta) == 2
+    assert all(m is not None and m.get("progress_token") == "t" for m in seen_meta)
diff --git a/tests/client/test_client_extensions.py b/tests/client/test_client_extensions.py
index f80cfe8841..d2b79ef876 100644
--- a/tests/client/test_client_extensions.py
+++ b/tests/client/test_client_extensions.py
@@ -17,7 +17,7 @@
 
 from mcp.client import ClaimContext, ClientExtension, NotificationBinding, ResultClaim, advertise
 from mcp.client.client import Client
-from mcp.client.session import ClientRequestContext, _CallToolResultAdapter
+from mcp.client.session import ClientRequestContext, ClientSession, _CallToolResultAdapter
 from mcp.server import Server, ServerRequestContext
 from mcp.server.context import CallNext, HandlerResult
 from mcp.server.extension import Extension
@@ -59,6 +59,13 @@ def claims(self) -> Sequence[ResultClaim[Any]]:
         return [ResultClaim(result_type="voucher", model=VoucherResult, resolve=self._resolve)]
 
 
+class _SessionExtension(ClientExtension):
+    identifier = "com.example/session"
+
+    def bind(self, session: ClientSession) -> ClientSession:
+        return session
+
+
 class _VoucherIssuer(Extension):
     """Server half: rewrites every `tools/call` result into the vendor-claimed shape."""
 
@@ -166,6 +173,30 @@ def test_mapping_extensions_get_the_migration_error() -> None:
     )
 
 
+async def test_extension_returns_a_custom_extensions_typed_binding() -> None:
+    """SDK-defined: custom extensions can expose typed methods through Client.extension."""
+    async with Client(_add_server(), extensions=[advertise("com.example/other"), _SessionExtension()]) as client:
+        bound = client.extension(_SessionExtension)
+        assert_type(bound, ClientSession)
+        assert bound is client.session
+
+
+async def test_extension_rejects_an_unregistered_type() -> None:
+    """SDK-defined: a client cannot bind an extension it did not register."""
+    async with Client(_add_server()) as client:
+        with pytest.raises(ValueError) as exc_info:
+            client.extension(_SessionExtension)
+    assert str(exc_info.value) == snapshot("client extension '_SessionExtension' is not registered")
+
+
+def test_extension_requires_a_connected_client() -> None:
+    """SDK-defined: extension methods require a live session."""
+    client = Client(_add_server(), extensions=[_SessionExtension()])
+    with pytest.raises(RuntimeError) as exc_info:
+        client.extension(_SessionExtension)
+    assert str(exc_info.value) == snapshot("Client must be used within an async context manager")
+
+
 def test_one_extension_claiming_a_tag_twice_reads_as_one_owner() -> None:
     """SDK-defined: a self-conflict names the one extension once, not as a pair."""
     with pytest.raises(ValueError) as exc_info:
diff --git a/tests/docs_src/test_skills.py b/tests/docs_src/test_skills.py
new file mode 100644
index 0000000000..de64e523b2
--- /dev/null
+++ b/tests/docs_src/test_skills.py
@@ -0,0 +1,47 @@
+"""`docs/advanced/skills.md`: every claim the page makes, proved against the real SDK."""
+
+import pytest
+from mcp_types import INVALID_PARAMS, TextResourceContents
+
+from docs_src.skills import tutorial001
+from mcp import Client
+from mcp.client.extensions.skills import Skills
+from mcp.shared.exceptions import MCPError
+
+pytestmark = pytest.mark.anyio
+
+
+async def test_list_skills_returns_the_registered_skill() -> None:
+    """tutorial001: `list_skills` returns the one skill the server declared."""
+    skills = Skills()
+    async with Client(tutorial001.mcp, extensions=[skills]) as client:
+        result = await client.extension(Skills).list_skills()
+    assert [s.uri for s in result] == [tutorial001.SKILL_URI]
+
+
+async def test_get_skill_answers_by_uri() -> None:
+    """tutorial001: `get_skill` returns the same entry `list_skills` does."""
+    skills = Skills()
+    async with Client(tutorial001.mcp, extensions=[skills]) as client:
+        skill = await client.extension(Skills).get_skill(tutorial001.SKILL_URI)
+    assert skill.frontmatter["name"] == "git-workflow"
+
+
+async def test_get_skill_rejects_an_unknown_uri() -> None:
+    """tutorial001: `get_skill` raises `-32602` (Invalid params) for an unknown skill."""
+    skills = Skills()
+    async with Client(tutorial001.mcp, extensions=[skills]) as client:
+        with pytest.raises(MCPError) as exc_info:
+            await client.extension(Skills).get_skill("skill://unknown/SKILL.md")
+    assert exc_info.value.code == INVALID_PARAMS
+
+
+async def test_the_skill_file_is_served_as_an_ordinary_resource() -> None:
+    """tutorial001: `Skills` never reads or serves content itself — the file is registered
+    through `mcp.add_resource`, the SDK's ordinary resource machinery."""
+    async with Client(tutorial001.mcp) as client:
+        result = await client.read_resource(tutorial001.SKILL_URI)
+    contents = result.contents[0]
+    assert isinstance(contents, TextResourceContents)
+    assert contents.mime_type == "text/markdown"
+    assert contents.text == tutorial001.SKILL_MD
diff --git a/tests/server/test_skills.py b/tests/server/test_skills.py
new file mode 100644
index 0000000000..3f430838b4
--- /dev/null
+++ b/tests/server/test_skills.py
@@ -0,0 +1,360 @@
+"""Tests for the Skills extension (`io.modelcontextprotocol/skills`, SEP-2640).
+
+`mcp.shared.skills`'s validators are unit-tested in `tests/shared/test_skills.py`; this
+file covers this module's own wiring: request dispatch, capability advertisement, the
+`skills/get`/`resources/directory/read` URI checks the extension performs itself before
+calling the handler, and — the one piece of SEP-2549 behavior a hand-rolled extension
+method must implement itself — gating `ttlMs`/`cacheScope` to protocol version 2026-07-28+.
+"""
+
+from typing import Any
+
+import pytest
+from inline_snapshot import snapshot
+from mcp_types import INTERNAL_ERROR, INVALID_PARAMS, METHOD_NOT_FOUND, Resource
+from pydantic import BaseModel, ConfigDict
+
+from mcp.client.client import Client
+from mcp.server.context import ServerRequestContext
+from mcp.server.mcpserver import MCPServer
+from mcp.server.skills import Skills
+from mcp.shared.exceptions import MCPError
+from mcp.shared.skills import (
+    GetSkillParams,
+    GetSkillRequest,
+    GetSkillResult,
+    ListSkillsParams,
+    ListSkillsRequest,
+    ListSkillsResult,
+    ReadDirectoryParams,
+    ReadDirectoryRequest,
+    ReadDirectoryResult,
+    Skill,
+    SkillResource,
+)
+
+pytestmark = pytest.mark.anyio
+
+
+class _RawResult(BaseModel):
+    """Captures every wire field, typed, so assertions can inspect fields our own
+    `ListSkillsResult` model doesn't declare being absent (there are none) or present."""
+
+    model_config = ConfigDict(extra="allow")
+
+
+_DIGEST = "sha256:" + "a" * 64
+_SKILL_URI = "skill://git-workflow/SKILL.md"
+
+
+def _git_workflow_skill() -> Skill:
+    return Skill(
+        uri=_SKILL_URI,
+        frontmatter={"name": "git-workflow", "description": "Follow this team's Git conventions"},
+        resources=[SkillResource(uri=_SKILL_URI, digest=_DIGEST, size=10)],
+    )
+
+
+async def _list_skills(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+    return ListSkillsResult(skills=[_git_workflow_skill()])
+
+
+async def _get_skill(ctx: ServerRequestContext[Any, Any], params: GetSkillParams) -> GetSkillResult:
+    if params.uri != _SKILL_URI:
+        raise MCPError(code=INVALID_PARAMS, message="unknown skill")
+    return GetSkillResult(skill=_git_workflow_skill())
+
+
+async def _read_directory(ctx: ServerRequestContext[Any, Any], params: ReadDirectoryParams) -> ReadDirectoryResult:
+    return ReadDirectoryResult(
+        resources=[Resource(uri="skill://git-workflow/references", name="references", mime_type="inode/directory")]
+    )
+
+
+def _server(*, with_directory_read: bool = False) -> MCPServer:
+    return MCPServer(
+        "catalog",
+        extensions=[
+            Skills(
+                list_skills=_list_skills,
+                get_skill=_get_skill,
+                read_directory=_read_directory if with_directory_read else None,
+            )
+        ],
+    )
+
+
+async def test_skills_list_returns_the_handlers_skills() -> None:
+    async with Client(_server(), mode="2026-07-28") as client:
+        result = await client.session.send_request(ListSkillsRequest(), ListSkillsResult)
+    assert [s.uri for s in result.skills] == [_SKILL_URI]
+
+
+async def test_skills_list_may_return_an_empty_result() -> None:
+    """SEP-2640 Enumeration: the result MAY be empty."""
+
+    async def empty(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+        return ListSkillsResult(skills=[])
+
+    server = MCPServer("catalog", extensions=[Skills(list_skills=empty, get_skill=_get_skill)])
+    async with Client(server, mode="2026-07-28") as client:
+        result = await client.session.send_request(ListSkillsRequest(), ListSkillsResult)
+    assert result.skills == []
+
+
+async def test_skills_list_defaults_to_private_cache_scope_on_the_2026_07_28_wire() -> None:
+    """SDK-defined: an unset cache scope stays private, as on core cacheable results."""
+    async with Client(_server(), mode="2026-07-28") as client:
+        raw = await client.session.send_request(ListSkillsRequest(), _RawResult)
+    extra = raw.model_extra or {}
+    assert extra["cacheScope"] == "private"
+    assert extra["ttlMs"] == 0
+
+
+async def test_skills_list_omits_cache_fields_on_a_legacy_wire() -> None:
+    """The runner's per-version sieve only applies to core spec methods, so this extension
+    method must strip SEP-2549 fields itself for a pre-2026-07-28 connection."""
+    async with Client(_server(), mode="legacy") as client:
+        raw = await client.session.send_request(ListSkillsRequest(), _RawResult)
+    extra = raw.model_extra or {}
+    assert "cacheScope" not in extra
+    assert "ttlMs" not in extra
+
+
+async def test_skills_list_handler_setting_cache_scope_explicitly_is_not_overridden() -> None:
+    async def public_list(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+        return ListSkillsResult(skills=[_git_workflow_skill()], cache_scope="public")
+
+    server = MCPServer("catalog", extensions=[Skills(list_skills=public_list, get_skill=_get_skill)])
+    async with Client(server, mode="2026-07-28") as client:
+        raw = await client.session.send_request(ListSkillsRequest(), _RawResult)
+    extra = raw.model_extra or {}
+    assert extra["cacheScope"] == "public"
+
+
+async def test_skills_list_with_a_ttl_stays_private_when_scope_is_unset() -> None:
+    """SDK-defined: a fresh user-specific listing must not become shareable by default."""
+
+    async def private_list(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+        return ListSkillsResult(skills=[_git_workflow_skill()], ttl_ms=60_000)
+
+    server = MCPServer("catalog", extensions=[Skills(list_skills=private_list, get_skill=_get_skill)])
+    async with Client(server, mode="2026-07-28") as client:
+        raw = await client.session.send_request(ListSkillsRequest(), _RawResult)
+    extra = raw.model_extra or {}
+    assert (extra["ttlMs"], extra["cacheScope"]) == (60_000, "private")
+
+
+async def test_skills_list_rejects_a_handler_result_with_an_invalid_skill() -> None:
+    """SDK-defined: a `list_skills` handler bug (a non-conformant skill entry) is caught
+    before it reaches the client, as an Internal error — the fault is the server's, not the
+    caller's params — rather than a silently non-conformant listing."""
+
+    async def bad_list(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+        return ListSkillsResult(
+            skills=[Skill(uri=_SKILL_URI, frontmatter={"name": "git-workflow", "description": "d"}, resources=[])]
+        )
+
+    server = MCPServer("catalog", extensions=[Skills(list_skills=bad_list, get_skill=_get_skill)])
+    async with Client(server) as client:
+        with pytest.raises(MCPError) as exc_info:
+            await client.session.send_request(ListSkillsRequest(), ListSkillsResult)
+    assert exc_info.value.code == INTERNAL_ERROR
+
+
+async def test_skills_list_rejects_a_skill_mutated_after_the_result_is_built() -> None:
+    """SDK-defined: the value models validate on construction but stay mutable. A handler that
+    builds a valid result and then mutates a skill in place must not slip a non-conformant
+    listing past the server — the outbound payload is re-validated, so this is an Internal error."""
+
+    async def mutating_list(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+        result = ListSkillsResult(skills=[_git_workflow_skill()])
+        result.skills[0].frontmatter["name"] = "not the uri name"
+        return result
+
+    server = MCPServer("catalog", extensions=[Skills(list_skills=mutating_list, get_skill=_get_skill)])
+    async with Client(server) as client:
+        with pytest.raises(MCPError) as exc_info:
+            await client.session.send_request(ListSkillsRequest(), ListSkillsResult)
+    assert exc_info.value.code == INTERNAL_ERROR
+
+
+async def test_skills_get_returns_the_matching_skill() -> None:
+    async with Client(_server()) as client:
+        result = await client.session.send_request(
+            GetSkillRequest(params=GetSkillParams(uri=_SKILL_URI)), GetSkillResult
+        )
+    assert result.skill.uri == _SKILL_URI
+
+
+async def test_skills_get_defaults_to_private_cache_scope_on_the_2026_07_28_wire() -> None:
+    """SDK-defined: skills/get uses the same private cache default as skills/list."""
+    async with Client(_server(), mode="2026-07-28") as client:
+        raw = await client.session.send_request(GetSkillRequest(params=GetSkillParams(uri=_SKILL_URI)), _RawResult)
+    extra = raw.model_extra or {}
+    assert extra["cacheScope"] == "private"
+    assert extra["ttlMs"] == 0
+
+
+async def test_skills_get_omits_cache_fields_on_a_legacy_wire() -> None:
+    """As with `skills/list`, this extension method strips the SEP-2549 fields itself for a
+    pre-2026-07-28 connection, since the runner's per-version sieve only applies to core methods."""
+    async with Client(_server(), mode="legacy") as client:
+        raw = await client.session.send_request(GetSkillRequest(params=GetSkillParams(uri=_SKILL_URI)), _RawResult)
+    extra = raw.model_extra or {}
+    assert "cacheScope" not in extra
+    assert "ttlMs" not in extra
+
+
+async def test_skills_get_answers_for_a_skill_absent_from_the_listing() -> None:
+    """SEP-2640 Retrieval: a server MUST answer for every skill it serves, whether or not
+    that skill appears in `skills/list`."""
+
+    async def list_without_it(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+        return ListSkillsResult(skills=[])
+
+    server = MCPServer("catalog", extensions=[Skills(list_skills=list_without_it, get_skill=_get_skill)])
+    async with Client(server) as client:
+        listing = await client.session.send_request(ListSkillsRequest(), ListSkillsResult)
+        result = await client.session.send_request(
+            GetSkillRequest(params=GetSkillParams(uri=_SKILL_URI)), GetSkillResult
+        )
+    assert listing.skills == []
+    assert result.skill.uri == _SKILL_URI
+
+
+async def test_skills_get_rejects_an_unknown_uri_with_invalid_params() -> None:
+    """SEP-2640 Retrieval: an unknown skill URI MUST be rejected with -32602 (Invalid params)."""
+    async with Client(_server()) as client:
+        with pytest.raises(MCPError) as exc_info:
+            await client.session.send_request(
+                GetSkillRequest(params=GetSkillParams(uri="skill://other/SKILL.md")), GetSkillResult
+            )
+    assert exc_info.value.code == INVALID_PARAMS
+
+
+async def test_skills_get_rejects_a_uri_that_does_not_end_in_skill_md() -> None:
+    async with Client(_server()) as client:
+        with pytest.raises(MCPError) as exc_info:
+            await client.session.send_request(
+                GetSkillRequest(params=GetSkillParams(uri="skill://git-workflow/README.md")), GetSkillResult
+            )
+    assert exc_info.value.code == INVALID_PARAMS
+
+
+async def test_skills_get_rejects_a_handler_that_returns_a_mismatched_uri() -> None:
+    """SDK-defined: a `get_skill` handler bug (returning the wrong skill) is caught before
+    it reaches the client, as an Internal error rather than a silently wrong answer."""
+
+    async def wrong_skill(ctx: ServerRequestContext[Any, Any], params: GetSkillParams) -> GetSkillResult:
+        return GetSkillResult(skill=_git_workflow_skill())
+
+    server = MCPServer("catalog", extensions=[Skills(list_skills=_list_skills, get_skill=wrong_skill)])
+    async with Client(server) as client:
+        with pytest.raises(MCPError) as exc_info:
+            await client.session.send_request(
+                GetSkillRequest(params=GetSkillParams(uri="skill://other/SKILL.md")), GetSkillResult
+            )
+    assert exc_info.value.code == INTERNAL_ERROR
+
+
+async def test_skills_get_rejects_a_matching_but_non_conformant_skill() -> None:
+    """SDK-defined: a `get_skill` handler bug (a non-conformant skill body, distinct from a
+    URI mismatch) is caught the same way, as an Internal error."""
+
+    async def bad_skill(ctx: ServerRequestContext[Any, Any], params: GetSkillParams) -> GetSkillResult:
+        return GetSkillResult(
+            skill=Skill(uri=params.uri, frontmatter={"name": "git-workflow", "description": "d"}, resources=[])
+        )
+
+    server = MCPServer("catalog", extensions=[Skills(list_skills=_list_skills, get_skill=bad_skill)])
+    async with Client(server) as client:
+        with pytest.raises(MCPError) as exc_info:
+            await client.session.send_request(GetSkillRequest(params=GetSkillParams(uri=_SKILL_URI)), GetSkillResult)
+    assert exc_info.value.code == INTERNAL_ERROR
+
+
+async def test_skills_get_rejects_a_skill_mutated_after_the_result_is_built() -> None:
+    """SDK-defined: as on `skills/list`, a handler that mutates the skill in place after building
+    the result can't ship a non-conformant body — the re-validated outbound payload fails it as an
+    Internal error."""
+
+    async def mutating_get(ctx: ServerRequestContext[Any, Any], params: GetSkillParams) -> GetSkillResult:
+        result = GetSkillResult(skill=_git_workflow_skill())
+        assert isinstance(result.skill.resources, list)
+        result.skill.resources.clear()
+        return result
+
+    server = MCPServer("catalog", extensions=[Skills(list_skills=_list_skills, get_skill=mutating_get)])
+    async with Client(server) as client:
+        with pytest.raises(MCPError) as exc_info:
+            await client.session.send_request(GetSkillRequest(params=GetSkillParams(uri=_SKILL_URI)), GetSkillResult)
+    assert exc_info.value.code == INTERNAL_ERROR
+
+
+async def test_missing_uri_param_is_rejected_before_the_handler_runs() -> None:
+    """SDK-defined: `uri` is a required field on `GetSkillParams`, so an omitted param is
+    rejected by params validation - the handler never sees it."""
+    async with Client(_server()) as client:
+        with pytest.raises(MCPError) as exc_info:
+            await client.session.send_request(GetSkillRequest.model_construct(params=None), GetSkillResult)
+    assert exc_info.value.code == INVALID_PARAMS
+
+
+async def test_directory_read_is_not_advertised_without_a_handler() -> None:
+    async with Client(_server(with_directory_read=False)) as client:
+        assert client.server_capabilities.extensions == {"io.modelcontextprotocol/skills": {}}
+
+
+async def test_directory_read_is_advertised_when_a_handler_is_supplied() -> None:
+    async with Client(_server(with_directory_read=True)) as client:
+        assert client.server_capabilities.extensions == snapshot(
+            {"io.modelcontextprotocol/skills": {"directoryRead": True}}
+        )
+
+
+async def test_directory_read_returns_the_handlers_children() -> None:
+    async with Client(_server(with_directory_read=True)) as client:
+        result = await client.session.send_request(
+            ReadDirectoryRequest(params=ReadDirectoryParams(uri="skill://git-workflow")), ReadDirectoryResult
+        )
+    assert [r.uri for r in result.resources] == ["skill://git-workflow/references"]
+
+
+async def test_directory_read_is_not_registered_without_a_handler() -> None:
+    """SDK-defined: omitting `read_directory` doesn't just skip the capability ad - the
+    method itself isn't registered, so calling it anyway is Method not found."""
+    async with Client(_server(with_directory_read=False)) as client:
+        with pytest.raises(MCPError) as exc_info:
+            await client.session.send_request(
+                ReadDirectoryRequest(params=ReadDirectoryParams(uri="skill://git-workflow")), ReadDirectoryResult
+            )
+    assert exc_info.value.code == METHOD_NOT_FOUND
+
+
+async def test_directory_read_rejects_a_trailing_slash_uri() -> None:
+    """SEP-2640 Directory resources: directory URIs are written without a trailing slash."""
+    async with Client(_server(with_directory_read=True)) as client:
+        with pytest.raises(MCPError) as exc_info:
+            await client.session.send_request(
+                ReadDirectoryRequest(params=ReadDirectoryParams(uri="skill://git-workflow/")), ReadDirectoryResult
+            )
+    assert exc_info.value.code == INVALID_PARAMS
+
+
+async def test_directory_read_rejects_a_handler_result_with_a_grandchild() -> None:
+    """SDK-defined: a `read_directory` handler bug (a non-direct child) is a server fault,
+    surfaced as an Internal error, not the caller's Invalid params."""
+
+    async def bad_directory(ctx: ServerRequestContext[Any, Any], params: ReadDirectoryParams) -> ReadDirectoryResult:
+        return ReadDirectoryResult(resources=[Resource(uri="skill://git-workflow/a/b/c.md", name="c.md")])
+
+    server = MCPServer(
+        "catalog", extensions=[Skills(list_skills=_list_skills, get_skill=_get_skill, read_directory=bad_directory)]
+    )
+    async with Client(server) as client:
+        with pytest.raises(MCPError) as exc_info:
+            await client.session.send_request(
+                ReadDirectoryRequest(params=ReadDirectoryParams(uri="skill://git-workflow")), ReadDirectoryResult
+            )
+    assert exc_info.value.code == INTERNAL_ERROR
diff --git a/tests/shared/test_skills.py b/tests/shared/test_skills.py
new file mode 100644
index 0000000000..64f7d6214b
--- /dev/null
+++ b/tests/shared/test_skills.py
@@ -0,0 +1,356 @@
+"""SEP-2640 conformance checks in `mcp.shared.skills`: types and validation.
+
+Server- and client-side end-to-end wiring live in `tests/server/test_skills.py` and
+`tests/client/extensions/test_skills.py`; this file pins the pure functions both depend on.
+"""
+
+from typing import Any
+
+import pytest
+from mcp_types import Resource
+from pydantic import ValidationError
+
+from mcp.shared.skills import (
+    ListSkillsParams,
+    ListSkillsResult,
+    ReadDirectoryParams,
+    ReadDirectoryResult,
+    Skill,
+    SkillResource,
+    parse_directory_uri,
+    skill_name_from_uri,
+    validate_directory_result,
+)
+
+_DIGEST = "sha256:" + "a" * 64
+
+
+def _resource(uri: str, *, size: int = 4) -> SkillResource:
+    return SkillResource(uri=uri, digest=_DIGEST, size=size)
+
+
+def _skill(name: str = "git-workflow", *, extra_resources: list[SkillResource] | None = None) -> Skill:
+    uri = f"skill://{name}/SKILL.md"
+    return Skill(
+        uri=uri,
+        frontmatter={"name": name, "description": "d"},
+        resources=[_resource(uri), *(extra_resources or [])],
+    )
+
+
+@pytest.mark.parametrize(
+    ("uri", "name"),
+    [
+        ("skill://git-workflow/SKILL.md", "git-workflow"),
+        ("skill://acme/billing/refunds/SKILL.md", "refunds"),
+        ("https://example.com/skills/pdf/SKILL.md", "pdf"),
+    ],
+)
+def test_skill_name_from_uri_reads_the_final_path_segment(uri: str, name: str) -> None:
+    """SEP-2640 Resource Mapping: the final `<skill-path>` segment is the skill name."""
+    assert skill_name_from_uri(uri) == name
+
+
+@pytest.mark.parametrize(
+    "uri",
+    [
+        "skill://git-workflow/README.md",  # doesn't end in /SKILL.md
+        "not-a-uri",  # no scheme
+        "skill://git-workflow/SKILL.md?x=1",  # query component
+    ],
+)
+def test_skill_name_from_uri_rejects_malformed_uris(uri: str) -> None:
+    with pytest.raises(ValueError, match="SKILL.md|absolute resource URI"):
+        skill_name_from_uri(uri)
+
+
+def test_skill_name_from_uri_rejects_a_uri_with_no_recoverable_name() -> None:
+    with pytest.raises(ValueError, match="has no skill name"):
+        skill_name_from_uri("skill:///SKILL.md")
+
+
+def test_skill_with_a_static_resources_array_round_trips_through_json() -> None:
+    """SEP-2640 Resources: `resources` MUST serialize as a JSON array of `{uri, digest, size}`
+    triples - proves the union type doesn't collapse or mistag on the wire."""
+    original = _skill()
+    dumped = original.model_dump(mode="json", by_alias=True)
+    assert isinstance(dumped["resources"], list)
+    restored = Skill.model_validate(dumped)
+    assert restored == original
+
+
+def test_skill_with_dynamic_resources_round_trips_through_json_as_the_literal_string() -> None:
+    """SEP-2640 Resources: a dynamically generated skill MUST carry the literal string
+    `"dynamic"` in place of an array - not `null`, not `{}`, not omitted."""
+    original = Skill(
+        uri="skill://generated/SKILL.md", frontmatter={"name": "generated", "description": "d"}, resources="dynamic"
+    )
+    dumped = original.model_dump(mode="json", by_alias=True)
+    assert dumped["resources"] == "dynamic"
+    restored = Skill.model_validate(dumped)
+    assert restored == original
+    assert restored.resources == "dynamic"
+
+
+def test_skill_accepts_a_conformant_manifest() -> None:
+    skill = _skill()
+    assert isinstance(skill.resources, list)
+
+
+def test_skill_rejects_a_non_string_frontmatter_name() -> None:
+    with pytest.raises(ValidationError, match="frontmatter name"):
+        Skill(
+            uri="skill://git-workflow/SKILL.md",
+            frontmatter={"name": 1, "description": "d"},
+            resources=[_resource("skill://git-workflow/SKILL.md")],
+        )
+
+
+@pytest.mark.parametrize(
+    "name",
+    [
+        "foo--bar",  # consecutive hyphens
+        "-foo",  # leading hyphen
+        "foo-",  # trailing hyphen
+        "UPPER",  # uppercase not allowed
+        "with_underscore",  # underscore not allowed
+        "a" * 65,  # exceeds the 64-char limit
+    ],
+)
+def test_skill_rejects_names_violating_the_agent_skills_grammar(name: str) -> None:
+    """SEP-2640 defers naming to the Agent Skills spec: 1-64 chars, lowercase alphanumeric and
+    hyphens, no leading/trailing/consecutive hyphens. A URI whose final path segment carries the
+    bad name (so `frontmatter.name` can match it) still fails the name-grammar check first."""
+    uri = f"skill://acme/{name}/SKILL.md"
+    with pytest.raises(ValidationError, match="frontmatter name"):
+        Skill(
+            uri=uri,
+            frontmatter={"name": name, "description": "d"},
+            resources=[SkillResource(uri=uri, digest=_DIGEST, size=4)],
+        )
+
+
+def test_skill_rejects_an_invalid_resource_uri() -> None:
+    """A resource URI with a query component fails the same shape check as a skill URI."""
+    with pytest.raises(ValidationError, match="is invalid"):
+        _skill(extra_resources=[_resource("skill://git-workflow/x.md?y=1")])
+
+
+def test_skill_rejects_a_resource_with_the_same_authority_but_a_sibling_path() -> None:
+    """Same scheme+authority as the skill (so the URI passes the authority check) but a path
+    outside the skill's own directory, per SEP-2640 Resources ('a file within the skill's
+    directory')."""
+    root = "skill://acme/billing/refunds/SKILL.md"
+    with pytest.raises(ValidationError, match="outside the skill root"):
+        Skill(
+            uri=root,
+            frontmatter={"name": "refunds", "description": "d"},
+            resources=[_resource(root), _resource("skill://acme/billing/other/x.md")],
+        )
+
+
+def test_skill_rejects_a_traversal_segment_in_a_resource_uri() -> None:
+    with pytest.raises(ValidationError, match="traversal segment"):
+        _skill(extra_resources=[_resource("skill://git-workflow/../evil.md")])
+
+
+def test_skill_rejects_a_resource_uri_with_a_trailing_slash() -> None:
+    """A manifest entry names a file, not a directory: a trailing slash is rejected."""
+    with pytest.raises(ValidationError, match="names a directory"):
+        _skill(extra_resources=[_resource("skill://git-workflow/references/")])
+
+
+def test_skill_resource_rejects_a_negative_size() -> None:
+    with pytest.raises(ValidationError, match="greater than or equal to 0"):
+        SkillResource(uri="skill://git-workflow/SKILL.md", digest=_DIGEST, size=-1)
+
+
+def test_skill_rejects_frontmatter_name_uri_mismatch() -> None:
+    """SEP-2640 Resource Mapping: `frontmatter.name` MUST equal the URI-derived name."""
+    with pytest.raises(ValidationError, match="does not match URI name"):
+        Skill(
+            uri="skill://git-workflow/SKILL.md",
+            frontmatter={"name": "other-name", "description": "d"},
+            resources=[_resource("skill://git-workflow/SKILL.md")],
+        )
+
+
+@pytest.mark.parametrize("description", ["", "x" * 1025])
+def test_skill_rejects_out_of_range_description_length(description: str) -> None:
+    with pytest.raises(ValidationError, match="description"):
+        Skill(
+            uri="skill://git-workflow/SKILL.md",
+            frontmatter={"name": "git-workflow", "description": description},
+            resources=[_resource("skill://git-workflow/SKILL.md")],
+        )
+
+
+def test_skill_rejects_a_resource_outside_the_skill_root() -> None:
+    """SEP-2640 Resources: every entry MUST name a file within the skill's own directory."""
+    with pytest.raises(ValidationError, match="outside the skill root"):
+        _skill(extra_resources=[_resource("skill://other-skill/file.md")])
+
+
+def test_skill_rejects_missing_skill_md_entry() -> None:
+    """SEP-2640 Resources: `resources` MUST include an entry for the skill's own `SKILL.md`."""
+    with pytest.raises(ValidationError, match="does not include its own SKILL.md"):
+        Skill(
+            uri="skill://git-workflow/SKILL.md",
+            frontmatter={"name": "git-workflow", "description": "d"},
+            resources=[_resource("skill://git-workflow/references/GUIDE.md")],
+        )
+
+
+def test_skill_rejects_duplicate_resource_uris() -> None:
+    root = "skill://git-workflow/SKILL.md"
+    with pytest.raises(ValidationError, match="more than once"):
+        Skill(
+            uri=root,
+            frontmatter={"name": "git-workflow", "description": "d"},
+            resources=[_resource(root), _resource(root)],
+        )
+
+
+@pytest.mark.parametrize(
+    "digest",
+    [
+        "not-a-digest",  # no sha256: prefix at all
+        "sha256:" + "A" * 64,  # uppercase hex - spec requires lowercase
+        "sha256:" + "a" * 63,  # one hex char short
+        "sha256:" + "a" * 65,  # one hex char long
+        "sha1:" + "a" * 40,  # wrong algorithm prefix
+        "sha256:" + "g" * 64,  # non-hex characters
+    ],
+)
+def test_skill_resource_rejects_malformed_digest_formats(digest: str) -> None:
+    """SEP-2640 Integrity and verification: `sha256:{hex}` where `{hex}` is exactly 64
+    lowercase hexadecimal characters - each of these near-misses must still be rejected."""
+    with pytest.raises(ValidationError, match="digest"):
+        SkillResource(uri="skill://git-workflow/SKILL.md", digest=digest, size=1)
+
+
+def test_skill_accepts_exactly_512_resources() -> None:
+    """SEP-2640 Limits: a host MUST support skills up to and including 512 entries
+    (`SKILL.md` counted), so a 512-entry manifest validates."""
+    root = "skill://git-workflow/SKILL.md"
+    resources = [_resource(root)] + [_resource(f"skill://git-workflow/f{i}.md") for i in range(511)]
+    skill = Skill(uri=root, frontmatter={"name": "git-workflow", "description": "d"}, resources=resources)
+    assert isinstance(skill.resources, list)
+    assert len(skill.resources) == 512
+
+
+def test_skill_accepts_more_than_512_resources() -> None:
+    """SEP-2640 Limits: 512 is a SHOULD NOT threshold, not a hard cap — a host MAY support
+    larger skills, so an over-count manifest is not rejected."""
+    root = "skill://git-workflow/SKILL.md"
+    resources = [_resource(root)] + [_resource(f"skill://git-workflow/f{i}.md") for i in range(512)]
+    skill = Skill(uri=root, frontmatter={"name": "git-workflow", "description": "d"}, resources=resources)
+    assert isinstance(skill.resources, list)
+    assert len(skill.resources) == 513
+
+
+def test_skill_accepts_total_size_over_16mib() -> None:
+    """SEP-2640 Limits: 16 MiB total is a SHOULD NOT threshold, not a hard cap — an over-size
+    manifest is not rejected."""
+    root = "skill://git-workflow/SKILL.md"
+    skill = Skill(
+        uri=root,
+        frontmatter={"name": "git-workflow", "description": "d"},
+        resources=[_resource(root, size=16 * 1024 * 1024 + 1)],
+    )
+    assert isinstance(skill.resources, list)
+    assert skill.resources[0].size == 16 * 1024 * 1024 + 1
+
+
+def test_skill_accepts_dynamic_resources_without_further_checks() -> None:
+    """SEP-2640 Resources: `"dynamic"` offers no manifest to check against limits."""
+    skill = Skill(
+        uri="skill://generated/SKILL.md", frontmatter={"name": "generated", "description": "d"}, resources="dynamic"
+    )
+    assert skill.resources == "dynamic"
+
+
+def test_list_result_rejects_duplicate_skill_uris_across_entries() -> None:
+    with pytest.raises(ValidationError, match="more than once"):
+        ListSkillsResult(skills=[_skill(), _skill()])
+
+
+def test_list_result_accepts_an_empty_listing() -> None:
+    """SEP-2640 Enumeration: `skills/list` MAY return an empty result."""
+    assert ListSkillsResult(skills=[]).skills == []
+
+
+@pytest.mark.parametrize(
+    ("params_type", "payload"),
+    [
+        (ListSkillsParams, {"_meta": {"progressToken": "t"}}),
+        (ReadDirectoryParams, {"uri": "skill://pdf/templates", "_meta": {"progressToken": "t"}}),
+    ],
+)
+def test_request_meta_is_camelcase_on_the_wire_but_snakecase_to_a_handler(
+    params_type: type[ListSkillsParams] | type[ReadDirectoryParams], payload: dict[str, Any]
+) -> None:
+    """A caller's `_meta.progressToken` rides the wire camelCase (its JSON alias) yet is read back
+    snake_case as `progress_token` once deserialized - two spellings, one value. This is what lets
+    `list_skills`/`read_directory` forward a caller's `_meta` to every page while a server handler
+    still finds `progress_token` in `params.meta`; both spellings working is the point."""
+    params = params_type.model_validate(payload)
+    wire = params.model_dump(by_alias=True, mode="json", exclude_none=True)
+    assert wire["_meta"] == {"progressToken": "t"}  # camelCase over the wire
+    assert params.meta is not None and params.meta.get("progress_token") == "t"  # snake_case to a handler
+
+
+@pytest.mark.parametrize("uri", ["skill://pdf/templates/", "not-a-uri"])
+def test_parse_directory_uri_rejects_malformed_uris(uri: str) -> None:
+    with pytest.raises(ValueError, match="directory URI"):
+        parse_directory_uri(uri)
+
+
+def test_validate_directory_result_rejects_a_child_with_a_query_component() -> None:
+    result = ReadDirectoryResult(resources=[Resource(uri="skill://pdf/templates/x.md?y=1", name="x.md")])
+    with pytest.raises(ValueError, match="invalid URI"):
+        validate_directory_result("skill://pdf/templates", result)
+
+
+def test_validate_directory_result_rejects_a_duplicate_child_uri() -> None:
+    result = ReadDirectoryResult(
+        resources=[
+            Resource(uri="skill://pdf/templates/a.md", name="a"),
+            Resource(uri="skill://pdf/templates/a.md", name="b"),
+        ]
+    )
+    with pytest.raises(ValueError, match="duplicate child"):
+        validate_directory_result("skill://pdf/templates", result)
+
+
+def test_validate_directory_result_accepts_direct_children() -> None:
+    result = ReadDirectoryResult(
+        resources=[
+            Resource(uri="skill://pdf/templates/invoice.md", name="invoice.md", mime_type="text/markdown"),
+            Resource(uri="skill://pdf/templates/regional", name="regional", mime_type="inode/directory"),
+        ]
+    )
+    validate_directory_result("skill://pdf/templates", result)
+
+
+def test_validate_directory_result_rejects_a_grandchild() -> None:
+    """SEP-2640 Directory Listing: the listing is not recursive."""
+    result = ReadDirectoryResult(
+        resources=[Resource(uri="skill://pdf/templates/regional/eu.md", name="eu.md", mime_type="text/markdown")]
+    )
+    with pytest.raises(ValueError, match="direct child"):
+        validate_directory_result("skill://pdf/templates", result)
+
+
+@pytest.mark.parametrize("child_uri", ["skill://pdf/templates/.", "skill://pdf/templates/.."])
+def test_validate_directory_result_rejects_a_dot_segment_child(child_uri: str) -> None:
+    """A `.`/`..` child is a traversal segment, not a real direct child of the directory."""
+    result = ReadDirectoryResult(resources=[Resource(uri=child_uri, name="x")])
+    with pytest.raises(ValueError, match="direct child"):
+        validate_directory_result("skill://pdf/templates", result)
+
+
+def test_validate_directory_result_rejects_a_uri_outside_the_directory() -> None:
+    result = ReadDirectoryResult(resources=[Resource(uri="skill://other/file.md", name="file.md")])
+    with pytest.raises(ValueError, match="not a child"):
+        validate_directory_result("skill://pdf/templates", result)
```
</details>

---

## modelcontextprotocol__python-sdk-3600

**12/25** · [PR](https://github.com/modelcontextprotocol/python-sdk/pull/3600) · [issue #3332](https://github.com/modelcontextprotocol/python-sdk/issues/3332) · 12 FAIL_TO_PASS tests

### Issue

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

### Files changed by the gold patch

- `docs/client/transports.md` (+19 / -2)
- `docs/migration.md` (+1 / -1)
- `docs_src/client_transports/tutorial005.py` (+12 / -0)
- `pyproject.toml` (+1 / -1)
- `src/mcp/client/session_group.py` (+5 / -1)
- `src/mcp/client/streamable_http.py` (+50 / -15)
- `src/mcp/shared/_httpx_utils.py` (+6 / -2)
- `uv.lock` (+1 / -1)

### Tests that must pass (names, deduplicated)

- `test_client_session_group_establish_session_parameterized`
- `test_configured_sse_limit_accepts_a_large_get_notification`
- `test_configured_sse_limit_accepts_a_tool_result_larger_than_one_mebibyte`
- `test_configured_sse_limit_does_not_replay_an_oversized_reconnected_event`
- `test_configured_sse_limit_fails_an_oversized_resumption_event`
- `test_default_sse_limit_fails_one_large_tool_call_and_keeps_the_session_usable`
- `test_non_sse_reconnection_response_retries_before_failing_the_request`
- `test_none_disables_the_sse_event_limit`
- `test_oversized_get_event_reconnects_and_delivers_later_messages`
- `test_streamable_http_configuration_lives_on_the_httpx_client`
- `test_streamable_http_rejects_nonpositive_sse_event_limits`

<details><summary>Gold patch</summary>

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
</details>

<details><summary>Test patch</summary>

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
 
 
-class _ParkedSSEStream(httpx2.AsyncByteStream):
-    """An SSE response body that emits one comment line, then parks until closed.
-
-    `opened` fires once the transport is iterating the body (the POST is truly in
-    flight); `closed` fires when httpx2 tears the body down — the observable proof
-    that an abort, not a response, ended the stream.
-    """
-
-    def __init__(self) -> None:
-        self.opened = anyio.Event()
-        self.closed = anyio.Event()
-        self._release = anyio.Event()
-
-    async def __aiter__(self) -> AsyncIterator[bytes]:
-        self.opened.set()
-        yield b": parked\n\n"
-        await self._release.wait()
-
-    async def aclose(self) -> None:
-        self.closed.set()
-        self._release.set()
-
-
 def _sse_or_ack_handler(
     parked: _ParkedSSEStream, posted: list[dict[str, Any]], frame_posted: anyio.Event
 ) -> Callable[[httpx2.Request], httpx2.Response]:
diff --git a/tests/docs_src/test_client_transports.py b/tests/docs_src/test_client_transports.py
index 914067c7a0..6cd9c4f8dd 100644
--- a/tests/docs_src/test_client_transports.py
+++ b/tests/docs_src/test_client_transports.py
@@ -37,8 +37,13 @@ async def test_constructing_a_client_does_not_connect_it() -> None:
 
 
 async def test_streamable_http_configuration_lives_on_the_httpx_client() -> None:
-    """tutorial003: `streamable_http_client` takes `http_client=`; there is no `headers=` or any other HTTP knob."""
-    assert list(inspect.signature(streamable_http_client).parameters) == ["url", "http_client", "terminate_on_close"]
+    """tutorial003: HTTP settings use `http_client=`, while SSE event size is a transport setting."""
+    assert list(inspect.signature(streamable_http_client).parameters) == [
+        "url",
+        "http_client",
+        "terminate_on_close",
+        "max_sse_event_size",
+    ]
 
 
 async def test_stdio_parameters_go_straight_to_client() -> None:
```
</details>

---

## modelcontextprotocol__python-sdk-3620

**13/25** · [PR](https://github.com/modelcontextprotocol/python-sdk/pull/3620) · [issue #3484](https://github.com/modelcontextprotocol/python-sdk/issues/3484) · 14 FAIL_TO_PASS tests · ⚠️ **tests import a name introduced by the fix**

### Issue

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

### Files changed by the gold patch

- `docs/advanced/header-parameters.md` (+47 / -0)
- `docs/advanced/index.md` (+2 / -0)
- `docs/troubleshooting.md` (+9 / -0)
- `docs_src/header_parameters/__init__.py` (+0 / -0)
- `docs_src/header_parameters/tutorial001.py` (+16 / -0)
- `docs_src/header_parameters/tutorial002.py` (+36 / -0)
- `mkdocs.yml` (+1 / -0)
- `src/mcp/server/mcpserver/tools/base.py` (+3 / -0)

### Tests that must pass (names, deduplicated)

- `test_a_2026_http_client_sends_the_marked_argument_as_a_header_as_well`
- `test_a_call_whose_header_and_body_disagree_is_rejected`
- `test_a_connection_that_is_not_http_ignores_the_annotation`
- `test_a_legacy_http_connection_ignores_the_annotation`
- `test_a_plain_optional_argument_is_refused_and_the_spelled_out_schema_registers`
- `test_an_invalid_x_mcp_header_annotation_raises_at_import_time`
- `test_any_other_type_is_refused_when_the_tool_is_registered`
- `test_int_and_bool_arguments_can_be_marked`
- `test_the_low_level_server_serves_an_invalid_annotation_and_a_2026_client_leaves_the_tool_out`
- `test_tool_with_an_invalid_x_mcp_header_annotation_is_rejected_at_registration`

<details><summary>Gold patch</summary>

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
</details>

<details><summary>Test patch</summary>

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
</details>

---

## modelcontextprotocol__python-sdk-3622

**14/25** · [PR](https://github.com/modelcontextprotocol/python-sdk/pull/3622) · [issue #3598](https://github.com/modelcontextprotocol/python-sdk/issues/3598) · 1 FAIL_TO_PASS tests

### Issue

Server TokenHandler rejects the jwt-bearer (ID-JAG) grant from public CIMD clients, which the enterprise-managed authorization extension permits

### Problem

With `identity_assertion_enabled=True`, `TokenHandler` rejects every `urn:ietf:params:oauth:grant-type:jwt-bearer` request from a client that has no stored `client_secret`:

```python
# mcp/server/auth/handlers/token.py
if not client_info.client_secret:
    return self.response(
        TokenErrorResponse(
            error="unauthorized_client",
            error_description="The JWT bearer grant requires a confidential client",
        )
    )
```

A client identified by a Client ID Metadata Document (CIMD) cannot hold a shared secret (CIMD forbids `client_secret_*`), so the only methods open to it are `none` and `private_key_jwt`. Since `ClientAuthenticator` does not implement `private_key_jwt`, a CIMD client can never complete the ID-JAG exchange against an SDK-based authorization server.

This blocks real clients. At least one widely deployed MCP client documents its enterprise-managed authorization token request as carrying only `grant_type`, `assertion`, `client_id` (a CIMD URL), `scope` and `resource`, with no client secret and no client assertion.

### What the extension spec says

`modelcontextprotocol/ext-auth`, `specification/stable/enterprise-managed-authorization.mdx`, section 5 (Access Token Request):

> The MCP Client authenticates with its credentials as registered with the Resource Authorization Server.
>
> If the MCP Client is not pre-registered with the Resource Authorization Server, then it can use its Client ID Metadata Document as its client ID, and optionally authenticate using private_key_jwt.

Its example request has no client authentication at all:

```
grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer
&assertion=eyJhbGciOiJIUzI1NiIsI...
&client_id=https://client.example.com/client.json
```

So for a CIMD client, client authentication at this step is optional. The current check is stricter than the spec and turns away the case the spec calls out by name.

### Expected

A CIMD client with `token_endpoint_auth_method="none"` can exchange a valid ID-JAG issued for its `client_id`. Pre-registered clients keep today's behavior (they must authenticate as registered).

### Related

- #2260 / #2261 (`none` missing from `token_endpoint_auth_methods_supported`)
- #1842 / #1846 (`none` handling in `ClientAuthenticator`)



AI disclosure: I used an AI coding assistant to draft this issue; I have reviewed it and can answer for it.

### Files changed by the gold patch

- `docs/client/identity-assertion.md` (+2 / -1)
- `examples/snippets/clients/identity_assertion_client.py` (+1 / -1)
- `examples/snippets/servers/identity_assertion_server.py` (+1 / -1)
- `src/mcp/client/auth/extensions/identity_assertion.py` (+2 / -2)
- `src/mcp/server/auth/handlers/register.py` (+3 / -3)
- `src/mcp/server/auth/handlers/token.py` (+4 / -4)

### Tests that must pass (names, deduplicated)

- `test_empty_client_secret_is_rejected`

<details><summary>Gold patch</summary>

```diff
diff --git a/docs/client/identity-assertion.md b/docs/client/identity-assertion.md
index 9e18bcbfe5..fe891143dc 100644
--- a/docs/client/identity-assertion.md
+++ b/docs/client/identity-assertion.md
@@ -59,7 +59,7 @@ The extension does not demand this; it is a deliberately stricter choice. This c
 
 ### A confidential client
 
-`client_secret` is required; the constructor raises `ValueError` without one. The IETF profile underneath [SEP-990](https://github.com/modelcontextprotocol/modelcontextprotocol/issues/990) reserves this grant for confidential clients, SEP-990 requires the client to authenticate, and this SDK enforces both by insisting on a shared secret. `token_endpoint_auth_method` picks where it travels: `client_secret_post` (the default, in the form body) or `client_secret_basic` (an HTTP Basic header). The profile also permits `private_key_jwt`; this provider does not support it.
+`client_secret` is required; the constructor raises `ValueError` without one. The IETF profile underneath [SEP-990](https://github.com/modelcontextprotocol/modelcontextprotocol/issues/990) recommends this grant for confidential clients only, and [RFC 7521](https://datatracker.ietf.org/doc/html/rfc7521) leaves that policy to the authorization server. This SDK takes the conservative reading on both sides: the built-in authorization server refuses a client that has no shared secret, and this provider insists on one. `token_endpoint_auth_method` picks where it travels: `client_secret_post` (the default, in the form body) or `client_secret_basic` (an HTTP Basic header). The profile also permits `private_key_jwt`; this provider does not support it.
 
 !!! tip
     Read `client_secret` from the environment or a secret manager, never from source control.
@@ -86,6 +86,7 @@ The SDK can also *be* the authorization server: `create_auth_routes` returns the
 
 * `identity_assertion_enabled=True` gates everything. Off, which is the default, `/token` answers this grant with `unsupported_grant_type` even if you implemented the hook, and the metadata does not mention it. On, the metadata gains the `jwt-bearer` grant type and lists `urn:ietf:params:oauth:grant-profile:id-jag` in `authorization_grant_profiles_supported`, the field the extension uses to advertise support. (This SDK's client never reads it: it is provisioned for one issuer and simply asks.)
 * **`exchange_identity_assertion`** is the hook. Before it runs, the SDK has authenticated the client, refused public clients, and refused clients whose registration does not list the grant. You get an `IdentityAssertionParams` (the raw `assertion`, the requested `scopes` and `resource`) and return a plain `OAuthToken`.
+* Refusing public clients is SDK policy, not a spec requirement. The built-in server authenticates clients by shared secret only: it has no `private_key_jwt` support and doesn't resolve Client ID Metadata Documents yet ([#1801](https://github.com/modelcontextprotocol/python-sdk/issues/1801)), so a client identified by one can't use this grant here. A deployment that wants a different policy can swap the `/token` route that `create_auth_routes` returns for its own.
 * Dynamic client registration refuses this grant unconditionally, so `get_client` here serves a hand-provisioned client. An ID-JAG client cannot register itself into existence.
 * Half the class is refusals. `OAuthAuthorizationServerProvider` is the *whole* authorization server, so it also asks for the authorization-code flow; a server that signs users in as well implements those for real, and this one has exactly one door.
 
diff --git a/examples/snippets/clients/identity_assertion_client.py b/examples/snippets/clients/identity_assertion_client.py
index a1291ee4d1..39635a3fb9 100644
--- a/examples/snippets/clients/identity_assertion_client.py
+++ b/examples/snippets/clients/identity_assertion_client.py
@@ -8,7 +8,7 @@
 Obtaining the ID-JAG (logging into the IdP and the leg-1 exchange against it) is deployment-specific
 and out of scope for the SDK; supply it through the `assertion_provider` callback. The callback
 receives the authorization server's issuer (the ID-JAG `aud`) and the MCP server's resource
-identifier (the ID-JAG `resource` claim). SEP-990 requires a confidential client, so a client secret
+identifier (the ID-JAG `resource` claim). The provider requires a confidential client, so a client secret
 is mandatory, and `issuer` is the authorization server the credentials are provisioned for - the
 provider fetches metadata from that issuer's well-known and never asks the resource server which AS
 to use.
diff --git a/examples/snippets/servers/identity_assertion_server.py b/examples/snippets/servers/identity_assertion_server.py
index 9406111f8b..410d96a5ff 100644
--- a/examples/snippets/servers/identity_assertion_server.py
+++ b/examples/snippets/servers/identity_assertion_server.py
@@ -50,7 +50,7 @@ class IdentityAssertionProvider(OAuthAuthorizationServerProvider[AuthorizationCo
 
     def __init__(self) -> None:
         self.access_tokens: dict[str, AccessToken] = {}
-        # SEP-990 clients are pre-registered out of band (DCR refuses the grant) and must be
+        # ID-JAG clients here are pre-registered out of band (DCR refuses the grant) and must be
         # confidential. `get_client` must return them, or the token endpoint 401s before the
         # exchange runs. Real deployments load these from their own store.
         self.clients: dict[str, OAuthClientInformationFull] = {
diff --git a/src/mcp/client/auth/extensions/identity_assertion.py b/src/mcp/client/auth/extensions/identity_assertion.py
index 35e48c03fa..5e715cb83a 100644
--- a/src/mcp/client/auth/extensions/identity_assertion.py
+++ b/src/mcp/client/auth/extensions/identity_assertion.py
@@ -104,7 +104,7 @@ def __init__(
             server_url: The MCP server URL.
             storage: Token storage implementation.
             client_id: The OAuth client ID registered with the MCP authorization server.
-            client_secret: The client secret. SEP-990 section 5.1 requires a confidential client.
+            client_secret: The client secret. This provider supports confidential clients only.
             issuer: The issuer identifier of the MCP authorization server this client is provisioned
                 for. Authorization-server metadata is fetched from this issuer's well-known and the
                 ID-JAG and secret are sent only to its token endpoint.
@@ -115,7 +115,7 @@ def __init__(
                 (default) or `client_secret_basic`.
         """
         if not client_secret:
-            raise ValueError("client_secret is required: SEP-990 mandates a confidential client")
+            raise ValueError("client_secret is required: this provider supports confidential clients only")
         if not issuer:
             raise ValueError("issuer is required: the authorization server is configuration, not discovery")
         self._resource = resource_url_from_server_url(server_url)
diff --git a/src/mcp/server/auth/handlers/register.py b/src/mcp/server/auth/handlers/register.py
index 7fb14b2c43..621a0f37d6 100644
--- a/src/mcp/server/auth/handlers/register.py
+++ b/src/mcp/server/auth/handlers/register.py
@@ -91,9 +91,9 @@ async def handle(self, request: Request) -> Response:
                 status_code=400,
             )
 
-        # SEP-990 §5.1 / draft-ietf-oauth-identity-assertion-authz-grant §8.1: the ID-JAG flow is
-        # for confidential clients provisioned out of band. Refuse to grant it through DCR so a
-        # self-registered client cannot reach the identity-assertion provider hook.
+        # SDK policy: the ID-JAG flow is for confidential clients (a SHOULD in
+        # draft-ietf-oauth-identity-assertion-authz-grant-04 §9.1) provisioned out of band. Refuse to
+        # grant it through DCR so a self-registered client cannot reach the provider hook.
         if JWT_BEARER_GRANT_TYPE in client_metadata.grant_types:
             return PydanticJSONResponse(
                 content=RegistrationErrorResponse(
diff --git a/src/mcp/server/auth/handlers/token.py b/src/mcp/server/auth/handlers/token.py
index 0e644c378a..00df115573 100644
--- a/src/mcp/server/auth/handlers/token.py
+++ b/src/mcp/server/auth/handlers/token.py
@@ -248,10 +248,10 @@ async def handle(self, request: Request):
                         )
                     )
 
-                # SEP-990 §5.1: only confidential clients may present an ID-JAG. ClientAuthenticator
-                # already rejects a secret-based method with no stored secret; this additionally
-                # rejects the public `none` method so an unauthenticated client never reaches the
-                # provider hook.
+                # SDK policy, adopting the SHOULD in draft-ietf-oauth-identity-assertion-authz-grant-04
+                # §9.1: only confidential clients may present an ID-JAG. ClientAuthenticator already
+                # rejects a secret-based method with no stored secret; this additionally rejects the
+                # public `none` method so an unauthenticated client never reaches the provider hook.
                 if not client_info.client_secret:
                     # RFC 6749 §5.2: the client authenticated but is not permitted this grant, so
                     # unauthorized_client (not invalid_client, which is for failed authentication).
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/tests/client/auth/extensions/test_identity_assertion.py b/tests/client/auth/extensions/test_identity_assertion.py
index d4c965edc5..f4f9b6080c 100644
--- a/tests/client/auth/extensions/test_identity_assertion.py
+++ b/tests/client/auth/extensions/test_identity_assertion.py
@@ -11,6 +11,7 @@
 
 import httpx2
 import pytest
+from inline_snapshot import snapshot
 
 from mcp.client.auth import OAuthFlowError, OAuthTokenError
 from mcp.client.auth.extensions.identity_assertion import IdentityAssertionOAuthProvider, _origin
@@ -377,7 +378,7 @@ def test_empty_client_secret_is_rejected() -> None:
     async def assertion_provider(audience: str, resource: str) -> str:
         raise NotImplementedError
 
-    with pytest.raises(ValueError, match="client_secret is required"):
+    with pytest.raises(ValueError) as exc_info:
         IdentityAssertionOAuthProvider(
             server_url=f"{RS}/mcp",
             storage=InMemoryStorage(),
@@ -387,6 +388,10 @@ async def assertion_provider(audience: str, resource: str) -> str:
             assertion_provider=assertion_provider,
         )
 
+    assert str(exc_info.value) == snapshot(
+        "client_secret is required: this provider supports confidential clients only"
+    )
+
 
 def test_empty_issuer_is_rejected() -> None:
     async def assertion_provider(audience: str, resource: str) -> str:
```
</details>

---

## psf__black-5259

**15/25** · [PR](https://github.com/psf/black/pull/5259) · [issue #260](https://github.com/psf/black/issues/260) · 3 FAIL_TO_PASS tests

### Issue

List concatenation, multiple lines
Probably not a bug, but I was wondering if the code below shouldn't be formatted more like call chains are.
I did not expect black to change anything other than quotes in this example.
Aligned brackets feel much more readable.

```
# before
-    search_fields = (
-        ['file__%s' % field for field in FileAdmin.search_fields] +
-        ['resource__%s' % field for field in ResourceAdmin.search_fields]
-    )
# black output
+    search_fields = ["file__%s" % field for field in FileAdmin.search_fields] + [
+        "resource__%s" % field for field in ResourceAdmin.search_fields
+    ]
```

Operating system: OSX 10.11.6
Python version: 3.6.5
Black version: 18.5b0
Does also happen on master: yes

### Files changed by the gold patch

- `CHANGES.md` (+3 / -0)
- `docs/the_black_code_style/future_style.md` (+30 / -0)
- `src/black/linegen.py` (+11 / -0)
- `src/black/lines.py` (+89 / -0)
- `src/black/mode.py` (+1 / -0)
- `src/black/resources/black.schema.json` (+1 / -0)

### Tests that must pass (names, deduplicated)

- `test_simple_format`

<details><summary>Gold patch</summary>

```diff
diff --git a/CHANGES.md b/CHANGES.md
index 1871c688ee0..c5e4152e5b4 100644
--- a/CHANGES.md
+++ b/CHANGES.md
@@ -17,6 +17,9 @@
 
 <!-- Changes that affect Black's preview style -->
 
+- Format long binary operations between collection displays symmetrically when both
+  operands fit on their own delimiter-split line (#5259)
+
 ### Configuration
 
 <!-- Changes to how Black can be configured -->
diff --git a/docs/the_black_code_style/future_style.md b/docs/the_black_code_style/future_style.md
index 2435209702c..a3dea90d492 100644
--- a/docs/the_black_code_style/future_style.md
+++ b/docs/the_black_code_style/future_style.md
@@ -51,6 +51,9 @@ Currently, the following features are included in the preview style:
   definition starts inside a `# fmt: off` block after an import.
 - `remove_redundant_generator_parentheses`: Remove redundant parentheses around
   generator expressions. ([see below](labels/remove-redundant-generator-parentheses))
+- `symmetric_collection_operations`: Keep optional parentheses around long binary
+  operations between collection displays when both operands fit on their own
+  delimiter-split line. ([see below](labels/symmetric-collection-operations))
 - `remove_redundant_unpacking_parentheses`: Remove redundant parentheses around
   individual variables in unpacking targets.
   ([see below](labels/remove-redundant-unpacking-parentheses))
@@ -287,6 +290,33 @@ any additional pair:
 [(item for item in items), fallback]
 ```
 
+(labels/symmetric-collection-operations)=
+
+### Symmetric display operations
+
+When a binary operation between two collection displays is too long for one line and
+both operands fit on their own delimiter-split line, Black keeps optional parentheses
+around the expression so that the operands can be split symmetrically. This applies to
+every arithmetic, bitwise, and symbolic comparison operator between collection displays.
+If either display needs an internal split, including when an active magic trailing comma
+forces it onto multiple lines, Black retains the existing formatting.
+
+```python
+# Before
+names = ["Alice", "Bob", "Charlie", "Diana", "Edward"] + [
+    "Fiona",
+    "George",
+    "Harriet",
+    "Isabelle",
+]
+
+# After (with --preview)
+names = (
+    ["Alice", "Bob", "Charlie", "Diana", "Edward"]
+    + ["Fiona", "George", "Harriet", "Isabelle"]
+)
+```
+
 (labels/wrap-comprehension-in)=
 
 ### Wrapping long comprehension `in` clauses
diff --git a/src/black/linegen.py b/src/black/linegen.py
index d50c94e8746..099d4262648 100644
--- a/src/black/linegen.py
+++ b/src/black/linegen.py
@@ -33,6 +33,7 @@
     can_be_split,
     can_omit_invisible_parens,
     is_line_short_enough,
+    is_symmetric_collection_binop,
     line_to_string,
 )
 from black.mode import Feature, Mode, Preview
@@ -1223,6 +1224,14 @@ def _maybe_split_omitting_optional_parens(
     features: Collection[Feature] = (),
     omit: Collection[LeafID] = (),
 ) -> Iterator[Line]:
+    split_symmetric_collection_binops = (
+        Preview.symmetric_collection_operations in mode
+        and rhs.opening_bracket.type == token.LPAR
+        and not rhs.opening_bracket.value
+        and rhs.closing_bracket.type == token.RPAR
+        and not rhs.closing_bracket.value
+        and is_symmetric_collection_binop(rhs.body, mode.line_length)
+    )
     if (
         Feature.FORCE_OPTIONAL_PARENTHESES not in features
         # the opening bracket is an optional paren
@@ -1288,6 +1297,8 @@ def _maybe_split_omitting_optional_parens(
 
     ensure_visible(rhs.opening_bracket)
     ensure_visible(rhs.closing_bracket)
+    if split_symmetric_collection_binops:
+        rhs.body.should_split_rhs = True
     for result in (rhs.head, rhs.body, rhs.tail):
         if result:
             yield result
diff --git a/src/black/lines.py b/src/black/lines.py
index c2593795f86..123b4894372 100644
--- a/src/black/lines.py
+++ b/src/black/lines.py
@@ -10,16 +10,20 @@
 from black.nodes import (
     BRACKETS,
     CLOSING_BRACKETS,
+    COMPARATORS,
+    MATH_OPERATORS,
     OPENING_BRACKETS,
     STANDALONE_COMMENT,
     TEST_DESCENDANTS,
     child_towards,
     first_leaf,
     is_docstring,
+    is_generator,
     is_import,
     is_multiline_string,
     is_one_sequence_between,
     is_one_tuple,
+    is_tuple,
     is_type_comment,
     is_type_ignore_comment,
     is_with_or_async_with_stmt,
@@ -1542,6 +1546,84 @@ def _is_annotated_assignment(head: Line) -> bool:
     return False
 
 
+def is_symmetric_collection_binop(line: Line, line_length: int) -> bool:
+    """Is `line` a binary operation between single-line collection displays?"""
+    if len(line.bracket_tracker.delimiters) != 1:
+        return False
+
+    # Delimiters is keyed by leaf ID, not line position.
+    delimiter_id = next(iter(line.bracket_tracker.delimiters))
+    try:
+        left_closing_index = next(
+            index for index, leaf in enumerate(line.leaves) if id(leaf) == delimiter_id
+        )
+    except StopIteration:
+        return False
+
+    # Math operators are split *before* the delimiter, so BracketTracker keys
+    # them by the preceding leaf.
+    delimiter_index = left_closing_index + 1
+    if delimiter_index >= len(line.leaves) - 1:
+        return False
+
+    first = line.leaves[0]
+    left_closing = line.leaves[left_closing_index]
+    delimiter = line.leaves[delimiter_index]
+    right_opening = line.leaves[delimiter_index + 1]
+    last = line.leaves[-1]
+
+    collection_display = {
+        (token.LSQB, token.RSQB),
+        (token.LPAR, token.RPAR),
+        (token.LBRACE, token.RBRACE),
+    }
+
+    def is_collection_display(opening: Leaf, closing: Leaf) -> bool:
+        if (opening.type, closing.type) not in collection_display:
+            return False
+        return opening.type != token.LPAR or (
+            opening.parent is not None
+            and is_tuple(opening.parent)
+            and not is_generator(opening.parent)
+        )
+
+    if (
+        not is_collection_display(first, left_closing)
+        or not is_collection_display(right_opening, last)
+        or delimiter.type not in MATH_OPERATORS | COMPARATORS
+        or left_closing.opening_bracket is not first
+        or last.opening_bracket is not right_opening
+    ):
+        return False
+
+    # Keep the existing asymmetric split when either display is already forced
+    # to split by a magic trailing comma.
+    if line.mode.magic_trailing_comma and (
+        line.leaves[left_closing_index - 1].type == token.COMMA
+        or line.leaves[-2].type == token.COMMA
+    ):
+        return False
+
+    def rendered_width(start: int, end: int) -> int | None:
+        leaves = line.leaves[start:end]
+        rendered = "    " * line.depth
+        # End-of-line comments do not determine whether the operand itself fits.
+        for index, leaf in enumerate(leaves):
+            rendered += leaf.value if index == 0 else str(leaf)
+        if "\n" in rendered:
+            return None
+        return str_width(rendered)
+
+    left_width = rendered_width(0, delimiter_index)
+    right_width = rendered_width(delimiter_index, len(line.leaves))
+    return (
+        left_width is not None
+        and right_width is not None
+        and left_width <= line_length
+        and right_width <= line_length
+    )
+
+
 def can_omit_invisible_parens(
     rhs: RHSResult,
     line_length: int,
@@ -1676,6 +1758,13 @@ def can_omit_invisible_parens(
             # the with statement. `rhs.head` is the `with (` part on the previous
             # line.
             return False
+        if (
+            Preview.symmetric_collection_operations in mode
+            and is_symmetric_collection_binop(line, line_length)
+        ):
+            # Retaining the optional parentheses lets the delimiter splitter put
+            # each display operand on its own line instead of exploding just one.
+            return False
         # Otherwise it may also read better, but we don't do it today and requires
         # careful considerations for all possible cases. See
         # https://github.com/psf/black/issues/2156.
diff --git a/src/black/mode.py b/src/black/mode.py
index cdcb6e713eb..4d22892fff3 100644
--- a/src/black/mode.py
+++ b/src/black/mode.py
@@ -265,6 +265,7 @@ class Preview(Enum):
     parenthesize_tuple_in_yield = auto()
     fmt_off_class_blank_lines = auto()
     remove_redundant_generator_parentheses = auto()
+    symmetric_collection_operations = auto()
     normalize_tstring_prefix = auto()
     remove_redundant_unpacking_parentheses = auto()
     fix_magic_trailing_comma_trailer_split = auto()
diff --git a/src/black/resources/black.schema.json b/src/black/resources/black.schema.json
index d17495205f7..e61000c6b23 100644
--- a/src/black/resources/black.schema.json
+++ b/src/black/resources/black.schema.json
@@ -95,6 +95,7 @@
           "parenthesize_tuple_in_yield",
           "fmt_off_class_blank_lines",
           "remove_redundant_generator_parentheses",
+          "symmetric_collection_operations",
           "normalize_tstring_prefix",
           "remove_redundant_unpacking_parentheses",
           "fix_magic_trailing_comma_trailer_split",
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/tests/data/cases/preview_symmetric_list_concatenation.py b/tests/data/cases/preview_symmetric_list_concatenation.py
new file mode 100644
index 00000000000..96cd98cafa0
--- /dev/null
+++ b/tests/data/cases/preview_symmetric_list_concatenation.py
@@ -0,0 +1,249 @@
+# flags: --preview
+
+# Regression test for https://github.com/psf/black/issues/260.
+search_fields = (["file__%s" % field for field in FileAdmin.search_fields] + ["resource__%s" % field for field in ResourceAdmin.search_fields])
+
+# Plain list displays receive the same symmetric treatment.
+names = ["Alice", "Bob", "Charlie", "Diana", "Edward"] + ["Fiona", "George", "Harriet", "Isabelle"]
+
+# The matching tuple, dictionary, and set operations are also symmetric.
+tuple_values = ("first_long_value", "second_long_value") + ("third_long_value", "fourth_long_value")
+dictionary_values = {"first_long_key": first_long_value, "second_long_key": second_long_value} | {"third_long_key": third_long_value, "fourth_long_key": fourth_long_value}
+set_union = {"first_long_value", "second_long_value"} | {"third_long_value", "fourth_long_value"}
+set_intersection = {"first_long_value", "second_long_value"} & {"third_long_value", "fourth_long_value"}
+
+# Every arithmetic and bitwise binary operator gets the same treatment when both operands
+# are collections.
+collection_subtraction = ["first_long_value", "second_long_value"] - ["third_long_value", "fourth_long_value"]
+collection_product = ("first_long_value", "second_long_value") * ("third_long_value", "fourth_long_value")
+collection_division = {"first_long_value", "second_long_value"} / {"third_long_value", "fourth_long_value"}
+collection_floor_division = ["first_long_value", "second_long_value"] // ["third_long_value", "fourth_long_value"]
+collection_modulo = {"first_long_value", "second_long_value"} % {"third_long_value", "fourth_long_value"}
+collection_matrix = ["first_long_value", "second_long_value"] @ ["third_long_value", "fourth_long_value"]
+collection_power = ("first_long_value", "second_long_value") ** ("third_long_value", "fourth_long_value")
+collection_shift = {"first_long_value", "second_long_value"} << {"third_long_value", "fourth_long_value"}
+collection_right_shift = {"first_long_value", "second_long_value"} >> {"third_long_value", "fourth_long_value"}
+collection_xor = ["first_long_value", "second_long_value"] ^ ["third_long_value", "fourth_long_value"]
+mixed_collection_operands = ["first_long_value", "second_long_value"] + ("third_long_value", "fourth_long_value")
+
+# Symbolic comparisons between collection displays also split symmetrically.
+list_equality = ["first_long_value", "second_long_value"] == ["third_long_value", "fourth_long_value"]
+list_comprehension_equality = [item for item in source_items] == [first_value, second_value, third_value]
+
+# Parenthesized scalars and generator expressions are not collection displays.
+parenthesized_scalars = (first_function_with_a_really_long_name(first_argument)) + (second_function_with_a_really_long_name(second_argument))
+generator_operands = (first_item for first_item in first_collection_with_a_really_long_name) + (second_item for second_item in second_collection_with_a_really_long_name)
+
+# Comments on an operand stay attached and formatting remains stable.
+commented = (
+    ["first_long_value", "second_long_value", "third_long_value"]  # first list
+    + ["fourth_long_value", "fifth_long_value", "sixth_long_value"]
+)
+
+commented_left = (
+    ["first_value", "second_value", "third_value"]  # abc
+    + ["fourth_value", "fifth_value", "sixth_value"]
+)
+commented_right = (
+    ["first_value", "second_value", "third_value"]
+    + ["fourth_value", "fifth_value", "sixth_value"]  # abc
+)
+
+# Split symmetrically even when the RHS alone fits inside optional parentheses.
+values = [first_value, second_value, third_value] + [fourth_value, fifth_value, sixth_value]
+
+# Chained concatenations already use the normal delimiter split.
+chained = ["first_long_value", "second_long_value"] + ["third_long_value", "fourth_long_value"] + ["fifth_long_value", "sixth_long_value"]
+
+# Mixed operands are not symmetric list concatenations.
+mixed_left = ["first_long_value", "second_long_value", "third_long_value"] + tuple_with_a_very_long_name
+mixed_right = list_with_a_very_long_name + ["first_long_value", "second_long_value", "third_long_value"]
+
+# Short concatenations stay on one line.
+small = [1, 2] + [3, 4]
+
+# Lists that already require bracket splitting keep the existing formatting.
+long_left = ["first_value_with_an_extremely_long_name", "second_value_with_an_extremely_long_name", "third"] + ["short"]
+long_right = ["short"] + ["first_value_with_an_extremely_long_name", "second_value_with_an_extremely_long_name", "third"]
+both_long = ["first_value_with_an_extremely_long_name", "second_value_with_an_extremely_long_name", "third"] + ["fourth_value_with_an_extremely_long_name", "fifth_value_with_an_extremely_long_name", "sixth"]
+
+# Magic trailing commas also keep the existing formatting.
+magic_left = [
+    "first_long_value",
+    "second_long_value",
+] + ["third_long_value", "fourth_long_value"]
+magic_right = ["first_long_value", "second_long_value"] + [
+    "third_long_value",
+    "fourth_long_value",
+]
+
+# output
+
+# Regression test for https://github.com/psf/black/issues/260.
+search_fields = (
+    ["file__%s" % field for field in FileAdmin.search_fields]
+    + ["resource__%s" % field for field in ResourceAdmin.search_fields]
+)
+
+# Plain list displays receive the same symmetric treatment.
+names = (
+    ["Alice", "Bob", "Charlie", "Diana", "Edward"]
+    + ["Fiona", "George", "Harriet", "Isabelle"]
+)
+
+# The matching tuple, dictionary, and set operations are also symmetric.
+tuple_values = (
+    ("first_long_value", "second_long_value")
+    + ("third_long_value", "fourth_long_value")
+)
+dictionary_values = (
+    {"first_long_key": first_long_value, "second_long_key": second_long_value}
+    | {"third_long_key": third_long_value, "fourth_long_key": fourth_long_value}
+)
+set_union = (
+    {"first_long_value", "second_long_value"}
+    | {"third_long_value", "fourth_long_value"}
+)
+set_intersection = (
+    {"first_long_value", "second_long_value"}
+    & {"third_long_value", "fourth_long_value"}
+)
+
+# Every arithmetic and bitwise binary operator gets the same treatment when both operands
+# are collections.
+collection_subtraction = (
+    ["first_long_value", "second_long_value"]
+    - ["third_long_value", "fourth_long_value"]
+)
+collection_product = (
+    ("first_long_value", "second_long_value")
+    * ("third_long_value", "fourth_long_value")
+)
+collection_division = (
+    {"first_long_value", "second_long_value"}
+    / {"third_long_value", "fourth_long_value"}
+)
+collection_floor_division = (
+    ["first_long_value", "second_long_value"]
+    // ["third_long_value", "fourth_long_value"]
+)
+collection_modulo = (
+    {"first_long_value", "second_long_value"}
+    % {"third_long_value", "fourth_long_value"}
+)
+collection_matrix = (
+    ["first_long_value", "second_long_value"]
+    @ ["third_long_value", "fourth_long_value"]
+)
+collection_power = (
+    ("first_long_value", "second_long_value")
+    ** ("third_long_value", "fourth_long_value")
+)
+collection_shift = (
+    {"first_long_value", "second_long_value"}
+    << {"third_long_value", "fourth_long_value"}
+)
+collection_right_shift = (
+    {"first_long_value", "second_long_value"}
+    >> {"third_long_value", "fourth_long_value"}
+)
+collection_xor = (
+    ["first_long_value", "second_long_value"]
+    ^ ["third_long_value", "fourth_long_value"]
+)
+mixed_collection_operands = (
+    ["first_long_value", "second_long_value"]
+    + ("third_long_value", "fourth_long_value")
+)
+
+# Symbolic comparisons between collection displays also split symmetrically.
+list_equality = (
+    ["first_long_value", "second_long_value"]
+    == ["third_long_value", "fourth_long_value"]
+)
+list_comprehension_equality = (
+    [item for item in source_items]
+    == [first_value, second_value, third_value]
+)
+
+# Parenthesized scalars and generator expressions are not collection displays.
+parenthesized_scalars = (first_function_with_a_really_long_name(first_argument)) + (
+    second_function_with_a_really_long_name(second_argument)
+)
+generator_operands = (
+    first_item for first_item in first_collection_with_a_really_long_name
+) + (second_item for second_item in second_collection_with_a_really_long_name)
+
+# Comments on an operand stay attached and formatting remains stable.
+commented = (
+    ["first_long_value", "second_long_value", "third_long_value"]  # first list
+    + ["fourth_long_value", "fifth_long_value", "sixth_long_value"]
+)
+
+commented_left = (
+    ["first_value", "second_value", "third_value"]  # abc
+    + ["fourth_value", "fifth_value", "sixth_value"]
+)
+commented_right = (
+    ["first_value", "second_value", "third_value"]
+    + ["fourth_value", "fifth_value", "sixth_value"]  # abc
+)
+
+# Split symmetrically even when the RHS alone fits inside optional parentheses.
+values = (
+    [first_value, second_value, third_value]
+    + [fourth_value, fifth_value, sixth_value]
+)
+
+# Chained concatenations already use the normal delimiter split.
+chained = (
+    ["first_long_value", "second_long_value"]
+    + ["third_long_value", "fourth_long_value"]
+    + ["fifth_long_value", "sixth_long_value"]
+)
+
+# Mixed operands are not symmetric list concatenations.
+mixed_left = [
+    "first_long_value",
+    "second_long_value",
+    "third_long_value",
+] + tuple_with_a_very_long_name
+mixed_right = list_with_a_very_long_name + [
+    "first_long_value",
+    "second_long_value",
+    "third_long_value",
+]
+
+# Short concatenations stay on one line.
+small = [1, 2] + [3, 4]
+
+# Lists that already require bracket splitting keep the existing formatting.
+long_left = [
+    "first_value_with_an_extremely_long_name",
+    "second_value_with_an_extremely_long_name",
+    "third",
+] + ["short"]
+long_right = ["short"] + [
+    "first_value_with_an_extremely_long_name",
+    "second_value_with_an_extremely_long_name",
+    "third",
+]
+both_long = [
+    "first_value_with_an_extremely_long_name",
+    "second_value_with_an_extremely_long_name",
+    "third",
+] + [
+    "fourth_value_with_an_extremely_long_name",
+    "fifth_value_with_an_extremely_long_name",
+    "sixth",
+]
+
+# Magic trailing commas also keep the existing formatting.
+magic_left = [
+    "first_long_value",
+    "second_long_value",
+] + ["third_long_value", "fourth_long_value"]
+magic_right = ["first_long_value", "second_long_value"] + [
+    "third_long_value",
+    "fourth_long_value",
+]
diff --git a/tests/data/cases/preview_symmetric_list_concatenation_line_length.py b/tests/data/cases/preview_symmetric_list_concatenation_line_length.py
new file mode 100644
index 00000000000..c847e737490
--- /dev/null
+++ b/tests/data/cases/preview_symmetric_list_concatenation_line_length.py
@@ -0,0 +1,12 @@
+# flags: --preview --line-length=60
+
+values = [first_value, second_value] + [third_value, fourth_value]
+short_values = [first_value] + [second_value]
+
+# output
+
+values = (
+    [first_value, second_value]
+    + [third_value, fourth_value]
+)
+short_values = [first_value] + [second_value]
diff --git a/tests/data/cases/preview_symmetric_list_concatenation_skip_magic.py b/tests/data/cases/preview_symmetric_list_concatenation_skip_magic.py
new file mode 100644
index 00000000000..e2249ba52bb
--- /dev/null
+++ b/tests/data/cases/preview_symmetric_list_concatenation_skip_magic.py
@@ -0,0 +1,15 @@
+# flags: --preview --skip-magic-trailing-comma
+
+# Ignored trailing commas do not prevent symmetric formatting.
+values = [
+    "first_long_value",
+    "second_long_value",
+] + ["third_long_value", "fourth_long_value"]
+
+# output
+
+# Ignored trailing commas do not prevent symmetric formatting.
+values = (
+    ["first_long_value", "second_long_value"]
+    + ["third_long_value", "fourth_long_value"]
+)
diff --git a/tests/data/cases/stable_symmetric_list_concatenation.py b/tests/data/cases/stable_symmetric_list_concatenation.py
new file mode 100644
index 00000000000..7fc4963b167
--- /dev/null
+++ b/tests/data/cases/stable_symmetric_list_concatenation.py
@@ -0,0 +1,4 @@
+# Stable style must keep the existing asymmetric bracket split.
+search_fields = ["file__%s" % field for field in FileAdmin.search_fields] + [
+    "resource__%s" % field for field in ResourceAdmin.search_fields
+]
```
</details>

---

## psf__black-5297

**16/25** · [PR](https://github.com/psf/black/pull/5297) · [issue #3869](https://github.com/psf/black/issues/3869) · 2 FAIL_TO_PASS tests

### Issue

Failure to consistently format inline type comments on a multi-line attribute access
<!--
Please make sure that the bug is not already fixed either in newer versions or the
current development version. To confirm this, you have three options:

1. Update Black's version if a newer release exists: `pip install -U black`
2. Use the online formatter at <https://black.vercel.app/?version=main>, which will use
   the latest main branch.
3. Or run _Black_ on your machine:
   - create a new virtualenv (make sure it's the same Python version);
   - clone this repository;
   - run `pip install -e .[d]`;
   - run `pip install -r test_requirements.txt`
   - make sure it's sane by running `python -m pytest`; and
   - run `black` like you did last time.
-->

**Describe the bug**

<!-- A clear and concise description of what the bug is. -->
Black fails to format code containing inline type comments within a multi-line attribute access consistently (the formatting moves the type comments to the end of line in trying to collapse the attribute access, changing meaning and triggering the `INTERNAL ERROR` check).

**To Reproduce**

<!--
Minimal steps to reproduce the behavior with source code and Black's configuration.
-->

For example, take this code:

```sh-session
❯ cat /tmp/foo.py

def _get_light_style(app: sphinx.application.Sphinx) -> Style:
    return (
        app  # type: ignore[no-any-return]
            .builder
            .highlighter # type: ignore[attr-defined]
            .formatter_args["style"]
        )

```

And run it with these arguments:

```sh
❯ black /tmp/foo.py
```

The resulting error is:

> error: cannot format /tmp/foo.py: INTERNAL ERROR: Black produced code that is not equivalent to the source.  Please report a bug on https://github.com/psf/black/issues.  This diff might be helpful: /var/folders/y1/j465wvf92vs938kmgqh63bj80000gn/T/blk_3otrtpyx.log

**Expected behavior**

<!-- A clear and concise description of what you expected to happen. -->
Black preserves the inline comments between attribute accesses.

**Environment**

<!-- Please complete the following information: -->

- Black's version: 23.9.0
- OS and Python version: 3.11.0

**Additional context**

<!-- Add any other context about the problem here. -->


```sh-session
❯ cat /var/folders/y1/j465wvf92vs938kmgqh63bj80000gn/T/blk_3otrtpyx.log
--- src
+++ dst
@@ -106,8 +106,6 @@
         None,  # NoneType
     )  # /FunctionDef
   type_ignores=
     TypeIgnore(
     )  # /TypeIgnore
-    TypeIgnore(
-    )  # /TypeIgnore
 )  # /Module
\ No newline at end of file
```

```sh-session
❯ black --fast /tmp/foo.py         
reformatted /tmp/foo.py

All done! ✨ 🍰 ✨
1 file reformatted.

❯ cat /tmp/foo.py
def _get_light_style(app: sphinx.application.Sphinx) -> Style:
    return app.builder.highlighter.formatter_args[  # type: ignore[no-any-return]  # type: ignore[attr-defined]
        "style"
    ]
```

### Files changed by the gold patch

- `CHANGES.md` (+2 / -0)
- `src/black/linegen.py` (+30 / -0)
- `src/black/lines.py` (+21 / -0)

### Tests that must pass (names, deduplicated)

- `test_simple_format`

<details><summary>Gold patch</summary>

```diff
diff --git a/CHANGES.md b/CHANGES.md
index 5e5ba2aa285..ce6d559756d 100644
--- a/CHANGES.md
+++ b/CHANGES.md
@@ -73,6 +73,8 @@
   `from x import (  # fmt: skip`) when a standalone comment is among the bracket's
   contents: the whole statement is now preserved instead of being reformatted (and
   previously crashing) (#5161)
+- Fix an AST safety error when separate `type: ignore` comments in a parenthesized
+  attribute chain were merged onto one physical line (#5297)
 - Preserve comments and blank lines outside requested ranges when formatting with
   `--line-ranges` (#5175)
 - Fix crash when `# fmt: skip` is used on one-line `async def`, `async with`, and
diff --git a/src/black/linegen.py b/src/black/linegen.py
index b6a0ddf66a3..463018f2f84 100644
--- a/src/black/linegen.py
+++ b/src/black/linegen.py
@@ -825,6 +825,7 @@ def transform_line(
                     string_paren_strip,
                     string_split,
                     delimiter_split,
+                    type_ignore_comment_split,
                     standalone_comment_split,
                     string_paren_wrap,
                     right_hand_split_with_omits,
@@ -841,6 +842,7 @@ def transform_line(
             if line.inside_brackets:
                 transformers = [
                     delimiter_split,
+                    type_ignore_comment_split,
                     standalone_comment_split,
                     right_hand_split_with_omits,
                 ]
@@ -1620,6 +1622,34 @@ def append_to_line(leaf: Leaf) -> Iterator[Line]:
         yield current_line
 
 
+@dont_increase_indentation
+def type_ignore_comment_split(
+    line: Line, features: Collection[Feature], mode: Mode
+) -> Iterator[Line]:
+    """Keep multiple type ignores on their original physical lines."""
+    if not line.contains_multiple_type_ignores_at_current_depth() or not any(
+        leaf.type == token.DOT for leaf in line.leaves
+    ):
+        raise CannotSplit("Line does not have multiple type ignore comments")
+
+    current_line = Line(
+        mode=line.mode, depth=line.depth, inside_brackets=line.inside_brackets
+    )
+    for leaf in line.leaves:
+        current_line.append(leaf, preformatted=True)
+        comments = line.comments_after(leaf)
+        for comment in comments:
+            current_line.append(comment, preformatted=True)
+        if any(is_type_ignore_comment(comment, mode=mode) for comment in comments):
+            yield current_line
+            current_line = Line(
+                mode=line.mode, depth=line.depth, inside_brackets=line.inside_brackets
+            )
+
+    if current_line:
+        yield current_line
+
+
 def _force_standalone_comment_split(line: Line) -> Iterator[Line]:
     """Last-resort split at every standalone-comment boundary."""
     current_line = Line(
diff --git a/src/black/lines.py b/src/black/lines.py
index b71de49e705..028d868d5fd 100644
--- a/src/black/lines.py
+++ b/src/black/lines.py
@@ -313,6 +313,18 @@ def contains_uncollapsable_type_comments(self) -> bool:
 
         return False
 
+    def contains_multiple_type_ignores_at_current_depth(self) -> bool:
+        count = 0
+        for leaf in self.leaves:
+            if leaf.bracket_depth != 0:
+                continue
+            for comment in self.comments_after(leaf):
+                if is_type_ignore_comment(comment, mode=self.mode):
+                    count += 1
+                    if count > 1:
+                        return True
+        return False
+
     def contains_unsplittable_type_ignore(self) -> bool:
         if not self.leaves:
             return False
@@ -1532,6 +1544,15 @@ def can_omit_invisible_parens(
     """
     line = rhs.body
 
+    # Multiple type ignores must stay on separate physical lines. Keeping the
+    # optional parens gives the line transformer a safe place to split them.
+    if (
+        line.contains_multiple_type_ignores_at_current_depth()
+        and not line.bracket_tracker.delimiters
+        and any(leaf.type == token.DOT for leaf in line.leaves)
+    ):
+        return False
+
     # Don't omit optional parens when the opening paren carries an inline comment.
     # Omitting them re-parents the comment onto a different leaf after the next
     # parse, which can make the RHS splitter choose a different shape on each
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/tests/data/cases/type_ignore_attribute_chain.py b/tests/data/cases/type_ignore_attribute_chain.py
new file mode 100644
index 00000000000..c6d636c5fcc
--- /dev/null
+++ b/tests/data/cases/type_ignore_attribute_chain.py
@@ -0,0 +1,18 @@
+def _get_light_style(app: sphinx.application.Sphinx) -> Style:
+    return (
+        app  # type: ignore[no-any-return]
+            .builder
+            .highlighter  # type: ignore[attr-defined]
+            .formatter_args["style"]
+        )
+
+
+# output
+
+
+def _get_light_style(app: sphinx.application.Sphinx) -> Style:
+    return (
+        app  # type: ignore[no-any-return]
+        .builder.highlighter  # type: ignore[attr-defined]
+        .formatter_args["style"]
+    )
diff --git a/tests/data/cases/type_ignore_attribute_chain_unstable.py b/tests/data/cases/type_ignore_attribute_chain_unstable.py
new file mode 100644
index 00000000000..12e7eaa1c46
--- /dev/null
+++ b/tests/data/cases/type_ignore_attribute_chain_unstable.py
@@ -0,0 +1,21 @@
+# flags: --unstable
+
+
+def _get_light_style(app: sphinx.application.Sphinx) -> Style:
+    return (
+        app  # type: ignore[no-any-return]
+            .builder
+            .highlighter  # type: ignore[attr-defined]
+            .formatter_args["style"]
+        )
+
+
+# output
+
+
+def _get_light_style(app: sphinx.application.Sphinx) -> Style:
+    return (
+        app  # type: ignore[no-any-return]
+        .builder.highlighter  # type: ignore[attr-defined]
+        .formatter_args["style"]
+    )
```
</details>

---

## psf__black-5304

**17/25** · [PR](https://github.com/psf/black/pull/5304) · [issue #2943](https://github.com/psf/black/issues/2943) · 1 FAIL_TO_PASS tests

### Issue

Remove redundant parentheses from generator expression inside function call
**Describe the style change**

I think that redundant parentheses should be removed from generators or at least be allowed to stick to next/previous parenthesis. Consider the following source example:

```python
any((
    this_very_long_method_name(obj) or another_long_method_name(obj)
    for obj in this_iterable
))
```
**Examples in the current _Black_ style**

Now black (22.1.0) formats it to

```python
any(
    (
        this_very_long_method_name(obj) or another_long_method_name(obj)
        for obj in this_iterable
    )
)
```
I think that added extra indentation level here makes source look worse.

**Desired style**

```python
any(
    this_very_long_method_name(obj) or another_long_method_name(obj)
    for obj in this_iterable
) 
```

Or at least

```python
any((
    this_very_long_method_name(obj) or another_long_method_name(obj)
    for obj in this_iterable
))
```

I would prefer the first approach (since AST of both results is the same), because this parenthesis are redundant and can be safely removed.

Related issue: #2522

### Files changed by the gold patch

- `CHANGES.md` (+1 / -0)
- `docs/the_black_code_style/future_style.md` (+28 / -0)
- `src/black/linegen.py` (+46 / -1)
- `src/black/mode.py` (+1 / -0)
- `src/black/resources/black.schema.json` (+2 / -1)

### Tests that must pass (names, deduplicated)

- `test_simple_format`

<details><summary>Gold patch</summary>

```diff
diff --git a/CHANGES.md b/CHANGES.md
index 14fcc56680f..35377597b40 100644
--- a/CHANGES.md
+++ b/CHANGES.md
@@ -58,6 +58,7 @@
 
 <!-- Changes that affect Black's preview style -->
 
+- Remove redundant parentheses around generator expressions (#5304)
 - Preserve two blank lines before a top-level class starting inside a `# fmt: off` block
   after an import (#5238)
 - Fix unnecessary parentheses around short RHS expressions in indexed assignments like
diff --git a/docs/the_black_code_style/future_style.md b/docs/the_black_code_style/future_style.md
index 4d098aa8888..b02694c5cbc 100644
--- a/docs/the_black_code_style/future_style.md
+++ b/docs/the_black_code_style/future_style.md
@@ -45,6 +45,34 @@ Currently, the following features are included in the preview style:
   statements.
 - `fmt_off_class_blank_lines`: Preserve two blank lines before a top-level class whose
   definition starts inside a `# fmt: off` block after an import.
+- `remove_redundant_generator_parentheses`: Remove redundant parentheses around
+  generator expressions. ([see below](labels/remove-redundant-generator-parentheses))
+
+(labels/remove-redundant-generator-parentheses)=
+
+### Redundant generator parentheses
+
+Black removes extra parentheses around generator expressions. When a generator
+expression is the sole argument to a call, the call's parentheses are sufficient:
+
+```python
+# Before
+any((item.is_valid() for item in items))
+
+# After (with --preview)
+any(item.is_valid() for item in items)
+```
+
+In other contexts, Black keeps the parentheses required by Python syntax while removing
+any additional pair:
+
+```python
+# Before
+[((item for item in items)), fallback]
+
+# After (with --preview)
+[(item for item in items), fallback]
+```
 
 (labels/wrap-comprehension-in)=
 
diff --git a/src/black/linegen.py b/src/black/linegen.py
index a1177023dd7..c779580b706 100644
--- a/src/black/linegen.py
+++ b/src/black/linegen.py
@@ -377,6 +377,23 @@ def visit_power(self, node: Node) -> Iterator[Line]:
             ):
                 wrap_in_parentheses(node, leaf)
 
+        if Preview.remove_redundant_generator_parentheses in self.mode:
+            for child in node.children:
+                if (
+                    child.type == syms.trailer
+                    and len(child.children) == 3
+                    and is_lpar_token(child.children[0])
+                    and is_generator(child.children[1])
+                    and is_rpar_token(child.children[2])
+                ):
+                    maybe_make_parens_invisible_in_atom(
+                        child.children[1],
+                        parent=child,
+                        mode=self.mode,
+                        features=self.features,
+                        remove_generator_parens=True,
+                    )
+
         remove_await_parens(node, mode=self.mode, features=self.features)
 
         yield from self.visit_default(node)
@@ -568,6 +585,17 @@ def visit_NUMBER(self, leaf: Leaf) -> Iterator[Line]:
 
     def visit_atom(self, node: Node) -> Iterator[Line]:
         """Visit any atom"""
+        if (
+            Preview.remove_redundant_generator_parentheses in self.mode
+            and _has_redundant_generator_parentheses(node)
+        ):
+            maybe_make_parens_invisible_in_atom(
+                node,
+                parent=node.parent or node,
+                mode=self.mode,
+                features=self.features,
+            )
+
         if len(node.children) == 3:
             first = node.children[0]
             last = node.children[-1]
@@ -1614,6 +1642,20 @@ def _is_parenthesized_lambda_or_ternary(node: LN) -> bool:
     return False
 
 
+def _has_redundant_generator_parentheses(node: LN) -> bool:
+    """Whether `node` adds parentheses around a parenthesized generator."""
+    if (
+        node.type != syms.atom
+        or len(node.children) != 3
+        or not is_lpar_token(node.children[0])
+        or not is_rpar_token(node.children[-1])
+    ):
+        return False
+
+    middle = node.children[1]
+    return is_generator(middle) or _has_redundant_generator_parentheses(middle)
+
+
 def normalize_invisible_parens(
     node: Node, parens_after: set[str], *, mode: Mode, features: Collection[Feature]
 ) -> None:
@@ -1959,6 +2001,7 @@ def maybe_make_parens_invisible_in_atom(
     features: Collection[Feature],
     remove_brackets_around_comma: bool = False,
     allow_star_expr: bool = False,
+    remove_generator_parens: bool = False,
 ) -> bool:
     """If it's safe, make the parens in the atom `node` invisible, recursively.
     Additionally, remove repeated, adjacent invisible parens from the atom `node`
@@ -1966,6 +2009,7 @@ def maybe_make_parens_invisible_in_atom(
 
     Returns whether the node should itself be wrapped in invisible parentheses.
     """
+    can_remove_generator_parens = remove_generator_parens and is_generator(node)
     if (
         node.type not in (syms.atom, syms.expr)
         or is_empty_tuple(node)
@@ -1983,6 +2027,7 @@ def maybe_make_parens_invisible_in_atom(
             # and option to skip this check for `for` and `with` statements.
             not remove_brackets_around_comma
             and max_delimiter_priority_in_atom(node) >= COMMA_PRIORITY
+            and not can_remove_generator_parens
             # Remove parentheses around multiple exception types in except and
             # except* without as. See PEP 758 for details.
             and not (
@@ -2003,7 +2048,7 @@ def maybe_make_parens_invisible_in_atom(
         )
         or is_tuple_containing_walrus(node)
         or (not allow_star_expr and is_tuple_containing_star(node))
-        or is_generator(node)
+        or (not can_remove_generator_parens and is_generator(node))
     ):
         return False
 
diff --git a/src/black/mode.py b/src/black/mode.py
index 551e8f4cd68..4860274ea3e 100644
--- a/src/black/mode.py
+++ b/src/black/mode.py
@@ -264,6 +264,7 @@ class Preview(Enum):
     hug_comparator = auto()
     parenthesize_tuple_in_yield = auto()
     fmt_off_class_blank_lines = auto()
+    remove_redundant_generator_parentheses = auto()
 
 
 UNSTABLE_FEATURES: set[Preview] = {
diff --git a/src/black/resources/black.schema.json b/src/black/resources/black.schema.json
index 64db190152f..acf5bb0f62a 100644
--- a/src/black/resources/black.schema.json
+++ b/src/black/resources/black.schema.json
@@ -93,7 +93,8 @@
           "pyi_blank_line_after_function_docstring",
           "hug_comparator",
           "parenthesize_tuple_in_yield",
-          "fmt_off_class_blank_lines"
+          "fmt_off_class_blank_lines",
+          "remove_redundant_generator_parentheses"
         ]
       },
       "description": "Enable specific features included in the `--unstable` style. Requires `--preview`. No compatibility guarantees are provided on the behavior or existence of any unstable features."
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/tests/data/cases/preview_redundant_generator_parentheses.py b/tests/data/cases/preview_redundant_generator_parentheses.py
new file mode 100644
index 00000000000..4def53930c4
--- /dev/null
+++ b/tests/data/cases/preview_redundant_generator_parentheses.py
@@ -0,0 +1,93 @@
+# flags: --preview
+
+any((x for x in items))
+service.consume((item for group in groups for item in group if item))
+factory((item for item in iterable))()
+
+((item.is_valid() for item in items))
+(((item.is_valid() for item in items)),)
+[((item.is_valid() for item in items)), ""]
+{"foo": ((item.is_valid() for item in items))}
+outer(inner(((item.is_valid() for item in items))))
+((result := transform(item) for item in items))
+((item async for item in stream()))
+next(((item for item in items)), None)
+consume(generator=((item for item in items)))
+consume(*((item for item in items)))
+
+# Power trailers still require the generator's own parentheses.
+((item for item in items)).send(None)
+((item for item in items))[0]
+((item for item in items)).attribute
+((item for item in items))()
+(item for item in items).send(None)
+(item for item in items)[0]
+(item for item in items).attribute
+(item for item in items)()
+
+any((
+    this_very_long_method_name(obj) or another_long_method_name(obj)
+    for obj in this_iterable
+))
+
+# Existing comment handling may keep the generator parentheses visible.
+any((
+    long_expression_that_exceeds_the_configured_line_length_limit_value  # inline comment
+    for item in iterable
+))
+
+# Parentheses are required when the generator is not the sole argument.
+next((item for item in iterable), None)
+enumerate((item for item in iterable), start=10)
+consume((item for item in iterable),)
+consume(*(item for item in iterable))
+consume(generator=(item for item in iterable))
+
+# output
+
+any(x for x in items)
+service.consume(item for group in groups for item in group if item)
+factory(item for item in iterable)()
+
+(item.is_valid() for item in items)
+((item.is_valid() for item in items),)
+[(item.is_valid() for item in items), ""]
+{"foo": (item.is_valid() for item in items)}
+outer(inner(item.is_valid() for item in items))
+(result := transform(item) for item in items)
+(item async for item in stream())
+next((item for item in items), None)
+consume(generator=(item for item in items))
+consume(*(item for item in items))
+
+# Power trailers still require the generator's own parentheses.
+(item for item in items).send(None)
+(item for item in items)[0]
+(item for item in items).attribute
+(item for item in items)()
+(item for item in items).send(None)
+(item for item in items)[0]
+(item for item in items).attribute
+(item for item in items)()
+
+any(
+    this_very_long_method_name(obj) or another_long_method_name(obj)
+    for obj in this_iterable
+)
+
+# Existing comment handling may keep the generator parentheses visible.
+any(
+    (
+        long_expression_that_exceeds_the_configured_line_length_limit_value  # inline comment
+        for item in iterable
+    )
+)
+
+# Parentheses are required when the generator is not the sole argument.
+next((item for item in iterable), None)
+enumerate((item for item in iterable), start=10)
+consume(
+    (item for item in iterable),
+)
+consume(*(item for item in iterable))
+consume(generator=(item for item in iterable))
```
</details>

---

## psf__black-5386

**18/25** · [PR](https://github.com/psf/black/pull/5386) · [issue #5422](https://github.com/psf/black/issues/5422) · [issue #5379](https://github.com/psf/black/issues/5379) · 1 FAIL_TO_PASS tests

### Issue

Fix ValueError in find_project_root for files on multiple Windows drives (#5379)
Resolves #5379.

    **Description:**
    When passing sources located on completely different Windows drives (e.g., `black C:\app\a.py D:\tmp\b.py`), `find_project_root` computes the common parents of all input paths. Because paths on separate Windows drives have no common `Path` parent, the resulting set intersection is empty. Previously, passing this empty intersection to `max()` caused an unhandled `ValueError` crash.

    This PR fixes the crash by checking if the intersection is empty before calling `max()`. If there is no common base (as is the
  case with files on different drives), it gracefully falls back to using the resolved current working directory (`Path.cwd()`) as
  the base to search for configuration files like `pyproject.toml`.

    **Changes:**
    - Updated `src/black/files.py` to handle an empty parent intersection and fallback to `Path.cwd()`.
    - Added `test_find_project_root_multiple_drives` regression test in `tests/test_black.py` (skipped on non-Windows platforms).
`find_project_root` raises `ValueError` for sources on different Windows drives
<!--
Please make sure that the bug is not already fixed either in newer versions or the
current development version. To confirm this, you have three options:

1. Update Black's version if a newer release exists: `pip install -U black`
2. Install the latest `main` branch directly:
   `pip install "black @ git+https://github.com/psf/black.git"`
3. Or run _Black_ from source on your machine:
   - create a new virtualenv (make sure it's the same Python version);
   - clone this repository;
   - run `pip install -e .[d]`;
   - run `pip install --group tests`
   - make sure it's sane by running `python -m pytest -n auto`; and
   - run `black` like you did last time.
-->

**Describe the bug**

<!-- A clear and concise description of what the bug is. -->
Running Black with source files on different Windows drives fails during project-root detection. `find_project_root` computes the common parents of all input paths and passes the result to `max()`. Absolute POSIX paths always share `/`, but paths on separate Windows drives have no common `Path` parent. The intersection is therefore empty, and `max()` raises `ValueError` during CLI startup.

This appears unrelated to [#5160](https://github.com/psf/black/issues/5160), which involves the VS Code extension and `relpath` behavior with UNC and mapped drives. This failure occurs in `src/black/files.py` when selecting the longest common parent.

**To Reproduce**

On Windows, create or select two Python files on different drives and run:

```sh
pip install black
black C:\work\app\a.py D:\tmp\b.py
```

Observed:

```
Traceback (most recent call last):
 ...
  File "D:\Work\Lib\site-packages\black\__init__.py", line 126, in read_pyproject_toml
    value = find_pyproject_toml(
        ctx.params.get("src", ()), ctx.params.get("stdin_filename", None)
    )
  File "D:\Work\Lib\site-packages\black\files.py", line 102, in find_pyproject_toml
    path_project_root, _ = find_project_root(path_search_start, stdin_filename)
                           ~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "D:\Work\Lib\site-packages\black\files.py", line 78, in find_project_root
    common_base = max(
        set.intersection(*(set(parents) for parents in src_parents)),
        key=lambda path: path.parts,
    )
ValueError: max() iterable argument is empty
```

For these paths, the parent sets are:

```
C:\work\app\a.py -> C:\work\app, C:\work, C:\
D:\tmp\b.py      -> D:\tmp, D:\
intersection     -> empty
```

**Expected behavior**

<!-- A clear and concise description of what you expected to happen. -->
Black should handle sources on different drives without exposing an internal `ValueError`. If a shared project root is required, it should report a clear, actionable CLI error. Formatting sources from a single drive should remain unchanged.

**Environment**

<!-- Please complete the following information: -->

- Black's version: 25.9.0 (compiled: no)
- OS and Python version: Windows / CPython 3.13.9 

**Additional context**

<!-- Add any other context about the problem here. -->
The failure occurs in `_find_project_root_cached` in `src/black/files.py`, which `find_project_root` calls after resolving each input path. On Windows, `Path.resolve()` preserves the drive letter, so paths on separate drives still have no common parent.

The immediate cause is the unguarded `max()` call:

```python
common = set.intersection(*(set(parents) for parents in src_parents))
common_base = max(common, key=lambda path: path.parts)
```

Handling the empty intersection explicitly would prevent the internal exception. Depending on the intended CLI behavior, Black could either return an appropriate fallback root or raise a user-facing error explaining that the inputs are on different drives.

### Files changed by the gold patch

- `CHANGES.md` (+3 / -0)
- `src/black/__init__.py` (+31 / -8)
- `src/black/files.py` (+17 / -10)

### Tests that must pass (names, deduplicated)

- `test_no_common_parent_warns_and_formats`

<details><summary>Gold patch</summary>

```diff
diff --git a/CHANGES.md b/CHANGES.md
index 5e5ba2aa285..2724d76371f 100644
--- a/CHANGES.md
+++ b/CHANGES.md
@@ -112,6 +112,9 @@
 
 <!-- Changes to how Black can be configured -->
 
+- Fall back to the default configuration, with a warning, when the given sources share
+  no common project root (for example, they are on different drives on Windows) instead
+  of crashing (#5386)
 - Fix `find_project_root` returning a stale cached result when `--code` is used from
   different working directories in the same process. The CWD fallback (used when no
   `srcs` are given) is now resolved before the `lru_cache` key is computed, so each
diff --git a/src/black/__init__.py b/src/black/__init__.py
index e719f817f8f..8b830d869e1 100644
--- a/src/black/__init__.py
+++ b/src/black/__init__.py
@@ -618,6 +618,20 @@ def main(
     )
     ctx.obj["root"] = root
 
+    if (
+        code is None
+        and root is None
+        and not quiet
+        and ctx.get_parameter_source("config") != ParameterSource.COMMANDLINE
+    ):
+        err(
+            "No project root could be identified: the given sources share no"
+            " common parent directory (for example, they are on different"
+            " drives). Black will use its default configuration. Pass"
+            " --config to select a configuration file or --quiet to silence"
+            " this warning."
+        )
+
     if verbose:
         if root:
             out(
@@ -717,7 +731,6 @@ def main(
             lines=lines,
         )
     else:
-        assert root is not None  # root is only None if code is not None
         try:
             sources = get_sources(
                 root=root,
@@ -778,7 +791,7 @@ def main(
 
 def get_sources(
     *,
-    root: Path,
+    root: Path | None,
     src: tuple[str, ...],
     quiet: bool,
     verbose: bool,
@@ -792,7 +805,9 @@ def get_sources(
     """Compute the set of files to be formatted."""
     sources: set[Path] = set()
 
-    assert root.is_absolute(), f"INTERNAL ERROR: `root` must be absolute but is {root}"
+    assert (
+        root is None or root.is_absolute()
+    ), f"INTERNAL ERROR: `root` must be absolute but is {root}"
     using_default_exclude = exclude is None
     exclude = re_compile_maybe_verbose(DEFAULT_EXCLUDES) if exclude is None else exclude
     gitignore: dict[Path, GitIgnoreSpec] | None = None
@@ -812,14 +827,22 @@ def get_sources(
             path = Path(s)
             is_stdin = False
 
+        # When the sources share no common parent, there is no project root.
+        # Fall back to a per-source root so that exclusion, symlink, and
+        # gitignore handling still work for each source independently.
+        if root is None:
+            src_root = path.resolve() if path.is_dir() else path.resolve().parent
+        else:
+            src_root = root
+
         # Compare the logic here to the logic in `gen_python_files`.
         if is_stdin or path.is_file():
-            if resolves_outside_root_or_cannot_stat(path, root, report):
+            if resolves_outside_root_or_cannot_stat(path, src_root, report):
                 if verbose:
                     out(f'Skipping invalid source: "{path}"', fg="red")
                 continue
 
-            root_relative_path = best_effort_relative_path(path, root).as_posix()
+            root_relative_path = best_effort_relative_path(path, src_root).as_posix()
             root_relative_path = "/" + root_relative_path
 
             # Hard-exclude any files that matches the `--force-exclude` regex.
@@ -841,19 +864,19 @@ def get_sources(
                 out(f'Found input source: "{path}"', fg="blue")
             sources.add(path)
         elif path.is_dir():
-            path = root / (path.resolve().relative_to(root))
+            path = src_root / (path.resolve().relative_to(src_root))
             if verbose:
                 out(f'Found input source directory: "{path}"', fg="blue")
 
             if using_default_exclude:
                 gitignore = {
-                    root: root_gitignore,
+                    src_root: root_gitignore,
                     path: get_gitignore(path),
                 }
             sources.update(
                 gen_python_files(
                     path.iterdir(),
-                    root,
+                    src_root,
                     include,
                     exclude,
                     extend_exclude,
diff --git a/src/black/files.py b/src/black/files.py
index 0e2d077b519..71e23241cb8 100644
--- a/src/black/files.py
+++ b/src/black/files.py
@@ -44,7 +44,7 @@ def _cached_resolve(path: Path) -> Path:
 
 def find_project_root(
     srcs: Sequence[str | Path], stdin_filename: str | None = None
-) -> tuple[Path, str]:
+) -> tuple[Path | None, str | None]:
     """Return a directory containing .git, .hg, or pyproject.toml.
 
     pyproject.toml files are only considered if they contain a [tool.black]
@@ -56,6 +56,10 @@ def find_project_root(
     If no directory in the tree contains a marker that would specify it's the
     project root, the root of the file system is returned.
 
+    If the sources share no common parent at all (for example, they live on
+    different drives on Windows), there is no project root and
+    ``(None, None)`` is returned.
+
     Returns a two-tuple with the first element as the project root path and
     the second element as a string describing the method by which the
     project root was discovered.
@@ -74,7 +78,7 @@ def find_project_root(
 
 
 @lru_cache
-def _find_project_root_cached(srcs: tuple[str, ...]) -> tuple[Path, str]:
+def _find_project_root_cached(srcs: tuple[str, ...]) -> tuple[Path | None, str | None]:
     path_srcs = [Path(src) for src in srcs]
 
     # A list of lists of parents for each 'src'. 'src' is included as a
@@ -83,10 +87,10 @@ def _find_project_root_cached(srcs: tuple[str, ...]) -> tuple[Path, str]:
         list(path.parents) + ([path] if path.is_dir() else []) for path in path_srcs
     ]
 
-    common_base = max(
-        set.intersection(*(set(parents) for parents in src_parents)),
-        key=lambda path: path.parts,
-    )
+    common_parents = set.intersection(*(set(parents) for parents in src_parents))
+    if not common_parents:
+        return None, None
+    common_base = max(common_parents, key=lambda path: path.parts)
 
     for directory in (common_base, *common_base.parents):
         if (directory / ".git").exists():
@@ -108,9 +112,10 @@ def find_pyproject_toml(
 ) -> str | None:
     """Find the absolute filepath to a pyproject.toml if it exists"""
     path_project_root, _ = find_project_root(path_search_start, stdin_filename)
-    path_pyproject_toml = path_project_root / "pyproject.toml"
-    if path_pyproject_toml.is_file():
-        return str(path_pyproject_toml)
+    if path_project_root is not None:
+        path_pyproject_toml = path_project_root / "pyproject.toml"
+        if path_pyproject_toml.is_file():
+            return str(path_pyproject_toml)
 
     try:
         path_user_pyproject_toml = find_user_pyproject_toml()
@@ -246,8 +251,10 @@ def find_user_pyproject_toml() -> Path:
 
 
 @lru_cache
-def get_gitignore(root: Path) -> GitIgnoreSpec:
+def get_gitignore(root: Path | None) -> GitIgnoreSpec:
     """Return a GitIgnoreSpec matching gitignore content if present."""
+    if root is None:
+        return GitIgnoreSpec.from_lines([])
     gitignore = root / ".gitignore"
     lines: list[str] = []
     if gitignore.is_file():
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/tests/test_black.py b/tests/test_black.py
index cd54765292e..8ea00a8542d 100644
--- a/tests/test_black.py
+++ b/tests/test_black.py
@@ -1925,6 +1925,98 @@ def test_find_project_root(self) -> None:
                 (src_dir.resolve(), "pyproject.toml"),
             )
 
+    @pytest.mark.incompatible_with_mypyc
+    def test_find_project_root_no_common_parent(self) -> None:
+        # Absolute vs relative paths share no parents on any platform. That is
+        # the same empty-intersection situation as C:\... and D:\... on Windows.
+        cases: list[tuple[str, ...]] = [("/work/app/a.py", "tmp/b.py")]
+        if sys.platform == "win32":
+            cases.append((r"C:\work\app\a.py", r"D:\tmp\b.py"))
+
+        for srcs in cases:
+            parents = [set(Path(src).parents) for src in srcs]
+            self.assertFalse(set.intersection(*parents))
+            with self.subTest(srcs=srcs):
+                self.assertEqual(
+                    black.files._find_project_root_cached(srcs), (None, None)
+                )
+
+        if sys.platform == "win32":
+            self.assertEqual(
+                black.find_project_root((r"C:\work\app\a.py", r"D:\tmp\b.py")),
+                (None, None),
+            )
+
+    @pytest.mark.incompatible_with_mypyc
+    @patch("black.files.find_user_pyproject_toml")
+    def test_find_pyproject_toml_no_common_parent(
+        self, find_user_pyproject_toml: MagicMock
+    ) -> None:
+        if system() != "Windows":
+            return
+
+        with TemporaryDirectory() as workspace:
+            user_config = Path(workspace) / "user-pyproject.toml"
+            user_config.write_text("[tool.black]", encoding="utf-8")
+            find_user_pyproject_toml.return_value = user_config
+
+            # Sources on different drives share no project root, so the
+            # project-level config is skipped and the user-level config
+            # applies, same as when the project root has no pyproject.toml.
+            result = black.files.find_pyproject_toml(
+                (r"C:\work\app\a.py", r"D:\tmp\b.py")
+            )
+            self.assertEqual(result, str(user_config))
+
+    @pytest.mark.incompatible_with_mypyc
+    @patch("black.files.find_user_pyproject_toml")
+    @patch("black.files.find_project_root")
+    @patch("black.find_project_root")
+    def test_no_common_parent_warns_and_formats(
+        self,
+        find_project_root: MagicMock,
+        files_find_project_root: MagicMock,
+        find_user_pyproject_toml: MagicMock,
+    ) -> None:
+        find_project_root.return_value = (None, None)
+        files_find_project_root.return_value = (None, None)
+        find_user_pyproject_toml.return_value = Path("does-not-exist")
+
+        runner = BlackRunner()
+        with TemporaryDirectory() as workspace:
+            root = Path(workspace)
+            project1 = root / "project1"
+            project2 = root / "project2"
+            project1.mkdir()
+            project2.mkdir()
+            (project1 / "a.py").write_text("x=1\n", encoding="utf-8")
+            (project2 / "b.py").write_text("y=2\n", encoding="utf-8")
+
+            def invoke(args: list[str]) -> tuple[int, str]:
+                for path in (project1 / "a.py", project2 / "b.py"):
+                    path.write_text("x=1\n", encoding="utf-8")
+                result = runner.invoke(
+                    black.main,
+                    [str(project1), str(project2), *args],
+                    catch_exceptions=False,
+                )
+                return result.exit_code, result.output
+
+            exit_code, output = invoke([])
+            assert exit_code == 0, output
+            assert "No project root could be identified" in output
+            assert "reformatted" in output
+            assert "a.py" in output and "b.py" in output
+
+            exit_code, output = invoke(["--quiet"])
+            assert exit_code == 0, output
+            assert "No project root could be identified" not in output
+
+            exit_code, output = invoke(["--config", str(THIS_DIR / "empty.toml")])
+            assert exit_code == 0, output
+            assert "No project root could be identified" not in output
+            assert "reformatted" in output
+
     @patch(
         "black.files.find_user_pyproject_toml",
     )
```
</details>

---

## psf__black-5408

**19/25** · [PR](https://github.com/psf/black/pull/5408) · [issue #3526](https://github.com/psf/black/issues/3526) · 2 FAIL_TO_PASS tests

### Issue

Github action could return number of changed/formatted files
**Is your feature request related to a problem? Please describe.**

The official psf/black GitHub Action does not seem to return information on its run. Other related actions such as https://github.com/rickstaa/action-black returned an is_formatted flag which could be used by subsequent steps.

If you use an "open pull request" action after the formatting step, and if black did format any file, then you can automatically open a pull request and when approved the formatted code would be committed to the original branch.

Without such a parameter if you queue an "open a pull request" github action after a "format with black" action, you would ALWAYS have a pull request, even if no files had been changed

**Describe the solution you'd like**

Have psf/black return a status or a number of files it changed.

**Describe alternatives you've considered**

none

**Additional context**

Sample workflow in github actions:

```
name: Formatting

on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]

jobs:
  black:
    runs-on: ubuntu-latest
    name: Format python
    
    steps:
    - name: Check out
      uses: actions/checkout@v3

    - name: Set up Python 3.10
      uses: actions/setup-python@v4
      with:
        python-version: "3.10"

    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install black autopep8 isort
        if [ -f requirements.txt ]; then pip install -r requirements.txt; fi

    - name: Format with black
      id: action_black
      uses: psf/black@stable
      with:
        options: "--verbose"
        src: "./src"

    - name: Create Pull Request
      uses: peter-evans/create-pull-request@v4
      with:
        title: "Format Python code with psf/black push"
        commit-message: "Format Python code with psf/black"
        body: "Format Python code with psf/black"
        base: main
        branch: black-format-github-action
        delete-branch: true

```

### Files changed by the gold patch

- `CHANGES.md` (+2 / -0)
- `action.yml` (+14 / -0)
- `docs/integrations/github_actions.md` (+15 / -0)
- `src/black/__init__.py` (+5 / -0)
- `src/black/report.py` (+15 / -0)

### Tests that must pass (names, deduplicated)

- `test_github_output_in_cli`
- `test_report_write_github_outputs`

<details><summary>Gold patch</summary>

```diff
diff --git a/CHANGES.md b/CHANGES.md
index 87449b2e1ca..e52875157bc 100644
--- a/CHANGES.md
+++ b/CHANGES.md
@@ -220,6 +220,8 @@
 
 - Support PEP 440 version specifiers in `tool.black.required-version` for the GitHub
   Action (#5399)
+- Add outputs (`is_formatted`, `change_count`, `same_count`, `failure_count`) to GitHub
+  Action runs (#5408)
 
 ### Documentation
 
diff --git a/action.yml b/action.yml
index 733fcbebac0..dc35ddaaaad 100644
--- a/action.yml
+++ b/action.yml
@@ -41,6 +41,19 @@ inputs:
       keeping GitHub Actions logs clean when using --diff or --check.
     required: false
     default: ""
+outputs:
+  is_formatted:
+    description: "Whether any files were reformatted or would be reformatted."
+    value: ${{ steps.black.outputs.is_formatted }}
+  change_count:
+    description: "Number of files that were reformatted or would be reformatted."
+    value: ${{ steps.black.outputs.change_count }}
+  same_count:
+    description: "Number of files that were left unchanged."
+    value: ${{ steps.black.outputs.same_count }}
+  failure_count:
+    description: "Number of files that failed to reformat."
+    value: ${{ steps.black.outputs.failure_count }}
 branding:
   color: "black"
   icon: "check-circle"
@@ -48,6 +61,7 @@ runs:
   using: composite
   steps:
     - name: black
+      id: black
       run: |
         # Even when black fails, do not close the shell
         set +e
diff --git a/docs/integrations/github_actions.md b/docs/integrations/github_actions.md
index 5f540e05741..dff2ec97bbe 100644
--- a/docs/integrations/github_actions.md
+++ b/docs/integrations/github_actions.md
@@ -114,3 +114,18 @@ Here's an example configuration:
     jupyter: true
     version: "21.5b1"
 ```
+
+### Outputs
+
+The action provides the following outputs:
+
+- `is_formatted`: Set to `"true"` if any files were reformatted (or in `--check` mode,
+  would be reformatted); `"false"` otherwise. This can be used to run subsequent steps
+  conditionally (for example, auto-committing formatted changes).
+- `change_count`: Number of files that were reformatted (or would be reformatted in
+  `--check` mode).
+- `same_count`: Number of files that were left unchanged.
+- `failure_count`: Number of files that failed to reformat.
+
+These outputs are only accessible if the action version as well as `with.version` are
+both 26.10+.
diff --git a/src/black/__init__.py b/src/black/__init__.py
index e719f817f8f..70554567054 100644
--- a/src/black/__init__.py
+++ b/src/black/__init__.py
@@ -1,5 +1,6 @@
 import io
 import json
+import os
 import platform
 import re
 import sys
@@ -739,6 +740,8 @@ def main(
                 out("No Python files are present to be formatted. Nothing to do 😴")
             if "-" in src:
                 sys.stdout.write(sys.stdin.read())
+            if "GITHUB_OUTPUT" in os.environ:
+                report.write_github_outputs(Path(os.environ["GITHUB_OUTPUT"]))
             ctx.exit(0)
 
         if len(sources) == 1:
@@ -773,6 +776,8 @@ def main(
         out(error_msg if report.return_code else "All done! ✨ 🍰 ✨")
         if code is None:
             click.echo(str(report), err=True)
+    if "GITHUB_OUTPUT" in os.environ:
+        report.write_github_outputs(Path(os.environ["GITHUB_OUTPUT"]))
     ctx.exit(report.return_code)
 
 
diff --git a/src/black/report.py b/src/black/report.py
index 2736529c8e1..777cb43361c 100644
--- a/src/black/report.py
+++ b/src/black/report.py
@@ -120,3 +120,18 @@ def __str__(self) -> str:
                 style_output(f"{self.failure_count} file{s} {failed}", fg="red")
             )
         return ", ".join(report) + "."
+
+    def write_github_outputs(self, output: Path) -> None:
+        is_formatted = "true" if self.change_count > 0 else "false"
+        _outputs = {
+            "is_formatted": is_formatted,
+            "change_count": str(self.change_count),
+            "same_count": str(self.same_count),
+            "failure_count": str(self.failure_count),
+        }
+        try:
+            with output.open("a", encoding="utf-8") as f:
+                for k, v in _outputs.items():
+                    f.write(f"{k}={v}\n")
+        except OSError:
+            pass
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/tests/test_black.py b/tests/test_black.py
index cd54765292e..efccb8452b2 100644
--- a/tests/test_black.py
+++ b/tests/test_black.py
@@ -743,6 +743,50 @@ def err(msg: str, **kwargs: Any) -> None:
                 " files would fail to reformat.",
             )
 
+    def test_report_write_github_outputs(self) -> None:
+        with TemporaryDirectory() as workspace:
+            output_file = Path(workspace) / "github_output"
+            report = Report()
+            report.done(Path("f1"), black.Changed.NO)
+            report.write_github_outputs(output_file)
+            content = output_file.read_text(encoding="utf-8")
+            self.assertIn("is_formatted=false\n", content)
+            self.assertIn("change_count=0\n", content)
+            self.assertIn("same_count=1\n", content)
+            self.assertIn("failure_count=0\n", content)
+
+            output_file.unlink()
+            report_quiet = Report(quiet=True)
+            report_quiet.done(Path("f2"), black.Changed.YES)
+            report_quiet.write_github_outputs(output_file)
+            content_quiet = output_file.read_text(encoding="utf-8")
+            self.assertIn("is_formatted=true\n", content_quiet)
+            self.assertIn("change_count=1\n", content_quiet)
+
+    def test_github_output_in_cli(self) -> None:
+        with TemporaryDirectory() as workspace:
+            output_file = Path(workspace) / "github_output"
+            src = Path(workspace) / "test.py"
+            src.write_text("x = 1\n", encoding="utf-8")
+            with patch.dict(os.environ, {"GITHUB_OUTPUT": str(output_file)}):
+                self.invokeBlack([str(src)])
+            content = output_file.read_text(encoding="utf-8")
+            self.assertIn("is_formatted=false\n", content)
+
+            output_file.unlink()
+            src.write_text("x =   1\n", encoding="utf-8")
+            with patch.dict(os.environ, {"GITHUB_OUTPUT": str(output_file)}):
+                self.invokeBlack([str(src), "--quiet"])
+            content = output_file.read_text(encoding="utf-8")
+            self.assertIn("is_formatted=true\n", content)
+
+            output_file.unlink()
+            src.write_text("x =   1\n", encoding="utf-8")
+            with patch.dict(os.environ, {"GITHUB_OUTPUT": str(output_file)}):
+                self.invokeBlack([str(src), "--check"], exit_code=1)
+            content = output_file.read_text(encoding="utf-8")
+            self.assertIn("is_formatted=true\n", content)
+
     def test_report_normal(self) -> None:
         report = black.Report()
         out_lines = []
```
</details>

---

## psf__black-5411

**20/25** · [PR](https://github.com/psf/black/pull/5411) · [issue #2516](https://github.com/psf/black/issues/2516) · 3 FAIL_TO_PASS tests

### Issue

Running in Jupyter Notebook raises 'OutStream' object has no attribute 'buffer'
**Describe the bug**

When running the function `reformat_code` (and code provided as a string) inside a Jupyter Notebook (or `ipython`), it raises the following exception:

```python
Traceback (most recent call last):
  File "C:\Python37-32\lib\site-packages\black\__init__.py", line 585, in reformat_code
    content=content, fast=fast, write_back=write_back, mode=mode
  File "C:\Python37-32\lib\site-packages\black\__init__.py", line 843, in format_stdin_to_stdout
    sys.stdout.buffer, encoding=encoding, newline=newline, write_through=True
AttributeError: 'OutStream' object has no attribute 'buffer'
error: cannot format <string>: 'OutStream' object has no attribute 'buffer'
```

We can find many similar issue on Github, including [this one](https://github.com/Yelp/mrjob/issues/1441#issuecomment-249267658), which 
contains the following analysis:

> looks like stdout and stderr are ipykernel.iostream.OutStream objects, which don't have a buffer attribute, but which seem perfectly happy to accept bytes as well as unicode.

This function works perfectly fine on a regular Python file.


**To Reproduce**

You can check the following notebook:
https://colab.research.google.com/gist/jfthuong/f8732badb0e19b2109e6e05346ca3b1b/formatting-code-with-black.ipynb

Or create a new one, with:
1. `from black import WriteBack, Report, Mode, reformat_code, TargetVersion, reformat_one`
2. Create a string with some source code
3. Create `WriteBack`, `Report`, and `Mode` objects
4. Call the function `reformat_code`

```python
reformat_code(
    content=code, fast=True, write_back=write_back, mode=mode, report=report
)
```

**Expected behavior**

Reformatted code. But error is raised.

**Environment:**

- Version: black-21.9b0
- OS and Python version: Jupyter on Windows / Linux (Python 3.7)

**Does this bug also happen on main?**

Yes.

(installed with `!pip install -q git+https://github.com/psf/black/`).

**Additional context**

Inside Jupyter Notebook / ipython. OK from "regular" python `.py` file.

### Files changed by the gold patch

- `CHANGES.md` (+2 / -0)
- `src/black/__init__.py` (+34 / -13)
- `src/black/files.py` (+3 / -4)

### Tests that must pass (names, deduplicated)

- `test_format_file_in_place_diff_without_stdout_buffer`
- `test_format_stdin_to_stdout_without_buffer`
- `test_reformat_code_without_stdout_buffer`

<details><summary>Gold patch</summary>

```diff
diff --git a/CHANGES.md b/CHANGES.md
index ed7e1c3931d..07fe66f5610 100644
--- a/CHANGES.md
+++ b/CHANGES.md
@@ -200,6 +200,8 @@
 <!-- Changes to Black's terminal output and error messages -->
 
 - Report parser failures using editor-friendly `path:line:column` locations (#5237)
+- Fix crash when writing formatted code or diffs to a `sys.stdout` that has no `buffer`
+  attribute, such as in Jupyter notebooks (#5411)
 
 ### _Blackd_
 
diff --git a/src/black/__init__.py b/src/black/__init__.py
index 8e834ed8315..db118f42d69 100644
--- a/src/black/__init__.py
+++ b/src/black/__init__.py
@@ -1023,15 +1023,12 @@ def format_file_in_place(
             diff_contents = color_diff(diff_contents)
 
         with lock or nullcontext():
-            f = io.TextIOWrapper(
-                sys.stdout.buffer,
+            _write_to_stdout(
+                diff_contents,
                 encoding=encoding,
                 newline=newline,
-                write_through=True,
+                wrap_for_windows=True,
             )
-            f = wrap_stream_for_windows(f)
-            f.write(diff_contents)
-            f.detach()
 
     return True
 
@@ -1068,14 +1065,11 @@ def format_stdin_to_stdout(
         return False
 
     finally:
-        f = io.TextIOWrapper(
-            sys.stdout.buffer, encoding=encoding, newline=newline, write_through=True
-        )
         if write_back == WriteBack.YES:
             # Make sure there's a newline after the content
             if dst and dst[-1] != "\n" and dst[-1] != "\r":
                 dst += newline
-            f.write(dst)
+            _write_to_stdout(dst, encoding=encoding, newline=newline)
         elif write_back in (WriteBack.DIFF, WriteBack.COLOR_DIFF):
             now = datetime.now(timezone.utc)
             src_name = f"STDIN\t{then}"
@@ -1083,9 +1077,36 @@ def format_stdin_to_stdout(
             d = diff(src, dst, src_name, dst_name)
             if write_back == WriteBack.COLOR_DIFF:
                 d = color_diff(d)
-                f = wrap_stream_for_windows(f)
-            f.write(d)
-        f.detach()
+            _write_to_stdout(
+                d,
+                encoding=encoding,
+                newline=newline,
+                wrap_for_windows=write_back == WriteBack.COLOR_DIFF,
+            )
+
+
+def _write_to_stdout(
+    content: str, *, encoding: str, newline: str, wrap_for_windows: bool = False
+) -> None:
+    """Write `content` to stdout with the given encoding and newline translation.
+
+    `sys.stdout` isn't required to expose the underlying binary `buffer` (for
+    example ipykernel's `OutStream` in Jupyter doesn't). In that case the stream
+    only accepts text, so the newline translation that `io.TextIOWrapper` would do
+    is applied here and the encoding is left to the stream itself.
+    """
+    buffer = getattr(sys.stdout, "buffer", None)
+    if buffer is None:
+        if newline != "\n":
+            content = content.replace("\n", newline)
+        stream = wrap_stream_for_windows(sys.stdout) if wrap_for_windows else sys.stdout
+        stream.write(content)
+        return
+
+    f = io.TextIOWrapper(buffer, encoding=encoding, newline=newline, write_through=True)
+    wrapped = wrap_stream_for_windows(f) if wrap_for_windows else f
+    wrapped.write(content)
+    f.detach()
 
 
 def check_stability_and_equivalence(
diff --git a/src/black/files.py b/src/black/files.py
index cdc93b3a947..0e2d077b519 100644
--- a/src/black/files.py
+++ b/src/black/files.py
@@ -1,11 +1,10 @@
-import io
 import os
 import sys
 from collections.abc import Iterable, Iterator, Sequence
 from functools import lru_cache
 from pathlib import Path
 from re import Pattern
-from typing import TYPE_CHECKING, Any, Union
+from typing import TYPE_CHECKING, Any, TextIO, Union
 
 from mypy_extensions import mypyc_attr
 from packaging.specifiers import InvalidSpecifier, Specifier, SpecifierSet
@@ -415,8 +414,8 @@ def gen_python_files(
 
 
 def wrap_stream_for_windows(
-    f: io.TextIOWrapper,
-) -> Union[io.TextIOWrapper, "colorama.AnsiToWin32"]:
+    f: TextIO,
+) -> Union[TextIO, "colorama.AnsiToWin32"]:
     """
     Wrap stream with colorama's wrap_stream so colors are shown on Windows.
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/tests/test_black.py b/tests/test_black.py
index 06fc3d455c6..7ea3e78d02a 100644
--- a/tests/test_black.py
+++ b/tests/test_black.py
@@ -1473,6 +1473,73 @@ def get_output(*args: Any, **kwargs: Any) -> io.StringIO | io.TextIOWrapper:
                     output.getvalue() == expected
                 ), f"incorrect formatting of {repr(content)}"
 
+    def test_format_stdin_to_stdout_without_buffer(self) -> None:
+        # Text streams aren't required to expose `.buffer` (e.g. ipykernel's
+        # OutStream in Jupyter), see #2516.
+        src = "print ( 'hello' )"
+        for write_back, expected in (
+            (black.WriteBack.YES, 'print("hello")\n'),
+            (black.WriteBack.CHECK, ""),
+            (black.WriteBack.NO, ""),
+        ):
+            output = io.StringIO()
+            assert not hasattr(output, "buffer")
+            with patch("sys.stdout", output):
+                changed = black.format_stdin_to_stdout(
+                    fast=True, content=src, write_back=write_back, mode=DEFAULT_MODE
+                )
+            self.assertTrue(changed)
+            self.assertEqual(output.getvalue(), expected)
+            self.assertFalse(output.closed)
+
+        for write_back in (black.WriteBack.DIFF, black.WriteBack.COLOR_DIFF):
+            output = io.StringIO()
+            with patch("sys.stdout", output):
+                black.format_stdin_to_stdout(
+                    fast=True, content=src, write_back=write_back, mode=DEFAULT_MODE
+                )
+            actual = unstyle(output.getvalue())
+            self.assertIn("-print ( 'hello' )\n", actual)
+            self.assertIn('+print("hello")\n', actual)
+            self.assertFalse(output.closed)
+
+    def test_reformat_code_without_stdout_buffer(self) -> None:
+        output = io.StringIO()
+        report = MagicMock()
+        with patch("sys.stdout", output):
+            black.reformat_code(
+                "x = ( 1 )",
+                fast=True,
+                write_back=black.WriteBack.YES,
+                mode=DEFAULT_MODE,
+                report=report,
+            )
+        self.assertEqual(output.getvalue(), "x = 1\n")
+        report.failed.assert_not_called()
+
+    def test_format_file_in_place_diff_without_stdout_buffer(self) -> None:
+        for nl in ("\n", "\r\n"):
+            with TemporaryDirectory() as workspace:
+                test_file = Path(workspace) / "test.py"
+                test_file.write_bytes(f"x = ( 1 ){nl}".encode())
+                output = io.StringIO(newline="")
+                with patch("sys.stdout", output):
+                    changed = black.format_file_in_place(
+                        test_file,
+                        fast=True,
+                        mode=DEFAULT_MODE,
+                        write_back=black.WriteBack.DIFF,
+                    )
+                self.assertTrue(changed)
+                actual = output.getvalue()
+                self.assertIn(f"-x = ( 1 ){nl}", actual)
+                self.assertIn(f"+x = 1{nl}", actual)
+                if nl == "\n":
+                    self.assertNotIn("\r\n", actual)
+                self.assertFalse(output.closed)
+                # The file itself is left untouched.
+                self.assertEqual(test_file.read_bytes(), f"x = ( 1 ){nl}".encode())
+
     def test_cli_unstable(self) -> None:
         self.invokeBlack(["--unstable", "-c", "0"], exit_code=0)
         self.invokeBlack(["--preview", "-c", "0"], exit_code=0)
```
</details>

---

## psf__black-5416

**21/25** · [PR](https://github.com/psf/black/pull/5416) · [issue #3080](https://github.com/psf/black/issues/3080) · 1 FAIL_TO_PASS tests

### Issue

unnecessary parentheses in unpacking aren't removed
**Describe the style change**

Replace `(foo)` with `foo` when unpacking, where `foo` is an expression.

**Examples in the current _Black_ style**

```python
points = [(1, 2), (3, 4)]
for (x), (y) in points:
    print(x, y)
```

**Desired style**

```python
points = [(1, 2), (3, 4)]
for x, y in points:
    print(x, y)
```

### Files changed by the gold patch

- `CHANGES.md` (+2 / -0)
- `docs/the_black_code_style/future_style.md` (+24 / -0)
- `src/black/linegen.py` (+67 / -0)
- `src/black/mode.py` (+1 / -0)
- `src/black/resources/black.schema.json` (+2 / -1)

### Tests that must pass (names, deduplicated)

- `test_simple_format`

<details><summary>Gold patch</summary>

```diff
diff --git a/CHANGES.md b/CHANGES.md
index 5e5ba2aa285..970177905f6 100644
--- a/CHANGES.md
+++ b/CHANGES.md
@@ -82,6 +82,8 @@
 
 <!-- Changes that affect Black's preview style -->
 
+- Remove redundant parentheses around individual variables in unpacking targets (for
+  example `for (x), (y) in points:` becomes `for x, y in points:`) (#5416)
 - Normalize uppercase `T` prefixes on t-strings to lowercase under `--preview` (#5425)
 - Remove redundant parentheses around generator expressions (#5304, #5369)
 - Preserve two blank lines before a top-level class starting inside a `# fmt: off` block
diff --git a/docs/the_black_code_style/future_style.md b/docs/the_black_code_style/future_style.md
index f36d1e2c0f5..9e9f16ecb1b 100644
--- a/docs/the_black_code_style/future_style.md
+++ b/docs/the_black_code_style/future_style.md
@@ -49,6 +49,30 @@ Currently, the following features are included in the preview style:
   definition starts inside a `# fmt: off` block after an import.
 - `remove_redundant_generator_parentheses`: Remove redundant parentheses around
   generator expressions. ([see below](labels/remove-redundant-generator-parentheses))
+- `remove_redundant_unpacking_parentheses`: Remove redundant parentheses around
+  individual variables in unpacking targets.
+  ([see below](labels/remove-redundant-unpacking-parentheses))
+
+(labels/remove-redundant-unpacking-parentheses)=
+
+### Redundant unpacking parentheses
+
+Black removes extra parentheses around individual variables in unpacking targets, such
+as in assignments, `for` loops, `with` statements, and `del` statements:
+
+```python
+# Before
+for (x), (y) in points:
+    pass
+
+(x), (y) = point
+
+# After (with --preview)
+for x, y in points:
+    pass
+
+x, y = point
+```
 
 (labels/remove-redundant-generator-parentheses)=
 
diff --git a/src/black/linegen.py b/src/black/linegen.py
index b6a0ddf66a3..50cbe65b3a5 100644
--- a/src/black/linegen.py
+++ b/src/black/linegen.py
@@ -705,6 +705,13 @@ def visit_tstring(self, node: Node) -> Iterator[Line]:
         # yield from self.visit_default(node)
 
     def visit_comp_for(self, node: Node) -> Iterator[Line]:
+        if (
+            Preview.remove_redundant_unpacking_parentheses in self.mode
+            and len(node.children) > 1
+        ):
+            _normalize_unpacking_targets(
+                node.children[1], mode=self.mode, features=self.features
+            )
         if Preview.wrap_comprehension_in in self.mode:
             normalize_invisible_parens(
                 node, parens_after={"in"}, mode=self.mode, features=self.features
@@ -1679,6 +1686,38 @@ def _has_redundant_generator_parentheses(node: LN) -> bool:
     return is_generator(middle) or _has_redundant_generator_parentheses(middle)
 
 
+def _normalize_unpacking_targets(
+    node: LN,
+    mode: Mode,
+    features: Collection[Feature],
+) -> None:
+    """Remove redundant parentheses from individual elements in unpacking targets."""
+    if not isinstance(node, Node):
+        return
+
+    if node.type in (
+        syms.exprlist,
+        syms.testlist_star_expr,
+        syms.testlist_gexp,
+        syms.testlist,
+        syms.listmaker,
+        syms.star_expr,
+    ):
+        for child in node.children:
+            if child.type == syms.atom and not _is_atom_multiline(child):
+                maybe_make_parens_invisible_in_atom(
+                    child,
+                    parent=node,
+                    mode=mode,
+                    features=features,
+                )
+            _normalize_unpacking_targets(child, mode=mode, features=features)
+    elif node.type == syms.atom:
+        for child in node.children:
+            if isinstance(child, Node):
+                _normalize_unpacking_targets(child, mode=mode, features=features)
+
+
 def normalize_invisible_parens(
     node: Node, parens_after: set[str], *, mode: Mode, features: Collection[Feature]
 ) -> None:
@@ -1695,6 +1734,34 @@ def normalize_invisible_parens(
             # This `node` has a prefix with `# fmt: off`, don't mess with parens.
             return
 
+    if Preview.remove_redundant_unpacking_parentheses in mode:
+        if node.type in (syms.for_stmt, syms.comp_for, syms.old_comp_for):
+            if len(node.children) > 1:
+                _normalize_unpacking_targets(
+                    node.children[1], mode=mode, features=features
+                )
+        elif node.type == syms.expr_stmt:
+            equal_indices = [
+                i for i, child in enumerate(node.children) if child.type == token.EQUAL
+            ]
+            if equal_indices:
+                for child in node.children[: equal_indices[-1]]:
+                    if child.type != token.EQUAL:
+                        _normalize_unpacking_targets(
+                            child, mode=mode, features=features
+                        )
+        elif node.type == syms.del_stmt:
+            if len(node.children) > 1:
+                _normalize_unpacking_targets(
+                    node.children[1], mode=mode, features=features
+                )
+        elif node.type == syms.with_stmt:
+            for child in node.children:
+                if child.type == syms.asexpr_test and len(child.children) > 2:
+                    _normalize_unpacking_targets(
+                        child.children[2], mode=mode, features=features
+                    )
+
     # The multiple context managers grammar has a different pattern, thus this is
     # separate from the for-loop below. This possibly wraps them in invisible parens,
     # and later will be removed in remove_with_parens when needed.
diff --git a/src/black/mode.py b/src/black/mode.py
index e5e62415790..242842d8b73 100644
--- a/src/black/mode.py
+++ b/src/black/mode.py
@@ -266,6 +266,7 @@ class Preview(Enum):
     fmt_off_class_blank_lines = auto()
     remove_redundant_generator_parentheses = auto()
     normalize_tstring_prefix = auto()
+    remove_redundant_unpacking_parentheses = auto()
 
 
 UNSTABLE_FEATURES: set[Preview] = {
diff --git a/src/black/resources/black.schema.json b/src/black/resources/black.schema.json
index 155ead0ef22..d6fcd7eb848 100644
--- a/src/black/resources/black.schema.json
+++ b/src/black/resources/black.schema.json
@@ -95,7 +95,8 @@
           "parenthesize_tuple_in_yield",
           "fmt_off_class_blank_lines",
           "remove_redundant_generator_parentheses",
-          "normalize_tstring_prefix"
+          "normalize_tstring_prefix",
+          "remove_redundant_unpacking_parentheses"
         ]
       },
       "description": "Enable specific features included in the `--unstable` style. Requires `--preview`. No compatibility guarantees are provided on the behavior or existence of any unstable features."
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/tests/data/cases/preview_unpacking_parens.py b/tests/data/cases/preview_unpacking_parens.py
new file mode 100644
index 00000000000..589d2733fed
--- /dev/null
+++ b/tests/data/cases/preview_unpacking_parens.py
@@ -0,0 +1,174 @@
+# flags: --preview
+# Unnecessary parentheses in unpacking should be removed.
+
+# For loop unpacking
+points = [(1, 2), (3, 4)]
+for (x), (y) in points:
+    print(x, y)
+
+for (x), y in points:
+    pass
+
+for x, (y) in points:
+    pass
+
+for ((a), (b)) in points:
+    pass
+
+for ((a), b) in points:
+    pass
+
+for (a, (b)) in points:
+    pass
+
+for (((a)), ((b))) in points:
+    pass
+
+for a, (b, c) in points:
+    pass
+
+for a, (b,) in points:
+    pass
+
+for a, [b, c] in points:
+    pass
+
+for a, ((b, c)) in points:
+    pass
+
+for a, ((b)) in points:
+    pass
+
+# Assignment unpacking
+(a), (b) = 1, 2
+a, (b) = 1, 2
+[(a), (b)] = [1, 2]
+((a), (b)) = 1, 2
+((a), b) = 1, 2
+(a, (b)) = 1, 2
+(((a)), ((b))) = 1, 2
+a, (b, (c)) = 1, (2, 3)
+(a), (b) = (c), (d) = 1, 2
+((a), (b)) = ((c), (d)) = 1, 2
+
+# Comprehensions
+[x for (a), (b) in points]
+[x for ((a), (b)) in points]
+{k: v for (a), (b) in points}
+(x for (a), (b) in points)
+{x for (a), (b) in points}
+
+# With statement
+with lock as ((a), (b)):
+    pass
+
+with c1 as ((a), (b)), c2 as ((c), (d)):
+    pass
+
+with lock as ((a), b):
+    pass
+
+with lock as (a, (b)):
+    pass
+
+# Delete statement
+del (a), (b)
+del ((a), (b))
+del ((a), b)
+del (a, (b))
+del (((a)), ((b)))
+
+# Star expression unpacking
+*(a), (b) = 1, 2
+*((a)), (b) = 1, 2
+*(((a))), ((b)) = 1, 2
+(*((a)), (b)) = 1, 2
+(*((a)), ((b))) = 1, 2
+
+# output
+
+# Unnecessary parentheses in unpacking should be removed.
+
+# For loop unpacking
+points = [(1, 2), (3, 4)]
+for x, y in points:
+    print(x, y)
+
+for x, y in points:
+    pass
+
+for x, y in points:
+    pass
+
+for a, b in points:
+    pass
+
+for a, b in points:
+    pass
+
+for a, b in points:
+    pass
+
+for a, b in points:
+    pass
+
+for a, (b, c) in points:
+    pass
+
+for a, (b,) in points:
+    pass
+
+for a, [b, c] in points:
+    pass
+
+for a, (b, c) in points:
+    pass
+
+for a, b in points:
+    pass
+
+# Assignment unpacking
+a, b = 1, 2
+a, b = 1, 2
+[a, b] = [1, 2]
+a, b = 1, 2
+a, b = 1, 2
+a, b = 1, 2
+a, b = 1, 2
+a, (b, c) = 1, (2, 3)
+a, b = c, d = 1, 2
+a, b = (c, d) = 1, 2
+
+# Comprehensions
+[x for a, b in points]
+[x for (a, b) in points]
+{k: v for a, b in points}
+(x for a, b in points)
+{x for a, b in points}
+
+# With statement
+with lock as (a, b):
+    pass
+
+with c1 as (a, b), c2 as (c, d):
+    pass
+
+with lock as (a, b):
+    pass
+
+with lock as (a, b):
+    pass
+
+# Delete statement
+del a, b
+del (a, b)
+del (a, b)
+del (a, b)
+del (a, b)
+
+# Star expression unpacking
+*a, b = 1, 2
+*a, b = 1, 2
+*a, b = 1, 2
+*a, b = 1, 2
+*a, b = 1, 2
```
</details>

---

## scrapy__scrapy-8189

**22/25** · [PR](https://github.com/scrapy/scrapy/pull/8189) · [issue #2186](https://github.com/scrapy/scrapy/issues/2186) · 113 FAIL_TO_PASS tests · ⚠️ **tests import a name introduced by the fix**

### Issue

move more functions from scrapy.utils.url to w3lib
Hey,

What do you think about moving `add_http_if_no_scheme` and `escape_ajax` functions to w3lib?

### Files changed by the gold patch

- `scrapy/core/downloader/handlers/_base_streaming.py` (+2 / -2)
- `scrapy/core/downloader/handlers/http11.py` (+2 / -2)
- `scrapy/utils/url.py` (+19 / -8)

### Tests that must pass (names, deduplicated)

- `test__is_filesystem_path`
- `test_add_http_if_no_scheme`
- `test_add_http_if_no_scheme_deprecated`
- `test_add_http_if_no_scheme_not_deprecated`
- `test_credentials`
- `test_default_ports`
- `test_default_ports_creds_off`
- `test_default_ports_keep`
- `test_fragments`
- `test_guess_scheme`
- `test_noop`
- `test_origin_only`
- `test_path`
- `test_url_has_any_extension`
- `test_url_is_from_any_domain`
- `test_url_is_from_spider`
- `test_url_is_from_spider_with_allowed_domains`
- `test_url_is_from_spider_with_allowed_domains_property`

<details><summary>Gold patch</summary>

```diff
diff --git a/scrapy/core/downloader/handlers/_base_streaming.py b/scrapy/core/downloader/handlers/_base_streaming.py
index 6e4dd687061..c7f4c82d8d1 100644
--- a/scrapy/core/downloader/handlers/_base_streaming.py
+++ b/scrapy/core/downloader/handlers/_base_streaming.py
@@ -23,7 +23,7 @@
     normalize_bind_address,
 )
 from scrapy.utils.asyncio import is_asyncio_available
-from scrapy.utils.url import add_http_if_no_scheme
+from scrapy.utils.url import _add_http_if_no_scheme
 
 from ._base_http import BaseHttpDownloadHandler
 
@@ -286,7 +286,7 @@ def _extract_proxy(request: Request) -> tuple[str | None, str | None]:
         proxy: str | None = request.meta.get("proxy")
         if not proxy:
             return None, None
-        proxy = add_http_if_no_scheme(proxy)
+        proxy = _add_http_if_no_scheme(proxy)
         auth_header: bytes | None = request.headers.get(b"Proxy-Authorization")
         return proxy, auth_header.decode("ascii") if auth_header else None
 
diff --git a/scrapy/core/downloader/handlers/http11.py b/scrapy/core/downloader/handlers/http11.py
index f3eaa3411ec..37b27c8a699 100644
--- a/scrapy/core/downloader/handlers/http11.py
+++ b/scrapy/core/downloader/handlers/http11.py
@@ -62,7 +62,7 @@
 from scrapy.utils.deprecate import warn_on_deprecated_spider_attribute
 from scrapy.utils.httpobj import urlparse_cached
 from scrapy.utils.python import to_bytes, to_unicode
-from scrapy.utils.url import add_http_if_no_scheme
+from scrapy.utils.url import _add_http_if_no_scheme
 
 from ._base_http import BaseHttpDownloadHandler
 
@@ -456,7 +456,7 @@ def _get_agent(self, request: Request, timeout: float) -> Agent:
         bindaddress = normalize_bind_address(bindaddress)
         proxy = request.meta.get("proxy")
         if proxy:
-            proxy = add_http_if_no_scheme(proxy)
+            proxy = _add_http_if_no_scheme(proxy)
             proxy_parsed = urlparse(proxy)
             proxy_host = proxy_parsed.hostname
             proxy_port = proxy_parsed.port
diff --git a/scrapy/utils/url.py b/scrapy/utils/url.py
index 21ef4aac7ed..de2e38728c3 100644
--- a/scrapy/utils/url.py
+++ b/scrapy/utils/url.py
@@ -10,8 +10,11 @@
 from typing import TYPE_CHECKING, TypeAlias
 from urllib.parse import ParseResult, urlparse, urlunparse
 
+import w3lib.url
 from w3lib.url import any_to_uri, parse_url
 
+from scrapy.exceptions import ScrapyDeprecationWarning
+
 if TYPE_CHECKING:
     from collections.abc import Iterable
 
@@ -57,17 +60,25 @@ def url_has_any_extension(url: UrlT, extensions: Iterable[str]) -> bool:
     return any(lowercase_path.endswith(ext) for ext in extensions)
 
 
-def add_http_if_no_scheme(url: str) -> str:
-    """Add http as the default scheme if it is missing from the url."""
-    match = re.match(r"^\w+://", url, flags=re.IGNORECASE)
-    if not match:
-        parts = urlparse(url)
-        scheme = "http:" if parts.netloc else "http://"
+def _add_http_if_no_scheme(url: str) -> str:
+    if not re.match(r"^\w+://", url, flags=re.IGNORECASE):
+        scheme = "http:" if urlparse(url).netloc else "http://"
         url = scheme + url
-
     return url
 
 
+def add_http_if_no_scheme(url: str) -> str:
+    """Add http as the default scheme if it is missing from the url."""
+    if hasattr(w3lib.url, "add_http_if_no_scheme"):
+        warnings.warn(
+            "scrapy.utils.url.add_http_if_no_scheme() is deprecated, use "
+            "w3lib.url.add_http_if_no_scheme() instead.",
+            ScrapyDeprecationWarning,
+            stacklevel=2,
+        )
+    return _add_http_if_no_scheme(url)
+
+
 def _is_posix_path(string: str) -> bool:
     return bool(
         re.match(
@@ -115,7 +126,7 @@ def guess_scheme(url: str) -> str:
     http:// otherwise."""
     if _is_filesystem_path(url):
         return any_to_uri(url)
-    return add_http_if_no_scheme(url)
+    return _add_http_if_no_scheme(url)
 
 
 def strip_url(
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/tests/test_utils_url.py b/tests/test_utils_url.py
index 403fd61763f..830d691e2aa 100644
--- a/tests/test_utils_url.py
+++ b/tests/test_utils_url.py
@@ -1,10 +1,13 @@
 from __future__ import annotations
 
 import pytest
+import w3lib.url
 
+from scrapy.exceptions import ScrapyDeprecationWarning
 from scrapy.linkextractors import IGNORED_EXTENSIONS
 from scrapy.spiders import Spider
 from scrapy.utils.url import (
+    _add_http_if_no_scheme,
     _is_filesystem_path,
     add_http_if_no_scheme,
     guess_scheme,
@@ -162,7 +165,22 @@ def test_url_has_any_extension(url: str, expected: bool) -> None:
     ],
 )
 def test_add_http_if_no_scheme(url: str, expected: str) -> None:
-    assert add_http_if_no_scheme(url) == expected
+    assert _add_http_if_no_scheme(url) == expected
+
+
+def test_add_http_if_no_scheme_deprecated(monkeypatch: pytest.MonkeyPatch) -> None:
+    monkeypatch.setattr(
+        w3lib.url, "add_http_if_no_scheme", lambda url: url, raising=False
+    )
+    with pytest.warns(
+        ScrapyDeprecationWarning, match="use w3lib.url.add_http_if_no_scheme"
+    ):
+        assert add_http_if_no_scheme("www.example.com") == "http://www.example.com"
+
+
+def test_add_http_if_no_scheme_not_deprecated(monkeypatch: pytest.MonkeyPatch) -> None:
+    monkeypatch.delattr(w3lib.url, "add_http_if_no_scheme", raising=False)
+    assert add_http_if_no_scheme("www.example.com") == "http://www.example.com"
 
 
 @pytest.mark.parametrize(
```
</details>

---

## scrapy__scrapy-8193

**23/25** · [PR](https://github.com/scrapy/scrapy/pull/8193) · [issue #939](https://github.com/scrapy/scrapy/issues/939) · 8 FAIL_TO_PASS tests

### Issue

Media pipeline problem
I think contrib.pipline.media.MediaPipeline should be add config to disable downloaded cache, when I use ImagePipeline to scrapy full site image, alway make memory leak. The media download should be make unique by user not scrapy framwork.

### Files changed by the gold patch

- `docs/topics/media-pipeline.rst` (+19 / -0)
- `docs/topics/optimize.rst` (+3 / -0)
- `scrapy/pipelines/media.py` (+6 / -2)
- `scrapy/settings/default_settings.py` (+3 / -0)

### Tests that must pass (names, deduplicated)

- `test_cache_size`

<details><summary>Gold patch</summary>

```diff
diff --git a/docs/topics/media-pipeline.rst b/docs/topics/media-pipeline.rst
index 362480515b8..5e9c99ca6d2 100644
--- a/docs/topics/media-pipeline.rst
+++ b/docs/topics/media-pipeline.rst
@@ -563,6 +563,25 @@ To handle media redirections, set this setting to ``True``:
 
     MEDIA_ALLOW_REDIRECTS = True
 
+Limiting the result cache
+-------------------------
+
+.. setting:: MEDIA_CACHE_SIZE
+
+Media pipelines remember the outcome of every media request they handle, so
+that a file referenced by several items is downloaded once. By default every
+outcome is kept for the whole crawl, which takes about 600 bytes per distinct
+media URL.
+
+.. versionadded:: VERSION
+
+To cap that memory, set :setting:`MEDIA_CACHE_SIZE` to the number of most
+recently used outcomes to keep, or to ``0`` to keep none:
+
+.. code-block:: python
+
+    MEDIA_CACHE_SIZE = 10000
+
 .. _topics-media-pipeline-override:
 
 Extending the Media Pipelines
diff --git a/docs/topics/optimize.rst b/docs/topics/optimize.rst
index 1dbb5949f32..e82d2f258b0 100644
--- a/docs/topics/optimize.rst
+++ b/docs/topics/optimize.rst
@@ -295,6 +295,9 @@ Lowering memory usage
 
     -   Set :setting:`JOBDIR` to offload all scheduled requests to disk.
 
+-   Set :setting:`MEDIA_CACHE_SIZE` if you use :ref:`media pipelines
+    <topics-media-pipeline>`.
+
 -   Be on the lookout for :ref:`memory leaks <topics-leaks>`.
 
 
diff --git a/scrapy/pipelines/media.py b/scrapy/pipelines/media.py
index 41b2e17c95f..58cc21246bc 100644
--- a/scrapy/pipelines/media.py
+++ b/scrapy/pipelines/media.py
@@ -5,7 +5,7 @@
 import logging
 import warnings
 from abc import ABC, abstractmethod
-from collections import defaultdict
+from collections import OrderedDict, defaultdict
 from typing import TYPE_CHECKING, Any, Literal, TypeAlias, TypedDict, cast
 
 from twisted.internet.defer import Deferred, DeferredList
@@ -80,7 +80,7 @@ class SpiderInfo:
         def __init__(self, spider: Spider):
             self.spider: Spider = spider
             self.downloading: set[bytes] = set()
-            self.downloaded: dict[bytes, FileInfo | Failure] = {}
+            self.downloaded: OrderedDict[bytes, FileInfo | Failure] = OrderedDict()
             self.waiting: defaultdict[bytes, list[Deferred[FileInfo]]] = defaultdict(
                 list
             )
@@ -111,6 +111,7 @@ def __init__(
             resolve("MEDIA_ALLOW_REDIRECTS"), False
         )
         self._handle_statuses(self.allow_redirects)
+        self._cache_size: int = settings.getint(resolve("MEDIA_CACHE_SIZE"))
 
     def _handle_statuses(self, allow_redirects: bool) -> None:
         self.handle_httpstatus_list = None
@@ -177,6 +178,7 @@ async def _process_request(
         # Return cached result if request was already seen
         if fp in info.downloaded:
             await _process_pending_io()
+            info.downloaded.move_to_end(fp)
             cached_result = info.downloaded[fp]
             if isinstance(cached_result, Failure):
                 if eb:
@@ -276,6 +278,8 @@ def _cache_result_and_execute_waiters(
 
         info.downloading.remove(fp)
         info.downloaded[fp] = result  # cache result
+        if 0 <= self._cache_size < len(info.downloaded):
+            info.downloaded.popitem(last=False)
         for wad in info.waiting.pop(fp):
             if isinstance(result, Failure):
                 wad.errback(result)
diff --git a/scrapy/settings/default_settings.py b/scrapy/settings/default_settings.py
index 0c0216ed2cd..e619811e65d 100644
--- a/scrapy/settings/default_settings.py
+++ b/scrapy/settings/default_settings.py
@@ -158,6 +158,7 @@
     "MAIL_SSL",
     "MAIL_TLS",
     "MAIL_USER",
+    "MEDIA_CACHE_SIZE",
     "MEMDEBUG_ENABLED",
     "MEMUSAGE_CHECK_INTERVAL_SECONDS",
     "MEMUSAGE_ENABLED",
@@ -488,6 +489,8 @@
 MAIL_SSL = False
 MAIL_TLS = False
 
+MEDIA_CACHE_SIZE = -1
+
 MEMDEBUG_ENABLED = False  # enable memory debugging
 
 MEMUSAGE_ENABLED = True
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/tests/test_pipeline_media.py b/tests/test_pipeline_media.py
index fd377fb7f3b..09d470cc5a1 100644
--- a/tests/test_pipeline_media.py
+++ b/tests/test_pipeline_media.py
@@ -455,6 +455,32 @@ async def rsp2_func():
         new_item = await self.pipe.process_item(item)
         assert new_item["results"] == [(True, {}), (True, {})]
 
+    @pytest.mark.parametrize(
+        ("size", "prefixed", "cached_urls"),
+        [
+            (2, False, ["http://url1", "http://url3"]),
+            (2, True, ["http://url1", "http://url3"]),
+            (0, False, []),
+            (-1, False, ["http://url2", "http://url1", "http://url3"]),
+        ],
+    )
+    @coroutine_test
+    async def test_cache_size(self, size: int, prefixed: bool, cached_urls: list[str]):
+        key = "MEDIA_CACHE_SIZE"
+        if prefixed:
+            key = f"{self.pipeline_class.__name__.upper()}_{key}"
+        crawler = get_crawler(DefaultSpider, {key: size})
+        crawler.spider = crawler._create_spider()
+        crawler.engine = MagicMock(download_async=mocked_download_func)
+        pipe = build_from_crawler(self.pipeline_class, crawler)
+        pipe.open_spider()
+        for url in ["http://url1", "http://url2", "http://url1", "http://url3"]:
+            req = Request(url, meta={"response": Response(url)})
+            await pipe.process_item({"requests": req})
+        assert list(pipe.spiderinfo.downloaded) == [
+            self.fingerprint(Request(url)) for url in cached_urls
+        ]
+
     @coroutine_test
     async def test_use_media_to_download_result(self):
         req = Request("http://url", meta={"result": "ITSME"})
```
</details>

---

## scrapy__scrapy-8204

**24/25** · [PR](https://github.com/scrapy/scrapy/pull/8204) · [issue #1241](https://github.com/scrapy/scrapy/issues/1241) · 6 FAIL_TO_PASS tests

### Issue

Provide a way to propagate an exit code from a Spider
I think we need a way to propagate the exit code from the Spider.

Based on: #1231

### Files changed by the gold patch

- `docs/topics/stats.rst` (+12 / -0)
- `scrapy/commands/__init__.py` (+2 / -2)
- `scrapy/core/engine.py` (+15 / -5)
- `scrapy/core/scraper.py` (+3 / -1)
- `scrapy/crawler.py` (+4 / -2)
- `scrapy/exceptions.py` (+8 / -2)
- `scrapy/extensions/closespider.py` (+5 / -3)
- `scrapy/extensions/corestats.py` (+2 / -1)

### Tests that must pass (names, deduplicated)

- `test_close_spider_error_exit_code`
- `test_closespider_errorcount`
- `test_core_stats_default_stats_collector`
- `test_crawler`
- `test_crawler_change_close_reason_and_error_on_idle`
- `test_crawler_change_close_reason_on_idle`

<details><summary>Gold patch</summary>

```diff
diff --git a/docs/topics/stats.rst b/docs/topics/stats.rst
index fe4f82da75e..6d61f283b61 100644
--- a/docs/topics/stats.rst
+++ b/docs/topics/stats.rst
@@ -317,6 +317,18 @@ one per actual value of the placeholder.
 
     Set by :class:`~scrapy.extensions.corestats.CoreStats`.
 
+.. stat:: finish_reason_error
+
+``finish_reason_error``
+    Boolean indicating whether :stat:`finish_reason` denotes a failed crawl.
+    It matches the *error* argument of the :signal:`spider_closed` signal, and
+    :ref:`commands <topics-commands>` such as :command:`crawl` use it to
+    decide their process exit code.
+
+    .. versionadded:: VERSION
+
+    Set by :class:`~scrapy.extensions.corestats.CoreStats`.
+
 .. stat:: finish_time
 
 ``finish_time``
diff --git a/scrapy/commands/__init__.py b/scrapy/commands/__init__.py
index 632e2a27a48..9dc2d3f7d86 100644
--- a/scrapy/commands/__init__.py
+++ b/scrapy/commands/__init__.py
@@ -244,8 +244,8 @@ def _run_crawler(
         self.crawler_process.crawl(crawler, **opts.spargs)
         self.crawler_process.start()
         if self.crawler_process.bootstrap_failed or crawler.stats.get_value(
-            "finish_reason"
-        ) in {"closespider_errorcount", "start_error"}:
+            "finish_reason_error", False
+        ):
             self.exitcode = 1
 
     def _warn_if_feeds_unused(self, sender: Crawler, **kwargs: Any) -> None:
diff --git a/scrapy/core/engine.py b/scrapy/core/engine.py
index 162f03c0cdb..b86fe233db9 100644
--- a/scrapy/core/engine.py
+++ b/scrapy/core/engine.py
@@ -350,7 +350,9 @@ def close(self) -> Deferred[None]:  # pragma: no cover
         )
         return deferred_from_coro(self.close_async())
 
-    async def close_async(self, *, reason: str = "shutdown") -> None:
+    async def close_async(
+        self, *, reason: str = "shutdown", error: bool = False
+    ) -> None:
         """
         Gracefully close the execution engine.
         If it has already been started, stop it. In all cases, close the spider and the downloader.
@@ -359,7 +361,8 @@ async def close_async(self, *, reason: str = "shutdown") -> None:
             await self.stop_async()  # will also close spider and downloader
             return
         if self.spider is not None:
-            await self.close_spider_async(reason=reason)  # will also close downloader
+            # will also close downloader
+            await self.close_spider_async(reason=reason, error=error)
         else:
             self.downloader.close()
         if self._state not in (_EngineState.STOPPING, _EngineState.STOPPED):
@@ -385,7 +388,9 @@ async def _process_start_next(self) -> None:
         except CloseSpider as exception:
             self._start = None
             _schedule_coro(
-                self.close_spider_async(reason=exception.reason or "cancelled")
+                self.close_spider_async(
+                    reason=exception.reason or "cancelled", error=exception.error
+                )
             )
         except Exception as exception:
             self._start = None
@@ -719,9 +724,12 @@ def _spider_idle(self) -> None:
             return
         if self.spider_is_idle():
             default_reason = "start_error" if self._start_error else "finished"
-            ex = detected_ex.get(CloseSpider, CloseSpider(reason=default_reason))
+            ex = detected_ex.get(
+                CloseSpider,
+                CloseSpider(reason=default_reason, error=self._start_error),
+            )
             assert isinstance(ex, CloseSpider)  # typing
-            _schedule_coro(self.close_spider_async(reason=ex.reason))
+            _schedule_coro(self.close_spider_async(reason=ex.reason, error=ex.error))
 
     def close_spider(
         self,
@@ -769,6 +777,7 @@ async def close_spider_async(  # noqa: PLR0912, PLR0915
         *,
         reason: str = "cancelled",
         mode: _StopMode = "graceful",
+        error: bool = False,
     ) -> None:
         """Close (cancel) spider and clear all its outstanding requests.
 
@@ -825,6 +834,7 @@ async def close_spider_async(  # noqa: PLR0912, PLR0915
                 signal=signals.spider_closed,
                 spider=spider,
                 reason=reason,
+                error=error,
             )
         except Exception:
             logger.exception(
diff --git a/scrapy/core/scraper.py b/scrapy/core/scraper.py
index 6c68fc65a4b..08eff6ead10 100644
--- a/scrapy/core/scraper.py
+++ b/scrapy/core/scraper.py
@@ -366,7 +366,9 @@ def handle_spider_error(
         exc = _failure.value
         if isinstance(exc, CloseSpider):
             _schedule_coro(
-                self.crawler.engine.close_spider_async(reason=exc.reason or "cancelled")
+                self.crawler.engine.close_spider_async(
+                    reason=exc.reason or "cancelled", error=exc.error
+                )
             )
             return
         logkws = self.logformatter.spider_error(
diff --git a/scrapy/crawler.py b/scrapy/crawler.py
index 0ff45b3e72b..723f70fc181 100644
--- a/scrapy/crawler.py
+++ b/scrapy/crawler.py
@@ -302,7 +302,9 @@ def crawl(self, *args: Any, **kwargs: Any) -> Generator[Deferred[Any], Any, None
             try:
                 yield deferred_from_coro(self.engine.open_spider_async())
             except CloseSpider as exc:
-                yield deferred_from_coro(self.engine.close_async(reason=exc.reason))
+                yield deferred_from_coro(
+                    self.engine.close_async(reason=exc.reason, error=exc.error)
+                )
             else:
                 yield deferred_from_coro(self.engine.start_async())
         except Exception:
@@ -336,7 +338,7 @@ async def crawl_async(self, *args: Any, **kwargs: Any) -> None:
             try:
                 await self.engine.open_spider_async()
             except CloseSpider as exc:
-                await self.engine.close_async(reason=exc.reason)
+                await self.engine.close_async(reason=exc.reason, error=exc.error)
             else:
                 await self.engine.start_async()
         except Exception:
diff --git a/scrapy/exceptions.py b/scrapy/exceptions.py
index db8b5d19652..aa6203f7a84 100644
--- a/scrapy/exceptions.py
+++ b/scrapy/exceptions.py
@@ -66,7 +66,12 @@ class CloseSpider(Exception):
     .. versionchanged:: VERSION
        Added support for raising it from a downloader middleware.
 
-    *reason* is a string with the reason for closing.
+    .. versionadded:: VERSION
+       The *error* parameter.
+
+    *reason* is a string with the reason for closing. *error*, keyword-only,
+    marks the crawl as failed, which commands such as :command:`crawl` report
+    through their process exit code.
 
     For example:
 
@@ -77,9 +82,10 @@ def parse_page(self, response):
                 raise CloseSpider("bandwidth_exceeded")
     """
 
-    def __init__(self, reason: str = "cancelled"):
+    def __init__(self, reason: str = "cancelled", *, error: bool = False):
         super().__init__()
         self.reason = reason
+        self.error = error
 
 
 class StopDownload(Exception):
diff --git a/scrapy/extensions/closespider.py b/scrapy/extensions/closespider.py
index 1c0f0a4d2d8..3ae2858ac12 100644
--- a/scrapy/extensions/closespider.py
+++ b/scrapy/extensions/closespider.py
@@ -87,7 +87,7 @@ def from_crawler(cls, crawler: Crawler) -> Self:
     def error_count(self, failure: Failure, response: Response, spider: Spider) -> None:
         self.counter["errorcount"] += 1
         if self.counter["errorcount"] == self.close_on["errorcount"]:
-            self._close_spider("closespider_errorcount")
+            self._close_spider("closespider_errorcount", error=True)
 
     def page_count(self, response: Response, request: Request, spider: Spider) -> None:
         self.counter["pagecount"] += 1
@@ -144,5 +144,7 @@ def _count_items_produced(self) -> None:
             )
             self._close_spider("closespider_timeout_no_item")
 
-    def _close_spider(self, reason: str) -> None:
-        _schedule_coro(self.crawler.engine.close_spider_async(reason=reason))
+    def _close_spider(self, reason: str, *, error: bool = False) -> None:
+        _schedule_coro(
+            self.crawler.engine.close_spider_async(reason=reason, error=error)
+        )
diff --git a/scrapy/extensions/corestats.py b/scrapy/extensions/corestats.py
index b464942afd2..3c92b713a13 100644
--- a/scrapy/extensions/corestats.py
+++ b/scrapy/extensions/corestats.py
@@ -39,7 +39,7 @@ def spider_opened(self, spider: Spider) -> None:
         self._start_time_mono = monotonic()
         self.stats.set_value("start_time", self.start_time)
 
-    def spider_closed(self, spider: Spider, reason: str) -> None:
+    def spider_closed(self, spider: Spider, reason: str, error: bool = False) -> None:
         assert self.start_time is not None
         assert self._start_time_mono is not None
         finish_time, finish_time_mono = datetime.now(tz=timezone.utc), monotonic()
@@ -47,6 +47,7 @@ def spider_closed(self, spider: Spider, reason: str) -> None:
         self.stats.set_value("elapsed_time_seconds", elapsed_time_seconds)
         self.stats.set_value("finish_time", finish_time)
         self.stats.set_value("finish_reason", reason)
+        self.stats.set_value("finish_reason_error", error)
 
     def item_scraped(self, item: Any, spider: Spider) -> None:
         self.stats.inc_value("item_scraped_count")
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/tests/test_closespider.py b/tests/test_closespider.py
index 99c552b8005..d5c029ff464 100644
--- a/tests/test_closespider.py
+++ b/tests/test_closespider.py
@@ -87,6 +87,7 @@ def test_closespider_errorcount(mockserver: MockServer):
     errorcount = crawler.stats.get_value(key)
     assert crawler.stats.get_value("spider_exceptions/count") >= close_on
     assert errorcount >= close_on
+    assert crawler.stats.get_value("finish_reason_error") is True
 
 
 @inline_callbacks_test
diff --git a/tests/test_command_crawl.py b/tests/test_command_crawl.py
index 6719127c20e..050371bd02f 100644
--- a/tests/test_command_crawl.py
+++ b/tests/test_command_crawl.py
@@ -134,6 +134,38 @@ async def start(self):
         assert "Spider closed (closespider_errorcount)" in err
         assert returncode != 0
 
+    def test_close_spider_error_exit_code(self, proj_path: Path) -> None:
+        spider_code = """
+import scrapy
+from scrapy.exceptions import CloseSpider
+
+class MySpider(scrapy.Spider):
+    name = 'myspider'
+
+    async def start(self):
+        raise CloseSpider('payment_required', error=True)
+        yield
+"""
+        returncode, _, err = self.crawl(spider_code, proj_path)
+        assert "Spider closed (payment_required)" in err
+        assert returncode != 0
+
+    def test_close_spider_custom_reason_exit_code(self, proj_path: Path) -> None:
+        spider_code = """
+import scrapy
+from scrapy.exceptions import CloseSpider
+
+class MySpider(scrapy.Spider):
+    name = 'myspider'
+
+    async def start(self):
+        raise CloseSpider('custom_reason')
+        yield
+"""
+        returncode, _, err = self.crawl(spider_code, proj_path)
+        assert "Spider closed (custom_reason)" in err
+        assert returncode == 0
+
     def test_start_error_exit_code(self, proj_path: Path) -> None:
         spider_code = """
 import scrapy
diff --git a/tests/test_engine.py b/tests/test_engine.py
index bd4646ce9c3..fc37b3a3b40 100644
--- a/tests/test_engine.py
+++ b/tests/test_engine.py
@@ -76,6 +76,11 @@ def spider_idle(self):
         raise CloseSpider(reason="custom_reason")
 
 
+class ErrorCloseReasonSpider(ChangeCloseReasonSpider):
+    def spider_idle(self):
+        raise CloseSpider(reason="custom_reason", error=True)
+
+
 class TestEngine(TestEngineBase):
     @coroutine_test
     async def test_crawler(self, mockserver: MockServer) -> None:
@@ -117,7 +122,21 @@ async def test_crawler_change_close_reason_on_idle(
         assert {
             "spider": run.crawler.spider,
             "reason": "custom_reason",
+            "error": False,
+        } == run.signals_caught[signals.spider_closed]
+
+    @coroutine_test
+    async def test_crawler_change_close_reason_and_error_on_idle(
+        self, mockserver: MockServer
+    ) -> None:
+        run = CrawlerRun(ErrorCloseReasonSpider)
+        await run.run(mockserver)
+        assert {
+            "spider": run.crawler.spider,
+            "reason": "custom_reason",
+            "error": True,
         } == run.signals_caught[signals.spider_closed]
+        assert run.crawler.stats.get_value("finish_reason_error") is True
 
     @coroutine_test
     async def test_close_downloader(self):
diff --git a/tests/test_stats.py b/tests/test_stats.py
index 4d7d11a06dd..53b2d09cded 100644
--- a/tests/test_stats.py
+++ b/tests/test_stats.py
@@ -56,6 +56,7 @@ def test_core_stats_default_stats_collector(
             "item_dropped_count": 1,
             "item_dropped_reasons_count/ZeroDivisionError": 1,
             "finish_reason": "finished",
+            "finish_reason_error": False,
             "elapsed_time_seconds": 0.0,
         }
 
diff --git a/tests/utils/bases/engine.py b/tests/utils/bases/engine.py
index a41a83a7b6a..cd34d828dc5 100644
--- a/tests/utils/bases/engine.py
+++ b/tests/utils/bases/engine.py
@@ -158,4 +158,5 @@ def _assert_signals_caught(run: CrawlerRun) -> None:
         assert {
             "spider": run.crawler.spider,
             "reason": "finished",
+            "error": False,
         } == run.signals_caught[signals.spider_closed]
```
</details>

---

## scrapy__scrapy-8224

**25/25** · [PR](https://github.com/scrapy/scrapy/pull/8224) · [issue #6895](https://github.com/scrapy/scrapy/issues/6895) · 6 FAIL_TO_PASS tests

### Issue

request slips through dupefilter after retry/redirect
<!--

Thanks for taking an interest in Scrapy!

If you have a question that starts with "How to...", please see the Scrapy Community page: https://scrapy.org/community/.
The GitHub issue tracker's purpose is to deal with bug reports and feature requests for the project itself.

Keep in mind that by filing an issue, you are expected to comply with Scrapy's Code of Conduct, including treating everyone with respect: https://github.com/scrapy/scrapy/blob/master/CODE_OF_CONDUCT.md

The following is a suggested template to structure your issue, you can find more guidelines at https://doc.scrapy.org/en/latest/contributing.html#reporting-bugs

-->

### Description

With the default configuration urls are sometimes crawled twice.

### Steps to Reproduce

I'm using server.py
```
from __future__ import annotations

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, RedirectResponse


app = FastAPI()


@app.get("/sbn/")
def sbn_slash():
    return RedirectResponse("/bn")


@app.get("/sbn")
def sbn():
    return HTMLResponse("I am /sbn")


first_time = True


@app.get("/bn")
def bn():
    global first_time
    if first_time:
        first_time = False
        return HTMLResponse("not ready", 503)
    else:
        return RedirectResponse("/sbn")
```

And crawler.py
```
import scrapy.crawler


class QuotesSpider(scrapy.Spider):
    name = "quotes"

    async def start(self):
        urls = ["http://localhost/sbn", "http://localhost/sbn/"]
        for url in urls:
            yield scrapy.Request(url=url, callback=self.parse)

    def parse(self, response):
        self.log(f"parsed {response.url}")


if __name__ == "__main__":
    p = scrapy.crawler.CrawlerProcess()
    p.crawl(QuotesSpider)
    p.start()
```

**Expected behavior:** [What you expect to happen]

When I'm running `python crawler.py` I would expect the output:
```
[scrapy.dupefilters] DEBUG: Filtered duplicate request: <GET http://localhost/sbn> - no more duplicates will be shown (see DUPEFILTER_DEBUG to show all duplicates)
[quotes] DEBUG: parsed http://localhost/sbn
```

**Actual behavior:** [What actually happens]
The first time this runs, I'm actually getting:
```
[quotes] DEBUG: parsed http://localhost/sbn
[quotes] DEBUG: parsed http://localhost/sbn
```

**Reproduces how often:** [What percentage of the time does it reproduce?]
reliably reproducible

### Versions

Scrapy       : 2.13.2
lxml         : 5.4.0
libxml2      : 2.13.8
cssselect    : 1.3.0
parsel       : 1.10.0
w3lib        : 2.3.1
Twisted      : 25.5.0
Python       : 3.12.3 (main, May 26 2025, 18:50:19) [GCC 13.3.0]
pyOpenSSL    : 25.1.0 (OpenSSL 3.5.0 8 Apr 2025)
cryptography : 45.0.4
Platform     : Linux-6.11.0-26-generic-x86_64-with-glibc2.39

### Additional context

Any additional information, configuration, data or output from commands that might be necessary to reproduce or understand the issue. Please try not to include screenshots of code or the command line, paste the contents as text instead. You can use [GitHub Flavored Markdown](https://help.github.com/en/articles/creating-and-highlighting-code-blocks) to make the text look better.

### Files changed by the gold patch

- `docs/topics/request-response.rst` (+15 / -0)
- `scrapy/core/engine.py` (+34 / -1)
- `scrapy/core/scheduler.py` (+25 / -1)
- `scrapy/downloadermiddlewares/retry.py` (+1 / -1)

### Tests that must pass (names, deduplicated)

- `test_basic_usage`
- `test_one_retry`
- `test_retry_redirect_dupefilter`
- `test_retry_redirect_dupefilter_legacy_scheduler`
- `test_two_retries`

<details><summary>Gold patch</summary>

```diff
diff --git a/docs/topics/request-response.rst b/docs/topics/request-response.rst
index 39f8701f176..869dbb55ff7 100644
--- a/docs/topics/request-response.rst
+++ b/docs/topics/request-response.rst
@@ -896,6 +896,7 @@ Those are:
 * :reqmeta:`referrer_policy`
 * :reqmeta:`retry_times`
 * :reqmeta:`rule`
+* :reqmeta:`skip_dupefilter_once`
 * :reqmeta:`verbatim_url`
 
 Scrapy components also use meta keys whose name starts with an underscore, such
@@ -1025,6 +1026,20 @@ The meta key is used set retry times per request. When set, the
 :reqmeta:`max_retry_times` meta key takes higher precedence over the
 :setting:`RETRY_TIMES` setting.
 
+.. reqmeta:: skip_dupefilter_once
+
+skip_dupefilter_once
+--------------------
+
+.. versionadded:: VERSION
+
+Set this key to ``True`` to skip :setting:`duplicate filtering
+<DUPEFILTER_CLASS>` for this request. The :ref:`scheduler <topics-scheduler>`
+removes this key, so requests derived from this request, e.g. redirects, are
+filtered as usual.
+
+:func:`~scrapy.downloadermiddlewares.retry.get_retry_request` sets this key.
+
 .. reqmeta:: verbatim_url
 
 verbatim_url
diff --git a/scrapy/core/engine.py b/scrapy/core/engine.py
index f9e9efd9acb..d45024bf39a 100644
--- a/scrapy/core/engine.py
+++ b/scrapy/core/engine.py
@@ -64,6 +64,21 @@
 logger = logging.getLogger(__name__)
 
 
+def _supports_skip_dupefilter_once(scheduler: BaseScheduler) -> bool:
+    # A subclass that overrides enqueue_request() does not inherit support.
+    cls = type(scheduler)
+    owner = next(
+        (
+            c
+            for c in cls.__mro__
+            if "enqueue_request" in vars(c)
+            or "supports_skip_dupefilter_once" in vars(c)
+        ),
+        cls,
+    )
+    return bool(vars(owner).get("supports_skip_dupefilter_once", False))
+
+
 class EngineState(Enum):
     """The lifecycle state of :class:`ExecutionEngine`.
 
@@ -173,6 +188,7 @@ def __init__(
         self.signals: SignalManager = crawler.signals
         self.logformatter: LogFormatter = crawler.logformatter
         self._slot: _Slot | None = None
+        self._warned_skip_dupefilter_once: bool = False
         self.spider: Spider | None = None
         self._state: EngineState = EngineState.CREATED
         # The reason and error flag of a close requested while the spider is
@@ -581,7 +597,24 @@ def _schedule_request(self, request: Request) -> None:
         for _, result in request_scheduled_result:
             if isinstance(result, Failure) and isinstance(result.value, IgnoreRequest):
                 return
-        if not self._slot.scheduler.enqueue_request(request):  # type: ignore[union-attr]
+        assert self._slot is not None
+        if request.meta.get(
+            "skip_dupefilter_once"
+        ) and not _supports_skip_dupefilter_once(self._slot.scheduler):
+            del request.meta["skip_dupefilter_once"]
+            request.dont_filter = True
+            if not self._warned_skip_dupefilter_once:
+                self._warned_skip_dupefilter_once = True
+                warnings.warn(
+                    f"{global_object_name(type(self._slot.scheduler))} does "
+                    f"not set supports_skip_dupefilter_once to True, so "
+                    f"requests with the skip_dupefilter_once meta key get "
+                    f"dont_filter=True instead, which requests derived from "
+                    f"them inherit. Support for such schedulers is deprecated.",
+                    ScrapyDeprecationWarning,
+                    stacklevel=2,
+                )
+        if not self._slot.scheduler.enqueue_request(request):
             self.signals.send_catch_log(
                 signals.request_dropped, request=request, spider=self.spider
             )
diff --git a/scrapy/core/scheduler.py b/scrapy/core/scheduler.py
index ff119215a4d..27b2c4326fd 100644
--- a/scrapy/core/scheduler.py
+++ b/scrapy/core/scheduler.py
@@ -65,6 +65,16 @@ class BaseScheduler(metaclass=BaseSchedulerMeta):
     The methods defined in this class constitute the minimal interface that the Scrapy engine will interact with.
     """
 
+    supports_skip_dupefilter_once: bool = False
+    """Must be ``True``, to declare that :meth:`enqueue_request` handles the
+    :reqmeta:`skip_dupefilter_once` meta key.
+
+    It is not inherited by subclasses that override :meth:`enqueue_request`,
+    which must set it again.
+
+    .. versionadded:: VERSION
+    """
+
     @classmethod
     def from_crawler(cls, crawler: Crawler) -> Self:
         """
@@ -102,12 +112,19 @@ def enqueue_request(self, request: Request) -> bool:
         """
         Process a request received by the engine.
 
+        .. versionchanged:: VERSION
+           Must handle the :reqmeta:`skip_dupefilter_once` meta key.
+
         Return ``True`` if the request is stored correctly, ``False`` otherwise.
 
         If ``False``, the engine will fire a ``request_dropped`` signal, and
         will not make further attempts to schedule the request at a later time.
         For reference, the default Scrapy scheduler returns ``False`` when the
         request is rejected by the dupefilter.
+
+        If the request has the :reqmeta:`skip_dupefilter_once` meta key, remove
+        it and, if it was ``True``, do not filter out the request as a
+        duplicate. See also :attr:`supports_skip_dupefilter_once`.
         """
         raise NotImplementedError
 
@@ -254,6 +271,8 @@ class Scheduler(BaseScheduler):
     which may also write data inside the job directory.
     """
 
+    supports_skip_dupefilter_once = True
+
     @classmethod
     def from_crawler(cls, crawler: Crawler) -> Self:
         dupefilter_cls = load_object(crawler.settings["DUPEFILTER_CLASS"])
@@ -380,7 +399,12 @@ def enqueue_request(self, request: Request) -> bool:
 
         Return ``True`` if the request was stored successfully, ``False`` otherwise.
         """
-        if not request.dont_filter and self.df.request_seen(request):
+        skip_dupefilter = request.meta.pop("skip_dupefilter_once", False)
+        if (
+            not request.dont_filter
+            and not skip_dupefilter
+            and self.df.request_seen(request)
+        ):
             self.df.log(request, self.spider)
             return False
         dqok = self._dqpush(request)
diff --git a/scrapy/downloadermiddlewares/retry.py b/scrapy/downloadermiddlewares/retry.py
index b8eed4da909..01b24f4bd70 100644
--- a/scrapy/downloadermiddlewares/retry.py
+++ b/scrapy/downloadermiddlewares/retry.py
@@ -108,7 +108,7 @@ def parse(self, response):
         )
         new_request: Request = request.copy()
         new_request.meta["retry_times"] = retry_times
-        new_request.dont_filter = True
+        new_request.meta["skip_dupefilter_once"] = True
         if priority_adjust is None:
             priority_adjust = settings.getint("RETRY_PRIORITY_ADJUST")
         new_request.priority = request.priority + priority_adjust
```
</details>

<details><summary>Test patch</summary>

```diff
diff --git a/tests/test_downloadermiddleware_retry.py b/tests/test_downloadermiddleware_retry.py
index a9dc1525a5a..6cae9d4df52 100644
--- a/tests/test_downloadermiddleware_retry.py
+++ b/tests/test_downloadermiddleware_retry.py
@@ -1,17 +1,20 @@
 from __future__ import annotations
 
 import logging
-from typing import Any, cast
+from typing import TYPE_CHECKING, Any, cast
+from urllib.parse import urlencode
 
 import pytest
 from twisted.internet.error import ConnectError, ConnectionDone, ConnectionLost
 
+from scrapy.core.scheduler import Scheduler
 from scrapy.downloadermiddlewares.retry import RetryMiddleware, get_retry_request
 from scrapy.exceptions import (
     CannotResolveHostError,
     DownloadConnectionRefusedError,
     DownloadTimeoutError,
     IgnoreRequest,
+    ScrapyDeprecationWarning,
 )
 from scrapy.http import Request, Response
 from scrapy.settings.default_settings import RETRY_EXCEPTIONS
@@ -19,6 +22,12 @@
 from scrapy.utils.misc import build_from_crawler
 from scrapy.utils.spider import DefaultSpider
 from scrapy.utils.test import get_crawler
+from tests.utils.decorators import coroutine_test
+
+if TYPE_CHECKING:
+    from collections.abc import AsyncIterator
+
+    from tests.mockserver.http import MockServer
 
 
 class TestRetry:
@@ -308,7 +317,7 @@ def test_basic_usage(self, caplog: pytest.LogCaptureFixture) -> None:
             )
         assert isinstance(new_request, Request)
         assert new_request != request
-        assert new_request.dont_filter
+        assert new_request.meta["skip_dupefilter_once"] is True
         expected_retry_times = 1
         assert new_request.meta["retry_times"] == expected_retry_times
         assert new_request.priority == -1
@@ -358,7 +367,7 @@ def test_one_retry(self, caplog: pytest.LogCaptureFixture) -> None:
             )
         assert isinstance(new_request, Request)
         assert new_request != request
-        assert new_request.dont_filter
+        assert new_request.meta["skip_dupefilter_once"] is True
         expected_retry_times = 1
         assert new_request.meta["retry_times"] == expected_retry_times
         assert new_request.priority == -1
@@ -392,7 +401,7 @@ def test_two_retries(self, caplog: pytest.LogCaptureFixture) -> None:
                 )
             assert isinstance(new_request, Request)
             assert new_request != request
-            assert new_request.dont_filter
+            assert new_request.meta["skip_dupefilter_once"] is True
             expected_retry_times = index + 1
             assert new_request.meta["retry_times"] == expected_retry_times
             assert new_request.priority == -expected_retry_times
@@ -751,3 +760,74 @@ def test_custom_stats_key(self):
             f"{stats_key}/reason_count/{expected_reason}",
         ):
             assert spider.crawler.stats.get_value(stat) == 1
+
+
+class _RetryThenRedirectSpider(Spider):
+    """Retries two requests whose retries redirect to an already-seen URL."""
+
+    name = "retry_then_redirect"
+    mockserver: MockServer
+
+    def __init__(self, *args: Any, **kwargs: Any) -> None:
+        super().__init__(*args, **kwargs)
+        self.seen_parsed = 0
+
+    async def start(self) -> AsyncIterator[Any]:
+        seen = self.mockserver.url("/status?n=200")
+        yield Request(seen)
+        for n in range(2):
+            url = self.mockserver.url(
+                "/redirect-to?" + urlencode({"goto": seen, "n": n})
+            )
+            yield Request(
+                url, meta={"dont_redirect": True, "handle_httpstatus_list": [302]}
+            )
+
+    def parse(self, response: Response) -> Request | None:
+        if response.status == 200:
+            self.seen_parsed += 1
+            return None
+        assert response.request is not None
+        request = get_retry_request(response.request, spider=self)
+        assert request is not None
+        del request.meta["dont_redirect"]
+        del request.meta["handle_httpstatus_list"]
+        return request
+
+
+class _LegacyScheduler(Scheduler):
+    supports_skip_dupefilter_once = False
+
+
+class _OverridingScheduler(Scheduler):
+    def enqueue_request(self, request: Request) -> bool:
+        if not request.dont_filter and self.df.request_seen(request):
+            self.df.log(request, self.spider)
+            return False
+        self._mqpush(request)
+        return True
+
+
+@coroutine_test
+async def test_retry_redirect_dupefilter(mockserver: MockServer) -> None:
+    crawler = get_crawler(_RetryThenRedirectSpider)
+    await crawler.crawl_async(mockserver=mockserver)
+    assert crawler.spider is not None
+    assert cast("_RetryThenRedirectSpider", crawler.spider).seen_parsed == 1
+    assert crawler.stats is not None
+    assert crawler.stats.get_value("dupefilter/filtered") == 2
+
+
+@pytest.mark.parametrize("scheduler", [_LegacyScheduler, _OverridingScheduler])
+@coroutine_test
+async def test_retry_redirect_dupefilter_legacy_scheduler(
+    mockserver: MockServer, scheduler: type[Scheduler]
+) -> None:
+    crawler = get_crawler(_RetryThenRedirectSpider, {"SCHEDULER": scheduler})
+    with pytest.warns(
+        ScrapyDeprecationWarning, match="supports_skip_dupefilter_once"
+    ) as record:
+        await crawler.crawl_async(mockserver=mockserver)
+    assert sum("supports_skip_dupefilter_once" in str(w.message) for w in record) == 1
+    assert crawler.spider is not None
+    assert cast("_RetryThenRedirectSpider", crawler.spider).seen_parsed == 3
```
</details>

