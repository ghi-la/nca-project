# PrefectHQ__fastmcp-6077

- repo: `PrefectHQ/fastmcp`, created: 2026-10-27, base_commit: `c3cca93f775d`
- PR: https://github.com/PrefectHQ/fastmcp/pull/6077
- issue: https://github.com/PrefectHQ/fastmcp/issues/5472
- FAIL_TO_PASS: 25 tests, PASS_TO_PASS: 154 tests, collection_error: **no**

## 1. Issue (what the agent sees)

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

## 2. Gold patch

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

## 3. Test patch

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
... (29 more lines, see the PR)
```

## 4. FAIL_TO_PASS tests

- `tests/server/providers/test_prefab_sharing.py::test_csp_domain_order_does_not_change_identity`
- `tests/server/providers/test_prefab_sharing.py::test_legacy_per_tool_uri_preserves_read_content_and_metadata`
- `tests/server/providers/test_prefab_sharing.py::test_listing_does_not_load_html`
- `tests/server/providers/test_prefab_sharing.py::test_matching_tools_share_one_listed_resource`
- `tests/server/providers/test_prefab_sharing.py::test_nested_mounts_share_renderer_and_keep_backend_identity`
- `tests/server/providers/test_prefab_sharing.py::test_renderer_mode_and_version_change_identity`
- `tests/server/providers/test_prefab_sharing.py::test_transformed_resource_configuration_is_readable[False]`
- `tests/server/providers/test_prefab_sharing.py::test_transformed_resource_configuration_is_readable[True]`
- `tests/server/providers/test_prefab_synthesis.py::TestDisplayMetaReachesResource::test_domain_and_prefers_border_reach_resource`
- `tests/server/providers/test_prefab_synthesis.py::TestDisplayMetaReachesResource::test_prefers_border_false_is_preserved`
- `tests/server/providers/test_prefab_synthesis.py::TestDisplayMetaReachesResource::test_unset_fields_stay_off_resource`
- `tests/server/providers/test_prefab_synthesis.py::TestFastMCPAppMounts::test_app_tool_synthesizes_renderer`
- `tests/server/providers/test_prefab_synthesis.py::TestFastMCPAppMounts::test_namespaced_mount_still_synthesizes_resource`
- `tests/server/providers/test_prefab_synthesis.py::TestReadResource::test_renderer_html_is_built_on_read_not_list`
- `tests/server/providers/test_prefab_synthesis.py::TestSharedRendererURIs::test_two_tools_share_uri`
- `tests/server/providers/test_prefab_synthesis.py::TestUserCSPReachesResource::test_all_four_domain_fields_preserved`
- `tests/server/providers/test_prefab_synthesis.py::TestUserCSPReachesResource::test_frame_domains_reach_resource`
- `tests/test_apps.py::TestPrefabAppConfig::test_auto_synthesizes_renderer_resource`
- `tests/test_apps.py::TestPrefabAppConfig::test_equivalent_to_app_true`
- `tests/test_apps_prefab.py::TestAppTrue::test_app_true_synthesizes_renderer_resource`
- `tests/test_apps_prefab.py::TestAppTrue::test_multiple_tools_share_renderer_resource`
- `tests/test_apps_prefab.py::TestAppTrue::test_renderer_resource_has_correct_mime_type`
- `tests/test_apps_prefab.py::TestAppTrue::test_renderer_resource_has_csp`
- `tests/test_apps_prefab.py::TestIntegration::test_tools_list_includes_app_meta`
- `tests/test_fastmcp_app.py::TestComposition::test_ui_synthesizes_renderer_resource`
