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


