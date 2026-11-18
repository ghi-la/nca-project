# PrefectHQ__fastmcp-6147

- repo: `PrefectHQ/fastmcp`, created: 2026-10-29, base_commit: `fde5a7921281`
- PR: https://github.com/PrefectHQ/fastmcp/pull/6147
- issue: https://github.com/PrefectHQ/fastmcp/issues/6115
- FAIL_TO_PASS: 9 tests, PASS_TO_PASS: 3 tests, collection_error: **no**

## 1. Issue (what the agent sees)

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

## 2. Gold patch

```diff
diff --git a/fastmcp_slim/fastmcp/server/dependencies.py b/fastmcp_slim/fastmcp/server/dependencies.py
index e326867142..f10e9c0187 100644
--- a/fastmcp_slim/fastmcp/server/dependencies.py
+++ b/fastmcp_slim/fastmcp/server/dependencies.py
@@ -15,7 +15,6 @@
 from contextlib import AsyncExitStack, asynccontextmanager, contextmanager
 from contextvars import ContextVar
 from dataclasses import dataclass
-from functools import lru_cache
 from types import TracebackType
 from typing import TYPE_CHECKING, Any, Protocol, cast, get_type_hints, runtime_checkable
 
@@ -42,6 +41,7 @@
 from fastmcp.exceptions import FastMCPError
 from fastmcp.server.auth import AccessToken
 from fastmcp.server.http import _current_http_request
+from fastmcp.utilities._callable_cache import cache_on_callable
 from fastmcp.utilities.async_utils import (
     call_sync_fn_in_threadpool,
     is_coroutine_function,
@@ -728,7 +728,7 @@ def get_access_token() -> AccessToken | None:
 # --- Schema generation helper ---
 
 
-@lru_cache(maxsize=5000)
+@cache_on_callable
 def without_injected_parameters(
     fn: Callable[..., Any], *, run_in_thread: bool = True
 ) -> Callable[..., Any]:
diff --git a/fastmcp_slim/fastmcp/server/sessions.py b/fastmcp_slim/fastmcp/server/sessions.py
index 82ef061a21..17298b28d8 100644
--- a/fastmcp_slim/fastmcp/server/sessions.py
+++ b/fastmcp_slim/fastmcp/server/sessions.py
@@ -41,7 +41,6 @@
 import json
 import time
 from collections.abc import Callable, Sequence
-from functools import lru_cache
 from types import TracebackType
 from typing import (
     TYPE_CHECKING,
@@ -61,6 +60,7 @@
 from fastmcp.exceptions import FastMCPError
 from fastmcp.server.dependencies import get_access_token, get_server, get_session
 from fastmcp.server.providers.base import Provider
+from fastmcp.utilities._callable_cache import cache_on_callable
 from fastmcp.utilities.logging import get_logger
 
 if TYPE_CHECKING:
@@ -339,7 +339,7 @@ class _SessionIdMarker:
 SessionId = Annotated[str, _SessionIdMarker()]
 
 
-@lru_cache(maxsize=5000)
+@cache_on_callable
 def session_id_parameter_names(fn: Callable[..., object]) -> tuple[str, ...]:
     """Names of a function's parameters annotated with `SessionId`.
 
diff --git a/fastmcp_slim/fastmcp/tools/function_tool.py b/fastmcp_slim/fastmcp/tools/function_tool.py
index 872d31310a..0706dd4096 100644
--- a/fastmcp_slim/fastmcp/tools/function_tool.py
+++ b/fastmcp_slim/fastmcp/tools/function_tool.py
@@ -7,7 +7,6 @@
 import logging
 from collections.abc import Callable
 from dataclasses import dataclass, field
-from functools import lru_cache
 from types import MethodType
 from typing import (
     Annotated,
@@ -38,6 +37,7 @@
     ToolResult,
 )
 from fastmcp.tools.function_parsing import ParsedFunction, _is_object_schema
+from fastmcp.utilities._callable_cache import cache_on_callable
 from fastmcp.utilities.async_utils import (
     call_sync_fn_in_threadpool,
     is_coroutine_function,
@@ -80,7 +80,7 @@ def _materialize_sync_generator(result: Any) -> Any:
     return result
 
 
-@lru_cache(maxsize=5000)
+@cache_on_callable
 def _wrap_body_errors(
     fn: Callable[..., Any], *, materialize_generators: bool = False
 ) -> Callable[..., Any]:
diff --git a/fastmcp_slim/fastmcp/utilities/_callable_cache.py b/fastmcp_slim/fastmcp/utilities/_callable_cache.py
new file mode 100644
index 0000000000..dfeb35deee
--- /dev/null
+++ b/fastmcp_slim/fastmcp/utilities/_callable_cache.py
@@ -0,0 +1,82 @@
+"""Memoize callable metadata without making the callable process-owned."""
+
+import inspect
+import weakref
+from collections.abc import Callable
+from dataclasses import dataclass, field
+from functools import wraps
+from threading import RLock
+from typing import Any, ParamSpec, TypeVar
+
+P = ParamSpec("P")
+R = TypeVar("R")
+_CACHE_ATTRIBUTE = "__fastmcp_callable_cache__"
+
+
+@dataclass
+class _CallableCache:
+    owner: weakref.ReferenceType[Any] | None
+    values: dict[tuple[Any, ...], Any] = field(default_factory=dict)
+
+    def __reduce__(self) -> tuple[type, tuple[None]]:
+        # Tasks can pickle user functions. Metadata is process-local and may
+        # contain weakrefs or adapters; a restored callable builds it afresh.
+        return type(self), (None,)
+
+
+def cache_on_callable(build: Callable[P, R]) -> Callable[P, R]:
+    """Cache on the first argument, or its instance for a bound method.
+
+    Wrapper and TypeAdapter values can refer back to their callable, so a weak
+    key alone cannot prevent retention. Owning the values on the callable makes
+    the whole cycle collectable. Callables without a writable namespace or weak
+    reference support are evaluated uncached instead of retained globally.
+    """
+    first_parameter = next(iter(inspect.signature(build).parameters))
+    lock = RLock()
+
+    @wraps(build)
+    def cached(*args: P.args, **kwargs: P.kwargs) -> R:
+        try:
+            target = args[0]
+        except IndexError:
+            if first_parameter not in kwargs:
+                return build(*args, **kwargs)
+            target = kwargs[first_parameter]
+        if inspect.ismethod(target):
+            method = target.__func__
+            owner = target.__self__
+        else:
+            method = None
+            owner = target
+        options = tuple((k, v) for k, v in kwargs.items() if k != first_parameter)
+        key = (build, method, args[1:], options)
+        try:
+            namespace = vars(owner)
+            owner_ref = weakref.ref(owner)
+        except TypeError:
+            return build(*args, **kwargs)
+
+        with lock:
+            cache = namespace.get(_CACHE_ATTRIBUTE)
+            # Function wrappers often copy __dict__. Never reuse the source
+            # function's metadata on a distinct wrapper with a different schema.
+            if (
+                not isinstance(cache, _CallableCache)
+                or cache.owner is None
+                or cache.owner() is not owner
+            ):
+                cache = _CallableCache(owner_ref)
+                try:
+                    namespace[_CACHE_ATTRIBUTE] = cache
+                except TypeError:
+                    return build(*args, **kwargs)
+            if key in cache.values:
+                return cache.values[key]
+
+        value = build(*args, **kwargs)
+        with lock:
+            cache.values[key] = value
+        return value
+
+    return cached
diff --git a/fastmcp_slim/fastmcp/utilities/types.py b/fastmcp_slim/fastmcp/utilities/types.py
index 56d77e59cd..ce2718a710 100644
--- a/fastmcp_slim/fastmcp/utilities/types.py
+++ b/fastmcp_slim/fastmcp/utilities/types.py
@@ -5,7 +5,7 @@
 import mimetypes
 import os
 from collections.abc import Callable
-from functools import lru_cache
+from functools import lru_cache, partial
 from pathlib import Path
 from types import EllipsisType, UnionType
 from typing import (
@@ -17,6 +17,7 @@
     get_args,
     get_origin,
     get_type_hints,
+    overload,
 )
 from urllib.parse import quote
 
@@ -25,6 +26,8 @@
 from pydantic import AnyUrl, BaseModel, ConfigDict, Field, TypeAdapter, UrlConstraints
 from typing_extensions import TypeVar
 
+from fastmcp.utilities._callable_cache import cache_on_callable
+
 T = TypeVar("T", default=Any)
 
 # TODO(sdkv2): the SDK's `mcp.types.AnyFunction` alias was removed with the
@@ -52,14 +55,37 @@ def get_function_type_hints(fn: Callable[..., Any]) -> dict[str, Any]:
     return get_type_hints(fn, include_extras=True)
 
 
-@lru_cache(maxsize=5000)
-def get_cached_typeadapter(cls: T) -> TypeAdapter[T]:
+@overload
+def get_cached_typeadapter(cls: type[T]) -> TypeAdapter[T]: ...
+
+
+@overload
+def get_cached_typeadapter(cls: Any) -> TypeAdapter[Any]: ...
+
+
+def get_cached_typeadapter(cls: Any) -> TypeAdapter[Any]:
     """
     TypeAdapters are heavy objects, and in an application context we'd typically
     create them once in a global scope and reuse them as often as possible.
     However, this isn't feasible for user-generated functions. Instead, we use a
     cache to minimize the cost of creating them as much as possible.
     """
+    if inspect.isfunction(cls) or inspect.ismethod(cls) or isinstance(cls, partial):
+        return _get_callable_typeadapter(cls)
+    return _get_type_typeadapter(cls)
+
+
+@cache_on_callable
+def _get_callable_typeadapter(cls: T) -> TypeAdapter[T]:
+    return _create_typeadapter(cls)
+
+
+@lru_cache(maxsize=5000)
+def _get_type_typeadapter(cls: T) -> TypeAdapter[T]:
+    return _create_typeadapter(cls)
+
+
+def _create_typeadapter(cls: T) -> TypeAdapter[T]:
     # For functions, process annotations to handle forward references and convert
     # Annotated[Type, "string"] to Annotated[Type, Field(description="string")]
     if inspect.isfunction(cls) or inspect.ismethod(cls):
```

## 3. Test patch

```diff
diff --git a/tests/server/test_callable_cache_lifetime.py b/tests/server/test_callable_cache_lifetime.py
new file mode 100644
index 0000000000..8592e6c498
--- /dev/null
+++ b/tests/server/test_callable_cache_lifetime.py
@@ -0,0 +1,219 @@
+"""Callable caches must not outlive the user functions they accelerate."""
+
+import gc
+import weakref
+from collections.abc import Callable
+from functools import partial, wraps
+
+import cloudpickle
+import pytest
+from uncalled_for import annotations, introspection
+
+from fastmcp import Client, FastMCP
+from fastmcp.server.context import Context
+from fastmcp.server.dependencies import without_injected_parameters
+from fastmcp.server.sessions import session_id_parameter_names
+from fastmcp.tools.function_tool import _wrap_body_errors
+from fastmcp.utilities.types import get_cached_typeadapter
+
+
+class Payload:
+    def __init__(self) -> None:
+        self.items = list(range(100))
+
+
+@pytest.fixture
+def external_introspection_caches(monkeypatch: pytest.MonkeyPatch) -> None:
+    # uncalled-for #21 independently retains callables in its introspection
+    # (signature, parameter) and annotations (metadata, annotation) caches.
+    # Isolate them so these regressions can verify FastMCP's ownership without
+    # changing the dependency's process-wide cache objects in production.
+    monkeypatch.setattr(introspection, "_signature_cache", {})
+    monkeypatch.setattr(introspection, "_parameter_cache", {})
+    monkeypatch.setattr(annotations, "_metadata_cache", {})
+    monkeypatch.setattr(annotations, "_annotation_cache", {})
+
+
+def release_external_introspection() -> None:
+    introspection._signature_cache.clear()
+    introspection._parameter_cache.clear()
+    annotations._metadata_cache.clear()
+    annotations._annotation_cache.clear()
+
+
+@pytest.mark.usefixtures("external_introspection_caches")
+@pytest.mark.parametrize(
+    "build",
+    [
+        get_cached_typeadapter,
+        without_injected_parameters,
+        _wrap_body_errors,
+        session_id_parameter_names,
+    ],
+    ids=["type-adapter", "dependencies", "body-errors", "session-id"],
+)
+def test_callable_cache_does_not_retain_a_dropped_closure(
+    build: Callable[..., object],
+) -> None:
+    def populate() -> tuple[weakref.ReferenceType, weakref.ReferenceType]:
+        payload = Payload()
+
+        def tool(query: str) -> int:
+            return len(payload.items)
+
+        build(tool)
+        return weakref.ref(tool), weakref.ref(payload)
+
+    tool_ref, payload_ref = populate()
+    release_external_introspection()
+    gc.collect()
+
+    assert tool_ref() is None
+    assert payload_ref() is None
+
+
+@pytest.mark.usefixtures("external_introspection_caches")
+async def test_dropped_servers_leave_no_fastmcp_owned_tool_closures() -> None:
+    async def build_and_call() -> tuple[weakref.ReferenceType, weakref.ReferenceType]:
+        server = FastMCP("temporary")
+        payload = Payload()
+
+        def search(query: str) -> int:
+            return len(payload.items)
+
+        server.tool(search)
+        async with Client(server) as client:
+            result = await client.call_tool("search", {"query": "q"})
+            assert result.data == 100
+        return weakref.ref(search), weakref.ref(payload)
+
+    refs = [await build_and_call() for _ in range(3)]
+    release_external_introspection()
+    gc.collect()
+
+    assert all(tool() is None and payload() is None for tool, payload in refs)
+
+
+@pytest.mark.usefixtures("external_introspection_caches")
+def test_live_callable_keeps_its_cached_adapter() -> None:
+    def tool(value: int) -> int:
+        return value + 1
+
+    adapter = get_cached_typeadapter(tool)
+    assert get_cached_typeadapter(tool) is adapter
+    assert adapter.validate_python({"value": 2}) == 3
+    gc.collect()
+    assert get_cached_typeadapter(tool) is adapter
+    assert get_cached_typeadapter(int) is get_cached_typeadapter(int)
+
+
+def test_wrapped_function_does_not_reuse_the_source_functions_cache() -> None:
+    def source() -> int:
+        return 1
+
+    original = _wrap_body_errors(source)
+
+    @wraps(source)
+    def wrapped() -> int:
+        return 2
+
+    distinct = _wrap_body_errors(wrapped)
+    assert distinct is not original
+    assert original() == 1
+    assert distinct() == 2
+    assert _wrap_body_errors(wrapped) is distinct
+
+
+@pytest.mark.usefixtures("external_introspection_caches")
+def test_dependency_wrapper_caches_each_thread_option_separately() -> None:
+    def tool(value: int, ctx: Context) -> int:
+        return value
+
+    threaded = without_injected_parameters(tool, run_in_thread=True)
+    inline = without_injected_parameters(tool, run_in_thread=False)
+    assert threaded is not inline
+    assert without_injected_parameters(tool, run_in_thread=True) is threaded
+    assert without_injected_parameters(fn=tool, run_in_thread=False) is inline
+
+
+@pytest.mark.usefixtures("external_introspection_caches")
+def test_bound_method_cache_is_owned_by_its_instance() -> None:
+    class Receiver:
+        def __init__(self, value: int) -> None:
+            self.value = value
+
+        def tool(self, offset: int) -> int:
+            return self.value + offset
+
+    live = Receiver(10)
+    adapter = get_cached_typeadapter(live.tool)
+    assert get_cached_typeadapter(live.tool) is adapter
+
+    def populate() -> weakref.ReferenceType:
+        dropped = Receiver(20)
+        other = get_cached_typeadapter(dropped.tool)
+        assert other is not adapter
+        assert other.validate_python({"offset": 1}) == 21
+        _wrap_body_errors(dropped.tool)
+        without_injected_parameters(dropped.tool)
+        session_id_parameter_names(dropped.tool)
+        return weakref.ref(dropped)
+
+    dropped_ref = populate()
+    release_external_introspection()
+    gc.collect()
+    assert dropped_ref() is None
+    assert get_cached_typeadapter(live.tool) is adapter
+    assert adapter.validate_python({"offset": 1}) == 11
+
+
+@pytest.mark.usefixtures("external_introspection_caches")
+def test_method_without_instance_namespace_is_not_retained() -> None:
+    class Receiver:
+        __slots__ = ("__weakref__",)
+
+        def tool(self, offset: int) -> int:
+            return offset
+
+    def populate() -> weakref.ReferenceType:
+        receiver = Receiver()
+        adapter = get_cached_typeadapter(receiver.tool)
+        assert adapter.validate_python({"offset": 2}) == 2
+        _wrap_body_errors(receiver.tool)
+        without_injected_parameters(receiver.tool)
+        session_id_parameter_names(receiver.tool)
+        return weakref.ref(receiver)
+
+    receiver_ref = populate()
+    release_external_introspection()
+    gc.collect()
+    assert receiver_ref() is None
+
+
+def test_partial_adapter_is_reused_without_retaining_its_bound_payload() -> None:
+    def tool(payload: Payload, offset: int) -> int:
+        return len(payload.items) + offset
+
+    def populate() -> tuple[weakref.ReferenceType, weakref.ReferenceType]:
+        payload = Payload()
+        bound = partial(tool, payload)
+        adapter = get_cached_typeadapter(bound)
+        assert get_cached_typeadapter(bound) is adapter
+        assert adapter.validate_python({"offset": 2}) == 102
+        return weakref.ref(bound), weakref.ref(payload)
+
+    bound_ref, payload_ref = populate()
+    gc.collect()
+    assert bound_ref() is None
+    assert payload_ref() is None
+
+
+def test_callable_cache_is_not_serialized_with_a_task_function() -> None:
+    def tool(value: int) -> int:
+        return value + 1
+
+    get_cached_typeadapter(tool)
+    restored = cloudpickle.loads(cloudpickle.dumps(tool))
+    assert restored(2) == 3
+    assert get_cached_typeadapter(restored).validate_python({"value": 2}) == 3
+    assert get_cached_typeadapter(restored) is not get_cached_typeadapter(tool)
```

## 4. FAIL_TO_PASS tests

- `tests/server/test_callable_cache_lifetime.py::test_bound_method_cache_is_owned_by_its_instance`
- `tests/server/test_callable_cache_lifetime.py::test_callable_cache_does_not_retain_a_dropped_closure[body-errors]`
- `tests/server/test_callable_cache_lifetime.py::test_callable_cache_does_not_retain_a_dropped_closure[dependencies]`
- `tests/server/test_callable_cache_lifetime.py::test_callable_cache_does_not_retain_a_dropped_closure[session-id]`
- `tests/server/test_callable_cache_lifetime.py::test_callable_cache_does_not_retain_a_dropped_closure[type-adapter]`
- `tests/server/test_callable_cache_lifetime.py::test_dependency_wrapper_caches_each_thread_option_separately`
- `tests/server/test_callable_cache_lifetime.py::test_dropped_servers_leave_no_fastmcp_owned_tool_closures`
- `tests/server/test_callable_cache_lifetime.py::test_method_without_instance_namespace_is_not_retained`
- `tests/server/test_callable_cache_lifetime.py::test_partial_adapter_is_reused_without_retaining_its_bound_payload`
