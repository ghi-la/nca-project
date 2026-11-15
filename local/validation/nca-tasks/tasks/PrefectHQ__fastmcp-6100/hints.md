Thanks for the report. This issue goes beyond what our contributor guidelines ask for — we just need a short problem description and an MRE. Please see our [contributing guidelines](https://github.com/PrefectHQ/fastmcp/blob/main/CONTRIBUTING.md) and condense this issue. We'll triage it once it's trimmed down.
Reproduced on current `main` with the issue's scenario, and verified the suggested direction: a name is treated as pre-addressed solely because it matches `parse_hashed_backend_name()`, without checking the digest is actually `hash_tool(app_name, local_name)`.

Branch ready with the fix + tests (carried forward from the author-closed #5867):
- `_prefix` now passes a name through only when it equals `hashed_backend_name(app_name, parsed_local_name)`; hash-shaped user names get a normal identity.
- Red/green evidence: 3 tests fail on main (`test_hash_shaped_name_is_still_given_an_identity` + both `TestHashShapedToolNames` compose variants); 103 pass across `tests/test_fastmcp_app.py` and `tests/server/providers/test_prefab_roundtrip.py` with the fix.

Happy to open the PR once assigned.

🤖 Prepared with ZCode (AI agent) on behalf of Wilson0511