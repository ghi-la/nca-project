#!/bin/bash
set -uxo pipefail
cd /testbed
git config --global --add safe.directory /testbed
git status
git -c core.fileMode=false diff 3fe80e9bc3a2089d9c9116b2398c8603a8a5889b
git checkout 3fe80e9bc3a2089d9c9116b2398c8603a8a5889b -- tests/server/providers/test_addressing.py tests/server/providers/test_prefab_roundtrip.py tests/server/test_hashed_tool_dispatch.py
git apply -v - <<'EOF_NCA_TEST_PATCH_7f3a'
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
EOF_NCA_TEST_PATCH_7f3a
: '>>>>> Start Test Output'
pytest -rA --color=no -p no:cacheprovider tests/apps/test_tool_names.py tests/server/providers/test_addressing.py tests/server/providers/test_prefab_roundtrip.py tests/server/test_hashed_tool_dispatch.py
: '>>>>> End Test Output'
git checkout 3fe80e9bc3a2089d9c9116b2398c8603a8a5889b -- tests/server/providers/test_addressing.py tests/server/providers/test_prefab_roundtrip.py tests/server/test_hashed_tool_dispatch.py
