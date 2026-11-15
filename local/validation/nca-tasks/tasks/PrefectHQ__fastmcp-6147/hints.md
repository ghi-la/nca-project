Reproduced on main `92c4c8d7` with Python 3.12.14 and uncalled-for 0.4.0: after 10 real in-process client calls and dropping the servers, all 10 tool closures and their payloads remain alive.

There are two more FastMCP cache owners on this version: `_wrap_body_errors` and `session_id_parameter_names`. Clearing the two caches in the report plus uncalled-for's caches still retains all 10; clearing these two as well releases all 10. Each also retains a closure in an isolated check.

A plain `WeakKeyDictionary` replacement isn't sufficient for the wrapper/adapter caches: their values retain the function (the no-injection wrapper even returns the key itself). I checked this separately with the real uncached wrapper/adapter builders and a non-retaining control.

Would a callable-owned cache be preferable to an explicit per-function eviction API? The reporter has first claim; happy to share the offline probe or help with the agreed approach. Investigated with Codex assistance.