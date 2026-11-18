# PrefectHQ__fastmcp-6180

- repo: `PrefectHQ/fastmcp`, created: 2026-10-30, base_commit: `fde5a7921281`
- PR: https://github.com/PrefectHQ/fastmcp/pull/6180
- issue: https://github.com/PrefectHQ/fastmcp/issues/6034
- FAIL_TO_PASS: 86 tests, PASS_TO_PASS: 23 tests, collection_error: **yes**

## 1. Issue (what the agent sees)

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

## 2. Gold patch

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

## 3. Test patch

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

## 4. FAIL_TO_PASS tests (first 40)

- `tests/utilities/openapi/test_parser.py::TestEscapedSchemaNameReferences::test_escaped_and_spaced_schema_names_survive_parsing`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_combined_operations`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_compresses_schema_nested_far_beyond_the_recursion_limit`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_disable_pruning_additional_properties`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_does_not_mutate_input`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_keeps_defs_referenced_below_the_traversal_cutoff`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_mcp_client_compatibility_requires_additional_properties`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_preserves_refs_by_default`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_prune_nested_additional_properties`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_prune_params`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_prune_titles`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_prune_titles_does_not_recurse_into_default_values`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_prune_titles_on_bare_metadata_node`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_prune_titles_on_draft07_and_legacy_keywords`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_prune_titles_preserves_user_extension_payloads`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_pruning_additional_properties`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_title_pruning_preserves_parameter_named_title`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_title_pruning_preserves_title_property_when_type_property_exists`
- `tests/utilities/test_json_schema.py::TestCompressSchema::test_title_pruning_with_nested_properties`
- `tests/utilities/test_json_schema.py::TestCompressSchemaDereference::test_dereference_false_preserves_refs`
- `tests/utilities/test_json_schema.py::TestCompressSchemaDereference::test_dereference_true_inlines_refs`
- `tests/utilities/test_json_schema.py::TestCompressSchemaDereference::test_other_optimizations_still_apply_without_dereference`
- `tests/utilities/test_json_schema.py::TestCompressSchemaEscapedRefNames::test_def_to_def_escaped_reference_keeps_both_defs`
- `tests/utilities/test_json_schema.py::TestCompressSchemaEscapedRefNames::test_escapes_percent_encoding_and_subpointers_are_preserved`
- `tests/utilities/test_json_schema.py::TestCompressSchemaEscapedRefNames::test_unused_escaped_defs_are_still_pruned`
- `tests/utilities/test_json_schema.py::TestDereferenceRefs::test_dereferences_nested_refs`
- `tests/utilities/test_json_schema.py::TestDereferenceRefs::test_dereferences_simple_ref`
- `tests/utilities/test_json_schema.py::TestDereferenceRefs::test_discriminator_property_remains_required_after_inlining`
- `tests/utilities/test_json_schema.py::TestDereferenceRefs::test_falls_back_for_circular_json_pointer_refs`
- `tests/utilities/test_json_schema.py::TestDereferenceRefs::test_falls_back_for_circular_refs`
- `tests/utilities/test_json_schema.py::TestDereferenceRefs::test_falls_back_for_root_ref_to_boolean_schema`
- `tests/utilities/test_json_schema.py::TestDereferenceRefs::test_falls_back_for_root_ref_to_false_schema_without_siblings`
- `tests/utilities/test_json_schema.py::TestDereferenceRefs::test_falls_back_for_root_ref_to_non_schema_json_value`
- `tests/utilities/test_json_schema.py::TestDereferenceRefs::test_nested_ref_to_boolean_schema_is_inlined_as_is`
- `tests/utilities/test_json_schema.py::TestDereferenceRefs::test_preserves_nested_siblings`
- `tests/utilities/test_json_schema.py::TestDereferenceRefs::test_preserves_property_named_discriminator`
- `tests/utilities/test_json_schema.py::TestDereferenceRefs::test_preserves_sibling_keywords`
- `tests/utilities/test_json_schema.py::TestDereferenceRefs::test_preserves_siblings_in_lists`
- `tests/utilities/test_json_schema.py::TestDereferenceRefs::test_strips_discriminator_mapping_after_inlining`
- `tests/utilities/test_json_schema.py::TestDereferenceRefs::test_strips_discriminator_under_property_named_like_a_keyword[const]`
