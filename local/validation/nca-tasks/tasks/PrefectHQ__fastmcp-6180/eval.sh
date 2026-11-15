#!/bin/bash
set -uxo pipefail
cd /testbed
git config --global --add safe.directory /testbed
git status
git -c core.fileMode=false diff fde5a7921281bae12267833c0b5624d5029229f6
git checkout fde5a7921281bae12267833c0b5624d5029229f6 -- tests/utilities/openapi/test_parser.py tests/utilities/test_json_schema.py
git apply -v - <<'EOF_NCA_TEST_PATCH_7f3a'
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
 
EOF_NCA_TEST_PATCH_7f3a
: '>>>>> Start Test Output'
pytest -rA --color=no -p no:cacheprovider --continue-on-collection-errors tests/utilities/openapi/test_parser.py tests/utilities/test_json_schema.py
: '>>>>> End Test Output'
git checkout fde5a7921281bae12267833c0b5624d5029229f6 -- tests/utilities/openapi/test_parser.py tests/utilities/test_json_schema.py
