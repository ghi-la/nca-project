#!/bin/bash
set -uxo pipefail
cd /testbed
git config --global --add safe.directory /testbed
git status
git -c core.fileMode=false diff 08095791f0c8b8e6a0e8a137ca5ab4a511259ec7
git checkout 08095791f0c8b8e6a0e8a137ca5ab4a511259ec7 -- tests/client/auth/extensions/test_identity_assertion.py
git apply -v - <<'EOF_NCA_TEST_PATCH_7f3a'
diff --git a/tests/client/auth/extensions/test_identity_assertion.py b/tests/client/auth/extensions/test_identity_assertion.py
index d4c965edc5..f4f9b6080c 100644
--- a/tests/client/auth/extensions/test_identity_assertion.py
+++ b/tests/client/auth/extensions/test_identity_assertion.py
@@ -11,6 +11,7 @@
 
 import httpx2
 import pytest
+from inline_snapshot import snapshot
 
 from mcp.client.auth import OAuthFlowError, OAuthTokenError
 from mcp.client.auth.extensions.identity_assertion import IdentityAssertionOAuthProvider, _origin
@@ -377,7 +378,7 @@ def test_empty_client_secret_is_rejected() -> None:
     async def assertion_provider(audience: str, resource: str) -> str:
         raise NotImplementedError
 
-    with pytest.raises(ValueError, match="client_secret is required"):
+    with pytest.raises(ValueError) as exc_info:
         IdentityAssertionOAuthProvider(
             server_url=f"{RS}/mcp",
             storage=InMemoryStorage(),
@@ -387,6 +388,10 @@ async def assertion_provider(audience: str, resource: str) -> str:
             assertion_provider=assertion_provider,
         )
 
+    assert str(exc_info.value) == snapshot(
+        "client_secret is required: this provider supports confidential clients only"
+    )
+
 
 def test_empty_issuer_is_rejected() -> None:
     async def assertion_provider(audience: str, resource: str) -> str:
EOF_NCA_TEST_PATCH_7f3a
: '>>>>> Start Test Output'
pytest -rA --color=no -p no:cacheprovider --continue-on-collection-errors -p no:pretty tests/client/auth/extensions/test_identity_assertion.py
: '>>>>> End Test Output'
git checkout 08095791f0c8b8e6a0e8a137ca5ab4a511259ec7 -- tests/client/auth/extensions/test_identity_assertion.py
