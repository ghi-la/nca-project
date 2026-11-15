#!/bin/bash
set -uxo pipefail
cd /testbed
git config --global --add safe.directory /testbed
git status
git -c core.fileMode=false diff 0d7bb12844e9315063e28c68cb5f121f432caca2
git checkout 0d7bb12844e9315063e28c68cb5f121f432caca2 -- tests/resources/test_resource_template.py tests/server/providers/openapi/test_openapi_features.py
git apply -v - <<'EOF_NCA_TEST_PATCH_7f3a'
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
EOF_NCA_TEST_PATCH_7f3a
: '>>>>> Start Test Output'
pytest -rA --color=no -p no:cacheprovider tests/resources/test_resource_template.py tests/server/providers/openapi/test_openapi_features.py
: '>>>>> End Test Output'
git checkout 0d7bb12844e9315063e28c68cb5f121f432caca2 -- tests/resources/test_resource_template.py tests/server/providers/openapi/test_openapi_features.py
