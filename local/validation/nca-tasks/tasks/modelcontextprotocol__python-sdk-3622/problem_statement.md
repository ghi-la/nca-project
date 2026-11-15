Server TokenHandler rejects the jwt-bearer (ID-JAG) grant from public CIMD clients, which the enterprise-managed authorization extension permits

### Problem

With `identity_assertion_enabled=True`, `TokenHandler` rejects every `urn:ietf:params:oauth:grant-type:jwt-bearer` request from a client that has no stored `client_secret`:

```python
# mcp/server/auth/handlers/token.py
if not client_info.client_secret:
    return self.response(
        TokenErrorResponse(
            error="unauthorized_client",
            error_description="The JWT bearer grant requires a confidential client",
        )
    )
```

A client identified by a Client ID Metadata Document (CIMD) cannot hold a shared secret (CIMD forbids `client_secret_*`), so the only methods open to it are `none` and `private_key_jwt`. Since `ClientAuthenticator` does not implement `private_key_jwt`, a CIMD client can never complete the ID-JAG exchange against an SDK-based authorization server.

This blocks real clients. At least one widely deployed MCP client documents its enterprise-managed authorization token request as carrying only `grant_type`, `assertion`, `client_id` (a CIMD URL), `scope` and `resource`, with no client secret and no client assertion.

### What the extension spec says

`modelcontextprotocol/ext-auth`, `specification/stable/enterprise-managed-authorization.mdx`, section 5 (Access Token Request):

> The MCP Client authenticates with its credentials as registered with the Resource Authorization Server.
>
> If the MCP Client is not pre-registered with the Resource Authorization Server, then it can use its Client ID Metadata Document as its client ID, and optionally authenticate using private_key_jwt.

Its example request has no client authentication at all:

```
grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer
&assertion=eyJhbGciOiJIUzI1NiIsI...
&client_id=https://client.example.com/client.json
```

So for a CIMD client, client authentication at this step is optional. The current check is stricter than the spec and turns away the case the spec calls out by name.

### Expected

A CIMD client with `token_endpoint_auth_method="none"` can exchange a valid ID-JAG issued for its `client_id`. Pre-registered clients keep today's behavior (they must authenticate as registered).

### Related

- #2260 / #2261 (`none` missing from `token_endpoint_auth_methods_supported`)
- #1842 / #1846 (`none` handling in `ClientAuthenticator`)



AI disclosure: I used an AI coding assistant to draft this issue; I have reviewed it and can answer for it.

