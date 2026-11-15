Tool function caches keep the tools of dropped servers alive
`without_injected_parameters` (`fastmcp/server/dependencies.py`) and `get_cached_typeadapter` (`fastmcp/utilities/types.py`) are `@lru_cache(maxsize=5000)` and keyed by the tool function. A server that is dropped keeps up to 5,000 of its tool functions alive, with everything their closures hold. `remove_tool` does not clear them, and FastMCP has no public call that does.

This matters for a server that builds its tools as closures per request or per user, for example to give each user their own tool list. Each rebuilt server adds entries, and the old servers' tool data stays in memory until the LRU pushes them out.

The functions are also keys of the unbounded dicts of `uncalled_for` (`_signature_cache`, `_parameter_cache`): https://github.com/chrisguidry/uncalled-for/issues/21.

## Reproduction

fastmcp 3.3.1, uncalled-for 0.2.0, Python 3.12.

```python
import asyncio
import gc
import weakref

from fastmcp import Client, FastMCP
from uncalled_for import introspection


async def build_and_call() -> weakref.ref:
    mcp = FastMCP("demo")
    index = list(range(100_000))

    def search(query: str) -> int:
        return len(index)

    mcp.tool(search)
    async with Client(mcp) as client:
        await client.call_tool("search", {"query": "q"})
    return weakref.ref(search)


async def main() -> None:
    refs = [await build_and_call() for _ in range(50)]
    gc.collect()
    print(f"tool functions still alive: {sum(ref() is not None for ref in refs)} of 50")


asyncio.run(main())
```

| Run | Tool functions still alive |
|---|---|
| As released | 50 of 50 |
| `uncalled_for`'s two dicts made `WeakKeyDictionary` | 50 of 50: the two LRU caches still hold them |
| Weak dicts, and the two LRU caches cleared before `gc.collect()` | 0 of 50 |

In our backend, 300 rebuilds of one 64-tool server grew the process by 54 MB. Today we free a dropped server's functions with `_clear_signature_caches(fn)` for each tool and resource, then `cache_clear()` on the two LRU caches. That calls a private name and empties the caches of every server in the process.

## Suggested change

Any of these would let a dropped server's functions go:

- Key the two caches weakly, for example by a `WeakKeyDictionary` in place of `lru_cache`, or store the result on the function object.
- Remove a tool's entries when `remove_tool` runs, or when the server shuts down.
- A public `forget(fn)` beside `_clear_signature_caches`, which clears every cache that FastMCP and `uncalled_for` keep for one function.

