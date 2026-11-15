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
