# PrefectHQ__fastmcp-6187

- repo: `PrefectHQ/fastmcp`, created: 2026-10-31, base_commit: `0d7bb12844e9`
- PR: https://github.com/PrefectHQ/fastmcp/pull/6187
- issue: https://github.com/PrefectHQ/fastmcp/issues/6150
- FAIL_TO_PASS: 15 tests, PASS_TO_PASS: 257 tests, collection_error: **no**

## 1. Issue (what the agent sees)

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

## 2. Gold patch

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

## 3. Test patch

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

## 4. FAIL_TO_PASS tests

- `tests/resources/test_resource_template.py::TestExpandNonIdentifierNames::test_expand_resolves_sanitized_keys[resource://digit/{1id}-params2-resource://digit/alice]`
- `tests/resources/test_resource_template.py::TestExpandNonIdentifierNames::test_expand_resolves_sanitized_keys[resource://dollar/{$top}-params0-resource://dollar/alice]`
- `tests/resources/test_resource_template.py::TestExpandNonIdentifierNames::test_expand_resolves_sanitized_keys[resource://dot/{x.y}-params1-resource://dot/alice]`
- `tests/resources/test_resource_template.py::TestExpandNonIdentifierNames::test_expand_resolves_sanitized_keys[resource://uni/{a\xb2}-params3-resource://uni/alice]`
- `tests/resources/test_resource_template.py::TestExpandNonIdentifierNames::test_forward_uri_resolves_sanitized_keys`
- `tests/resources/test_resource_template.py::TestMalformedURITemplates::test_build_regex_handles_all_digit_names`
- `tests/resources/test_resource_template.py::TestMalformedURITemplates::test_build_regex_sanitizes_leading_digit_group_names`
- `tests/resources/test_resource_template.py::TestMalformedURITemplates::test_match_uri_template_sanitizes_leading_digit_names`
- `tests/resources/test_resource_template.py::TestNonIdentifierTemplateVariableNames::test_build_regex_compiles_non_identifier_group_names`
- `tests/resources/test_resource_template.py::TestNonIdentifierTemplateVariableNames::test_matches_non_identifier_names[resource://digit/{1id}-resource://digit/x-expected2]`
- `tests/resources/test_resource_template.py::TestNonIdentifierTemplateVariableNames::test_matches_non_identifier_names[resource://dollar/{$top}-resource://dollar/x-expected0]`
- `tests/resources/test_resource_template.py::TestNonIdentifierTemplateVariableNames::test_matches_non_identifier_names[resource://dot/{x.y}-resource://dot/x-expected1]`
- `tests/resources/test_resource_template.py::TestNonIdentifierTemplateVariableNames::test_matches_non_identifier_names[resource://uni/{a\xb2}-resource://uni/x-expected5]`
- `tests/resources/test_resource_template.py::TestNonIdentifierTemplateVariableNames::test_wildcard_with_non_identifier_name`
- `tests/server/providers/openapi/test_openapi_features.py::TestNonIdentifierPathParameterNames::test_non_identifier_path_params_listed_and_readable`
