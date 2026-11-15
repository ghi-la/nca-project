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
