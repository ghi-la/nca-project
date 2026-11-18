# modelcontextprotocol__python-sdk-3485

- repo: `modelcontextprotocol/python-sdk`, created: 2026-09-09, base_commit: `91941ed4d398`
- PR: https://github.com/modelcontextprotocol/python-sdk/pull/3485
- issue: https://github.com/modelcontextprotocol/python-sdk/issues/3486
- FAIL_TO_PASS: 98 tests, PASS_TO_PASS: 21 tests, collection_error: **yes**

## 1. Issue (what the agent sees)

Add SEP-2640 (Skills Extension) protocol support
[SEP-2640 (Skills Extension)](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2640)
is Accepted, but the Python SDK has no support for it. It adds `skills/list`,
`skills/get`, and optional `resources/directory/read`, negotiated under the
`io.modelcontextprotocol/skills` extension.

We need to add the **protocol primitives** — a `Skills(...)` server extension
plus thin client wrappers and SEP-2640 validation — built on the existing
`Extension`/`MethodBinding` mechanism (like the shipped `Apps` extension), with no
schema or dependency changes. Filesystem discovery/caching would stay out of scope
for a higher-level provider.

## 2. Gold patch

```diff
diff --git a/docs/advanced/extensions.md b/docs/advanced/extensions.md
index b8372da3df..e8793b8cb1 100644
--- a/docs/advanced/extensions.md
+++ b/docs/advanced/extensions.md
@@ -190,6 +190,31 @@ that did not declare it (error -32021), and a claimed shape from a server that
 skips the gate fails validation, exactly as the spec requires for an
 unrecognized `resultType`. Off by default, on both ends of the wire.
 
+An extension can also expose methods of its own. Pass its type to `client.extension()`
+after connecting to get the API bound to that connection. Run the
+[Skills server](skills.md#serving-a-skill) at `http://localhost:8000/mcp` for this example:
+
+```python
+import anyio
+
+from mcp import Client
+from mcp.client.extensions.skills import Skills
+
+
+async def main() -> None:
+    async with Client("http://localhost:8000/mcp", extensions=[Skills()]) as client:
+        for skill in await client.extension(Skills).list_skills():
+            print(skill.uri)
+
+
+if __name__ == "__main__":
+    anyio.run(main)
+```
+
+`client.extension(Skills)` returns the type produced by `Skills.bind(session)`. Your own
+extension can define the same hook. The client raises `ValueError` when the type was not
+registered and `RuntimeError` when it is not connected.
+
 To advertise an identifier with **no** client-side behaviour (the server gates on
 the capability, the client does nothing, as in the search client above), use
 `advertise()`:
diff --git a/docs/advanced/skills.md b/docs/advanced/skills.md
new file mode 100644
index 0000000000..56f95cfa40
--- /dev/null
+++ b/docs/advanced/skills.md
@@ -0,0 +1,134 @@
+# Skills
+
+[SEP-2640](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2640) defines a
+convention for serving [Agent Skills](https://agentskills.io/) over MCP. A skill is just a
+directory of files — at minimum a `SKILL.md` with YAML frontmatter — that you expose as ordinary
+MCP resources, conventionally under a `skill://` URI.
+
+A server enumerates its skills with `skills/list`, answers for any single one by URI with
+`skills/get`, and — optionally — lists a directory's direct children with
+`resources/directory/read`.
+
+The SDK ships this as the built-in `Skills` extension (`io.modelcontextprotocol/skills`). There's
+one on the server side and one on the client side. If [Extensions](extensions.md) are new to you,
+skim that page first.
+
+!!! info
+    `Skills` gives you the **protocol** primitives: request/response handling, capability
+    advertisement, and SEP-2640 conformance validation.
+
+    It does **not** discover, read, or hash skills from a filesystem. You supply handlers that
+    answer from wherever your catalog actually lives — a database, a generated index, an in-memory
+    list, or a directory you walk yourself — and you serve each skill's files as ordinary resources
+    through `MCPServer.add_resource` or an `@mcp.resource(...)` template handler.
+
+## Serving a skill
+
+Here's a server that serves one skill:
+
+```python title="server.py" hl_lines="31-41 44-51 55"
+--8<-- "docs_src/skills/tutorial001.py"
+```
+
+There are three moves here:
+
+* `Skill(uri=..., frontmatter=..., resources=[...])` is one entry. It has the same shape whether it
+  comes back from `skills/list` or `skills/get`. `resources` is the skill's complete file
+  manifest — every file, `SKILL.md` included, each with a `sha256:...` digest and byte size — or
+  the string `"dynamic"` for content generated on demand.
+* `list_skills` and `get_skill` are plain async callables, invoked once per request. `get_skill`
+  **must** answer for a skill even if your `list_skills` left it out — SEP-2640 requires a server
+  to answer by URI for every skill it serves, listed or not.
+* `mcp.add_resource(TextResource(uri=SKILL_URI, ...))` registers the skill's actual file content,
+  served through the SDK's ordinary resource machinery. `Skills` never reads or writes resource
+  content itself.
+
+And that's it. `Skills(list_skills=..., get_skill=...)` is all a server needs;
+`resources/directory/read` is optional (more on that below).
+
+## Inspecting a skill
+
+On the client side, `Skills` is a [`ClientExtension`](extensions.md). You register it the same way
+you register any other one — by passing it to `Client(extensions=[...])` — and then call `extension` to
+get the verbs tied to that connection:
+
+```python title="client.py" hl_lines="9-11"
+--8<-- "docs_src/skills/tutorial001_client.py"
+```
+
+`client.extension(Skills)` hands you a `SkillsClient` with the SEP-2640 methods:
+
+* `list_skills` and `read_directory` follow `nextCursor` to completion, so a single call gives you
+  every page's skills or resources.
+* `get_skill` costs exactly one request.
+
+These three validate the server's response against the SEP-2640 conformance rules before returning
+it. A name that doesn't match its URI, a digest in the wrong shape, or an incomplete manifest raises
+`ValueError` rather than reaching your code.
+
+Read a skill file with `Client.read_resource(uri)`, the same method you use for any MCP resource.
+It returns raw content without checking it against the skill's manifest.
+
+!!! warning "Verify files before loading"
+    A host that loads a skill must hold its `Skill` entry. Before using a fetched file, check that
+    its URI appears in that entry's `resources` and that its bytes match the advertised size and
+    SHA-256 digest. A `"dynamic"` skill has no digest to check. Refreshing the entry to accept
+    changed bytes also changes the content to which any prior approval applied.
+
+    Skill content is untrusted model input, exactly like any other server-provided text. SEP-2640
+    requires a host to tag it with its originating server before it reaches the model, and to
+    never grant the frontmatter's `allowed-tools` field (or any other permission-widening field)
+    without explicit per-skill user approval.
+
+    A matching digest confirms the *bytes*, not the *frontmatter*: it doesn't prove the
+    `frontmatter` the server advertised in `skills/get` matches the frontmatter inside the fetched
+    `SKILL.md`. If you act on `skill.frontmatter` — especially `allowed-tools` — parse the fetched
+    file and compare its frontmatter yourself.
+
+    These are host responsibilities the SDK cannot discharge for you — read the SEP's
+    [Security Implications](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2640)
+    section before building a host on top of this extension.
+
+## Directory reads
+
+A skill's instructions often point at a directory rather than a file ("pick the matching
+template from `templates/`"). `resources/list` can't answer that — it enumerates a server's
+entire resource space, not one subtree — so SEP-2640 adds `resources/directory/read`, gated
+behind the `directoryRead` capability setting:
+
+```python
+mcp = MCPServer(
+    "catalog",
+    extensions=[
+        Skills(
+            list_skills=list_skills,
+            get_skill=get_skill,
+            read_directory=read_directory,  # lists uri's direct children
+        )
+    ],
+)
+```
+
+Supplying `read_directory` advertises `{"directoryRead": true}` under the extension's
+capabilities. Omitting it advertises neither the setting nor the method — a client calling
+`resources/directory/read` against such a server gets `METHOD_NOT_FOUND`. On the client side,
+`read_directory` raises before it sends anything if the connected server hasn't advertised the
+setting.
+
+## Protocol version and caching
+
+In protocol version `2026-07-28` and later, `skills/list` and `skills/get` results carry the base
+protocol's caching fields, [`ttlMs` and `cacheScope`](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2549) —
+the same freshness hint `tools/list`, `resources/list`, and `resources/read` carry. `Skills` fills
+`cacheScope` with `"private"` when your handler leaves it unset, and omits both fields entirely on an
+older connection. Set `cache_scope="public"` only when the result is the same for every user.
+You don't have to branch on protocol version yourself.
+
+## What this SDK doesn't do
+
+`Skills` is a protocol adapter, not a skills provider. It has no opinion on where a skill's bytes
+live, how they're indexed, or when a catalog is refreshed — that's for a higher-level library, or
+your own handler, to decide.
+
+If you're looking for "scan this directory and serve whatever's in it," you're looking for a
+provider built on top of `Skills`, not `Skills` itself.
diff --git a/docs_src/skills/__init__.py b/docs_src/skills/__init__.py
new file mode 100644
index 0000000000..e69de29bb2
diff --git a/docs_src/skills/tutorial001.py b/docs_src/skills/tutorial001.py
new file mode 100644
index 0000000000..61cc43c2e8
--- /dev/null
+++ b/docs_src/skills/tutorial001.py
@@ -0,0 +1,54 @@
+import hashlib
+from typing import Any
+
+from mcp.server.context import ServerRequestContext
+from mcp.server.mcpserver import MCPServer
+from mcp.server.mcpserver.resources import TextResource
+from mcp.server.skills import Skills
+from mcp.shared.exceptions import MCPError
+from mcp.shared.skills import (
+    GetSkillParams,
+    GetSkillResult,
+    ListSkillsParams,
+    ListSkillsResult,
+    Skill,
+    SkillResource,
+)
+from mcp.types import INVALID_PARAMS
+
+SKILL_URI = "skill://git-workflow/SKILL.md"
+SKILL_MD = """\
+---
+name: git-workflow
+description: Follow this team's Git conventions for branching and commits
+---
+
+Branch from `main` using `type/short-description`. Write commit subjects in the
+imperative mood, under 72 characters.
+"""
+
+GIT_WORKFLOW = Skill(
+    uri=SKILL_URI,
+    frontmatter={"name": "git-workflow", "description": "Follow this team's Git conventions for branching and commits"},
+    resources=[
+        SkillResource(
+            uri=SKILL_URI,
+            digest=f"sha256:{hashlib.sha256(SKILL_MD.encode()).hexdigest()}",
+            size=len(SKILL_MD.encode()),
+        )
+    ],
+)
+
+
+async def list_skills(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+    return ListSkillsResult(skills=[GIT_WORKFLOW])
+
+
+async def get_skill(ctx: ServerRequestContext[Any, Any], params: GetSkillParams) -> GetSkillResult:
+    if params.uri != SKILL_URI:
+        raise MCPError(code=INVALID_PARAMS, message=f"unknown skill: {params.uri}")
+    return GetSkillResult(skill=GIT_WORKFLOW)
+
+
+mcp = MCPServer("catalog", extensions=[Skills(list_skills=list_skills, get_skill=get_skill)])
+mcp.add_resource(TextResource(uri=SKILL_URI, name="SKILL.md", mime_type="text/markdown", text=SKILL_MD))
diff --git a/docs_src/skills/tutorial001_client.py b/docs_src/skills/tutorial001_client.py
new file mode 100644
index 0000000000..27f51fd2f1
--- /dev/null
+++ b/docs_src/skills/tutorial001_client.py
@@ -0,0 +1,18 @@
+import anyio
+
+from mcp import Client
+from mcp.client.extensions.skills import Skills
+
+
+async def main() -> None:
+    async with Client("http://localhost:8000/mcp", extensions=[Skills()]) as client:
+        catalog = client.extension(Skills)
+        for skill in await catalog.list_skills():
+            print(skill.uri, skill.frontmatter["description"])
+
+        skill = await catalog.get_skill("skill://git-workflow/SKILL.md")
+        print(skill.resources)
+
+
+if __name__ == "__main__":
+    anyio.run(main)
diff --git a/mkdocs.yml b/mkdocs.yml
index 1874a04050..62f0640366 100644
--- a/mkdocs.yml
+++ b/mkdocs.yml
@@ -69,6 +69,7 @@ nav:
       - Header parameters: advanced/header-parameters.md
       - Extensions: advanced/extensions.md
       - MCP Apps: advanced/apps.md
+      - Skills: advanced/skills.md
   - Troubleshooting: troubleshooting.md
   - Translations: translations.md
   - Migration Guide: migration.md
diff --git a/src/mcp/client/client.py b/src/mcp/client/client.py
index 8c7d372431..099dcbb874 100644
--- a/src/mcp/client/client.py
+++ b/src/mcp/client/client.py
@@ -49,7 +49,7 @@
 from mcp.client._probe import negotiate_auto
 from mcp.client._transport import Transport
 from mcp.client.caching import CacheConfig, CacheMode, ClientResponseCache, InMemoryResponseCacheStore
-from mcp.client.extension import ClaimContext, ClientExtension, NotificationBinding, ResultClaim
+from mcp.client.extension import ClaimContext, ClientExtension, ClientExtensionBinding, NotificationBinding, ResultClaim
 from mcp.client.session import (
     ClientRequestContext,
     ClientSession,
@@ -87,6 +87,7 @@
 _T = TypeVar("_T")
 _ResultT = TypeVar("_ResultT")
 _CacheableT = TypeVar("_CacheableT", bound=CacheableResult)
+_BoundT = TypeVar("_BoundT")
 
 _Connector = Callable[[AsyncExitStack, ConnectMode, bool], Awaitable["Dispatcher[Any]"]]
 """Resolved at ``__post_init__`` from the shape of ``server`` alone: enter whatever resources
@@ -376,6 +377,7 @@ async def main():
     _connect: _Connector = field(init=False, repr=False, compare=False)
     _response_cache: ClientResponseCache | None = field(init=False, default=None, repr=False, compare=False)
     _folded_extensions: _FoldedExtensions = field(init=False, repr=False, compare=False)
+    _registered_extensions: tuple[ClientExtension, ...] = field(init=False, repr=False, compare=False)
 
     def __post_init__(self) -> None:
         if self.mode not in ("legacy", "auto") and self.mode not in MODERN_PROTOCOL_VERSIONS:
@@ -389,6 +391,7 @@ def __post_init__(self) -> None:
             )
 
         self._folded_extensions = _fold_extensions(self.extensions)
+        self._registered_extensions = tuple(self.extensions or ())
 
         srv = self.server
         if isinstance(srv, MCPServer):
@@ -493,6 +496,19 @@ def session(self) -> ClientSession:
             raise RuntimeError("Client must be used within an async context manager")
         return self._session
 
+    def extension(self, extension_type: type[ClientExtensionBinding[_BoundT]]) -> _BoundT:
+        """Return the typed API of a registered extension for this connection.
+
+        Raises:
+            RuntimeError: If the client is not connected.
+            ValueError: If no extension of this type was registered.
+        """
+        session = self.session
+        for extension in self._registered_extensions:
+            if isinstance(extension, extension_type):
+                return cast(ClientExtensionBinding[_BoundT], extension).bind(session)
+        raise ValueError(f"client extension {extension_type.__name__!r} is not registered")
+
     # TODO(maxisbey): the by-construction shape is for __aenter__ to return a connected-view
     # type whose protocol_version/server_capabilities are non-Optional fields,
     # eliminating these guards (and the one in .session). Same family as resolving the
diff --git a/src/mcp/client/extension.py b/src/mcp/client/extension.py
index a813475e5e..59d08b1bfc 100644
--- a/src/mcp/client/extension.py
+++ b/src/mcp/client/extension.py
@@ -15,6 +15,7 @@
 from mcp_types.version import MODERN_PROTOCOL_VERSIONS
 from pydantic import AliasChoices, AliasPath, BaseModel
 from pydantic.fields import FieldInfo
+from typing_extensions import Protocol
 
 from mcp.shared.extension import validate_extension_identifier
 
@@ -24,6 +25,7 @@
 __all__ = [
     "ClaimContext",
     "ClientExtension",
+    "ClientExtensionBinding",
     "NotificationBinding",
     "ResultClaim",
     "UnexpectedClaimedResult",
@@ -54,6 +56,15 @@ def _wire_keys(name: str, field: FieldInfo) -> frozenset[str]:
 
 ClaimedT = TypeVar("ClaimedT", bound=Result)
 NotifyParamsT = TypeVar("NotifyParamsT", bound=BaseModel)
+BoundT_co = TypeVar("BoundT_co", covariant=True)
+
+
+class ClientExtensionBinding(Protocol[BoundT_co]):
+    """An extension that exposes a typed API for one connected client."""
+
+    def bind(self, session: ClientSession) -> BoundT_co:
+        """Return the extension API bound to `session`."""
+        ...
 
 
 @dataclass(frozen=True, kw_only=True)
diff --git a/src/mcp/client/extensions/__init__.py b/src/mcp/client/extensions/__init__.py
new file mode 100644
index 0000000000..ef91475f99
--- /dev/null
+++ b/src/mcp/client/extensions/__init__.py
@@ -0,0 +1,3 @@
+from mcp.client.extensions.skills import Skills, SkillsClient
+
+__all__ = ["Skills", "SkillsClient"]
diff --git a/src/mcp/client/extensions/skills.py b/src/mcp/client/extensions/skills.py
new file mode 100644
index 0000000000..11c78db816
--- /dev/null
+++ b/src/mcp/client/extensions/skills.py
@@ -0,0 +1,170 @@
+"""Client-side Skills extension (SEP-2640).
+
+`Skills` is an opt-in [`ClientExtension`](../advanced/extensions.md) for talking
+to a skills catalog server. Register it with `Client(extensions=[Skills()])`,
+then call `client.extension(Skills)` for the SEP-2640 verbs — `list_skills`, `get_skill`,
+and `read_directory` — tied to that connection:
+
+    async with Client("http://localhost:8000/mcp", extensions=[Skills()]) as client:
+        for skill in await client.extension(Skills).list_skills():
+            print(skill.uri, skill.frontmatter["description"])
+
+`client.extension(Skills)` returns a `SkillsClient`. Its catalog verbs — `list_skills`,
+`get_skill`, and `read_directory` — check that the server advertises the
+extension and validate its response; `list_skills` and `read_directory` follow
+`nextCursor` to completion, so one call returns every page's results.
+"""
+
... (634 more lines, see the PR)
```

## 3. Test patch

```diff
diff --git a/tests/client/extensions/test_skills.py b/tests/client/extensions/test_skills.py
new file mode 100644
index 0000000000..c6d044ea09
--- /dev/null
+++ b/tests/client/extensions/test_skills.py
@@ -0,0 +1,350 @@
+"""Tests for the client-side Skills extension (SEP-2640, `mcp.client.extensions.skills`)."""
+
+import hashlib
+from collections.abc import AsyncIterator
+from contextlib import asynccontextmanager
+from typing import Any
+
+import pytest
+from mcp_types import INVALID_PARAMS, Resource
+
+from mcp.client.client import Client
+from mcp.client.extensions.skills import Skills as ClientSkills
+from mcp.client.extensions.skills import SkillsClient
+from mcp.server.context import ServerRequestContext
+from mcp.server.extension import Extension, MethodBinding
+from mcp.server.mcpserver import MCPServer
+from mcp.server.mcpserver.resources import TextResource
+from mcp.server.skills import Skills
+from mcp.shared.exceptions import MCPError
+from mcp.shared.skills import (
+    EXTENSION_ID,
+    METHOD_GET,
+    GetSkillParams,
+    GetSkillResult,
+    ListSkillsParams,
+    ListSkillsResult,
+    ReadDirectoryParams,
+    ReadDirectoryResult,
+    Skill,
+    SkillResource,
+)
+
+pytestmark = pytest.mark.anyio
+
+_SKILL_URI = "skill://git-workflow/SKILL.md"
+_SKILL_CONTENT = "# git-workflow\n"
+_SKILL_DIGEST = f"sha256:{hashlib.sha256(_SKILL_CONTENT.encode()).hexdigest()}"
+
+
+def _skill() -> Skill:
+    return Skill(
+        uri=_SKILL_URI,
+        frontmatter={"name": "git-workflow", "description": "d"},
+        resources=[SkillResource(uri=_SKILL_URI, digest=_SKILL_DIGEST, size=len(_SKILL_CONTENT))],
+    )
+
+
+async def _get_skill(ctx: ServerRequestContext[Any, Any], params: GetSkillParams) -> GetSkillResult:
+    if params.uri != _SKILL_URI:
+        raise MCPError(code=INVALID_PARAMS, message="unknown skill")
+    return GetSkillResult(skill=_skill())
+
+
+def _paginated_list_handler() -> Any:
+    """A `list_skills` handler serving two skills across two pages, by URI order."""
+    pages = {
+        None: ([_skill()], "page-2"),
+        "page-2": (
+            [
+                Skill(
+                    uri="skill://other/SKILL.md", frontmatter={"name": "other", "description": "d"}, resources="dynamic"
+                )
+            ],
+            None,
+        ),
+    }
+
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+        skills, next_cursor = pages[params.cursor]
+        return ListSkillsResult(skills=skills, next_cursor=next_cursor)
+
+    return handler
+
+
+def _repeating_cursor_list_handler() -> Any:
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+        return ListSkillsResult(skills=[_skill()], next_cursor="same-cursor-forever")
+
+    return handler
+
+
+class _NonConformantGetSkill(Extension):
+    """A server that advertises the extension but answers `skills/get` with the wrong skill -
+    the case the SDK's own `Skills` extension already rules out server-side, so this
+    exercises `mcp.client.extensions.skills.SkillsClient.get_skill`'s own defense-in-depth check."""
+
+    identifier = EXTENSION_ID
+
+    def methods(self) -> Any:
+        async def handler(ctx: ServerRequestContext[Any, Any], params: GetSkillParams) -> GetSkillResult:
+            return GetSkillResult(skill=_skill())
+
+        return [MethodBinding(METHOD_GET, GetSkillParams, handler)]
+
+
+def _repeating_cursor_directory_handler() -> Any:
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ReadDirectoryParams) -> ReadDirectoryResult:
+        return ReadDirectoryResult(
+            resources=[Resource(uri="skill://git-workflow/references/A.md", name="A.md")],
+            next_cursor="same-cursor-forever",
+        )
+
+    return handler
+
+
+def _paginated_directory_handler() -> Any:
+    pages = {
+        None: (
+            [Resource(uri="skill://git-workflow/references/A.md", name="A.md")],
+            "page-2",
+        ),
+        "page-2": (
+            [Resource(uri="skill://git-workflow/references/B.md", name="B.md")],
+            None,
+        ),
+    }
+
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ReadDirectoryParams) -> ReadDirectoryResult:
+        resources, next_cursor = pages[params.cursor]
+        return ReadDirectoryResult(resources=resources, next_cursor=next_cursor)
+
+    return handler
+
+
+def _server(*, with_directory_read: bool = False) -> MCPServer:
+    server = MCPServer(
+        "catalog",
+        extensions=[
+            Skills(
+                list_skills=_paginated_list_handler(),
+                get_skill=_get_skill,
+                read_directory=_paginated_directory_handler() if with_directory_read else None,
+            )
+        ],
+    )
+    server.add_resource(TextResource(uri=_SKILL_URI, name="SKILL.md", text=_SKILL_CONTENT))
+    return server
+
+
+@asynccontextmanager
+async def _skills(server: MCPServer) -> AsyncIterator[SkillsClient]:
+    """Register the client `Skills` extension, connect, and yield the bound verbs."""
+    extension = ClientSkills()
+    async with Client(server, extensions=[extension]) as client:
+        yield client.extension(ClientSkills)
+
+
+async def test_list_skills_follows_next_cursor_to_completion() -> None:
+    async with _skills(_server()) as skills:
+        result = await skills.list_skills()
+    assert [s.uri for s in result] == [_SKILL_URI, "skill://other/SKILL.md"]
+
+
+async def test_list_skills_raises_on_a_server_that_repeats_its_cursor() -> None:
+    server = MCPServer(
+        "catalog", extensions=[Skills(list_skills=_repeating_cursor_list_handler(), get_skill=_get_skill)]
+    )
+    async with _skills(server) as skills:
+        with pytest.raises(ValueError, match="repeated"):
+            await skills.list_skills()
+
+
+async def test_list_skills_collapses_a_skill_repeated_across_pages() -> None:
+    """A catalog that changes between page fetches can surface the same skill on two pages; the
+    client returns it once (first occurrence) rather than failing or duplicating it."""
+
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+        if params.cursor is None:
+            return ListSkillsResult(skills=[_skill()], next_cursor="page-2")
+        return ListSkillsResult(skills=[_skill()], next_cursor=None)
+
+    server = MCPServer("catalog", extensions=[Skills(list_skills=handler, get_skill=_get_skill)])
+    async with _skills(server) as skills:
+        result = await skills.list_skills()
+    assert [s.uri for s in result] == [_SKILL_URI]
+
+
+async def test_list_skills_requires_the_extension_to_be_advertised() -> None:
+    """No `Skills` extension at all: the server never advertises `io.modelcontextprotocol/skills`."""
+    async with _skills(MCPServer("plain")) as skills:
+        with pytest.raises(ValueError, match="does not advertise"):
+            await skills.list_skills()
+
+
+async def test_get_skill_returns_the_matching_entry() -> None:
+    async with _skills(_server()) as skills:
+        skill = await skills.get_skill(_SKILL_URI)
+    assert skill.uri == _SKILL_URI
+
+
+async def test_get_skill_propagates_the_servers_unknown_skill_error() -> None:
+    async with _skills(_server()) as skills:
+        with pytest.raises(MCPError) as exc_info:
+            await skills.get_skill("skill://missing/SKILL.md")
+    assert exc_info.value.code == INVALID_PARAMS
+
+
+async def test_read_directory_follows_next_cursor_to_completion() -> None:
+    async with _skills(_server(with_directory_read=True)) as skills:
+        resources = await skills.read_directory("skill://git-workflow/references")
+    assert [r.uri for r in resources] == [
+        "skill://git-workflow/references/A.md",
+        "skill://git-workflow/references/B.md",
+    ]
+
+
+async def test_read_directory_accepts_distinct_children_with_the_same_name() -> None:
+    """SEP-2640 Directory Listing: child identity comes from URI, not Resource.name."""
+
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ReadDirectoryParams) -> ReadDirectoryResult:
+        return ReadDirectoryResult(
+            resources=[
+                Resource(uri="skill://git-workflow/references/a.md", name="example"),
+                Resource(uri="skill://git-workflow/references/b.md", name="example"),
+            ]
+        )
+
+    server = MCPServer(
+        "catalog",
+        extensions=[Skills(list_skills=_paginated_list_handler(), get_skill=_get_skill, read_directory=handler)],
+    )
+    async with _skills(server) as skills:
+        resources = await skills.read_directory("skill://git-workflow/references")
+    assert [resource.uri for resource in resources] == [
+        "skill://git-workflow/references/a.md",
+        "skill://git-workflow/references/b.md",
+    ]
+
+
+async def test_read_directory_requires_the_directory_read_setting() -> None:
+    """The extension is advertised, but without `directoryRead: true`."""
+    async with _skills(_server(with_directory_read=False)) as skills:
+        with pytest.raises(ValueError, match="directoryRead"):
+            await skills.read_directory("skill://git-workflow/references")
+
+
+async def test_read_directory_raises_on_a_server_that_repeats_its_cursor() -> None:
+    server = MCPServer(
+        "catalog",
+        extensions=[
+            Skills(
+                list_skills=_paginated_list_handler(),
+                get_skill=_get_skill,
+                read_directory=_repeating_cursor_directory_handler(),
+            )
+        ],
+    )
+    async with _skills(server) as skills:
+        with pytest.raises(ValueError, match="repeated"):
+            await skills.read_directory("skill://git-workflow/references")
+
+
+async def test_read_directory_collapses_a_child_repeated_across_pages() -> None:
+    """A changing directory can surface the same child on two pages; the client returns it once."""
+    child = Resource(uri="skill://git-workflow/references/A.md", name="A.md")
+
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ReadDirectoryParams) -> ReadDirectoryResult:
+        if params.cursor is None:
+            return ReadDirectoryResult(resources=[child], next_cursor="page-2")
+        return ReadDirectoryResult(resources=[child], next_cursor=None)
+
+    server = MCPServer(
+        "catalog",
+        extensions=[Skills(list_skills=_paginated_list_handler(), get_skill=_get_skill, read_directory=handler)],
+    )
+    async with _skills(server) as skills:
+        resources = await skills.read_directory("skill://git-workflow/references")
+    assert [r.uri for r in resources] == ["skill://git-workflow/references/A.md"]
+
+
+async def test_get_skill_rejects_a_mismatched_uri_from_a_non_conformant_server() -> None:
+    server = MCPServer("catalog", extensions=[_NonConformantGetSkill()])
+    async with _skills(server) as skills:
+        with pytest.raises(ValueError, match="returned skill"):
+            await skills.get_skill("skill://other/SKILL.md")
+
+
+async def test_get_skill_round_trips_a_dynamic_skill() -> None:
+    """SEP-2640 Resources: the `"dynamic"` marker survives the full server -> wire -> client
+    path — validated on both ends — with the union type intact, not coerced to a list or null."""
+    dynamic = Skill(
+        uri="skill://generated/SKILL.md",
+        frontmatter={"name": "generated", "description": "instructions generated on demand"},
+        resources="dynamic",
+    )
+
+    async def get_dynamic(ctx: ServerRequestContext[Any, Any], params: GetSkillParams) -> GetSkillResult:
+        # The server's own _handle_get already enforces the requested-uri match; this test only
+        # ever asks for `dynamic.uri`, so the handler just returns it.
+        return GetSkillResult(skill=dynamic)
+
+    server = MCPServer("catalog", extensions=[Skills(list_skills=_paginated_list_handler(), get_skill=get_dynamic)])
+    async with _skills(server) as skills:
+        skill = await skills.get_skill(dynamic.uri)
+    assert skill.resources == "dynamic"
+    assert skill.frontmatter["name"] == "generated"
+
+
+async def test_list_skills_starts_from_a_caller_supplied_cursor() -> None:
+    """A host resuming from a saved cursor: `list_skills` begins at that cursor rather than the
+    top, so only the pages after it come back (here, page 1's skill is skipped)."""
+    async with _skills(_server()) as skills:
+        result = await skills.list_skills(ListSkillsParams(cursor="page-2"))
+    assert [s.uri for s in result] == ["skill://other/SKILL.md"]
+
+
+async def test_list_skills_detects_a_server_repeating_the_caller_supplied_cursor() -> None:
+    """The starting cursor seeds the seen-cursor set: a server that hands back the very cursor
+    the caller resumed from is caught as a repeat on the first page, not chased a second time."""
+    calls = 0
+
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+        nonlocal calls
+        calls += 1
+        return ListSkillsResult(skills=[_skill()], next_cursor="resume-here")
+
+    server = MCPServer("catalog", extensions=[Skills(list_skills=handler, get_skill=_get_skill)])
+    async with _skills(server) as skills:
+        with pytest.raises(ValueError, match="repeated"):
+            await skills.list_skills(ListSkillsParams(cursor="resume-here"))
+    assert calls == 1
+
+
+async def test_list_skills_threads_request_meta_onto_every_page() -> None:
+    """A caller-supplied `_meta` rides along with each page request, not just the first."""
+    seen_meta: list[Any] = []
+
+    async def handler(ctx: ServerRequestContext[Any, Any], params: ListSkillsParams) -> ListSkillsResult:
+        seen_meta.append(params.meta)
+        if params.cursor is None:
+            return ListSkillsResult(skills=[_skill()], next_cursor="page-2")
+        return ListSkillsResult(
+            skills=[
+                Skill(
+                    uri="skill://other/SKILL.md", frontmatter={"name": "other", "description": "d"}, resources="dynamic"
+                )
+            ],
+            next_cursor=None,
+        )
+
+    server = MCPServer("catalog", extensions=[Skills(list_skills=handler, get_skill=_get_skill)])
+    async with _skills(server) as skills:
+        params = ListSkillsParams.model_validate({"_meta": {"progressToken": "t"}})
+        await skills.list_skills(params)
+    # `_meta` crosses the wire camelCase (`progressToken`), but the server deserializes it back
+    # through the meta model, which exposes the known field snake_case as `progress_token`; the
+    # transport also enriches `_meta` with its own keys. What matters is the caller's token
+    # reaching the server on both the first page and the cursor-following second one.
+    assert len(seen_meta) == 2
+    assert all(m is not None and m.get("progress_token") == "t" for m in seen_meta)
diff --git a/tests/client/test_client_extensions.py b/tests/client/test_client_extensions.py
index f80cfe8841..d2b79ef876 100644
--- a/tests/client/test_client_extensions.py
+++ b/tests/client/test_client_extensions.py
@@ -17,7 +17,7 @@
 
 from mcp.client import ClaimContext, ClientExtension, NotificationBinding, ResultClaim, advertise
 from mcp.client.client import Client
-from mcp.client.session import ClientRequestContext, _CallToolResultAdapter
+from mcp.client.session import ClientRequestContext, ClientSession, _CallToolResultAdapter
 from mcp.server import Server, ServerRequestContext
 from mcp.server.context import CallNext, HandlerResult
 from mcp.server.extension import Extension
@@ -59,6 +59,13 @@ def claims(self) -> Sequence[ResultClaim[Any]]:
         return [ResultClaim(result_type="voucher", model=VoucherResult, resolve=self._resolve)]
 
 
+class _SessionExtension(ClientExtension):
+    identifier = "com.example/session"
+
+    def bind(self, session: ClientSession) -> ClientSession:
+        return session
+
+
 class _VoucherIssuer(Extension):
     """Server half: rewrites every `tools/call` result into the vendor-claimed shape."""
 
@@ -166,6 +173,30 @@ def test_mapping_extensions_get_the_migration_error() -> None:
     )
 
 
+async def test_extension_returns_a_custom_extensions_typed_binding() -> None:
+    """SDK-defined: custom extensions can expose typed methods through Client.extension."""
+    async with Client(_add_server(), extensions=[advertise("com.example/other"), _SessionExtension()]) as client:
+        bound = client.extension(_SessionExtension)
+        assert_type(bound, ClientSession)
+        assert bound is client.session
+
+
+async def test_extension_rejects_an_unregistered_type() -> None:
+    """SDK-defined: a client cannot bind an extension it did not register."""
+    async with Client(_add_server()) as client:
+        with pytest.raises(ValueError) as exc_info:
+            client.extension(_SessionExtension)
... (795 more lines, see the PR)
```

## 4. FAIL_TO_PASS tests (first 40)

- `tests/client/extensions/test_skills.py::test_get_skill_propagates_the_servers_unknown_skill_error`
- `tests/client/extensions/test_skills.py::test_get_skill_rejects_a_mismatched_uri_from_a_non_conformant_server`
- `tests/client/extensions/test_skills.py::test_get_skill_returns_the_matching_entry`
- `tests/client/extensions/test_skills.py::test_get_skill_round_trips_a_dynamic_skill`
- `tests/client/extensions/test_skills.py::test_list_skills_collapses_a_skill_repeated_across_pages`
- `tests/client/extensions/test_skills.py::test_list_skills_detects_a_server_repeating_the_caller_supplied_cursor`
- `tests/client/extensions/test_skills.py::test_list_skills_follows_next_cursor_to_completion`
- `tests/client/extensions/test_skills.py::test_list_skills_raises_on_a_server_that_repeats_its_cursor`
- `tests/client/extensions/test_skills.py::test_list_skills_requires_the_extension_to_be_advertised`
- `tests/client/extensions/test_skills.py::test_list_skills_starts_from_a_caller_supplied_cursor`
- `tests/client/extensions/test_skills.py::test_list_skills_threads_request_meta_onto_every_page`
- `tests/client/extensions/test_skills.py::test_read_directory_accepts_distinct_children_with_the_same_name`
- `tests/client/extensions/test_skills.py::test_read_directory_collapses_a_child_repeated_across_pages`
- `tests/client/extensions/test_skills.py::test_read_directory_follows_next_cursor_to_completion`
- `tests/client/extensions/test_skills.py::test_read_directory_raises_on_a_server_that_repeats_its_cursor`
- `tests/client/extensions/test_skills.py::test_read_directory_requires_the_directory_read_setting`
- `tests/client/test_client_extensions.py::test_extension_rejects_an_unregistered_type`
- `tests/client/test_client_extensions.py::test_extension_requires_a_connected_client`
- `tests/client/test_client_extensions.py::test_extension_returns_a_custom_extensions_typed_binding`
- `tests/docs_src/test_skills.py::test_get_skill_answers_by_uri`
- `tests/docs_src/test_skills.py::test_get_skill_rejects_an_unknown_uri`
- `tests/docs_src/test_skills.py::test_list_skills_returns_the_registered_skill`
- `tests/docs_src/test_skills.py::test_the_skill_file_is_served_as_an_ordinary_resource`
- `tests/server/test_skills.py::test_directory_read_is_advertised_when_a_handler_is_supplied`
- `tests/server/test_skills.py::test_directory_read_is_not_advertised_without_a_handler`
- `tests/server/test_skills.py::test_directory_read_is_not_registered_without_a_handler`
- `tests/server/test_skills.py::test_directory_read_rejects_a_handler_result_with_a_grandchild`
- `tests/server/test_skills.py::test_directory_read_rejects_a_trailing_slash_uri`
- `tests/server/test_skills.py::test_directory_read_returns_the_handlers_children`
- `tests/server/test_skills.py::test_missing_uri_param_is_rejected_before_the_handler_runs`
- `tests/server/test_skills.py::test_skills_get_answers_for_a_skill_absent_from_the_listing`
- `tests/server/test_skills.py::test_skills_get_defaults_to_private_cache_scope_on_the_2026_07_28_wire`
- `tests/server/test_skills.py::test_skills_get_omits_cache_fields_on_a_legacy_wire`
- `tests/server/test_skills.py::test_skills_get_rejects_a_handler_that_returns_a_mismatched_uri`
- `tests/server/test_skills.py::test_skills_get_rejects_a_matching_but_non_conformant_skill`
- `tests/server/test_skills.py::test_skills_get_rejects_a_skill_mutated_after_the_result_is_built`
- `tests/server/test_skills.py::test_skills_get_rejects_a_uri_that_does_not_end_in_skill_md`
- `tests/server/test_skills.py::test_skills_get_rejects_an_unknown_uri_with_invalid_params`
- `tests/server/test_skills.py::test_skills_get_returns_the_matching_skill`
- `tests/server/test_skills.py::test_skills_list_defaults_to_private_cache_scope_on_the_2026_07_28_wire`
