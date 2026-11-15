#!/bin/bash
set -uxo pipefail
cd /testbed
git config --global --add safe.directory /testbed
git status
git -c core.fileMode=false diff 5d789b24f994bcdfca97c34d976c73739e064849
git checkout 5d789b24f994bcdfca97c34d976c73739e064849 -- tests/test_utils_url.py
git apply -v - <<'EOF_NCA_TEST_PATCH_7f3a'
diff --git a/tests/test_utils_url.py b/tests/test_utils_url.py
index 403fd61763f..830d691e2aa 100644
--- a/tests/test_utils_url.py
+++ b/tests/test_utils_url.py
@@ -1,10 +1,13 @@
 from __future__ import annotations
 
 import pytest
+import w3lib.url
 
+from scrapy.exceptions import ScrapyDeprecationWarning
 from scrapy.linkextractors import IGNORED_EXTENSIONS
 from scrapy.spiders import Spider
 from scrapy.utils.url import (
+    _add_http_if_no_scheme,
     _is_filesystem_path,
     add_http_if_no_scheme,
     guess_scheme,
@@ -162,7 +165,22 @@ def test_url_has_any_extension(url: str, expected: bool) -> None:
     ],
 )
 def test_add_http_if_no_scheme(url: str, expected: str) -> None:
-    assert add_http_if_no_scheme(url) == expected
+    assert _add_http_if_no_scheme(url) == expected
+
+
+def test_add_http_if_no_scheme_deprecated(monkeypatch: pytest.MonkeyPatch) -> None:
+    monkeypatch.setattr(
+        w3lib.url, "add_http_if_no_scheme", lambda url: url, raising=False
+    )
+    with pytest.warns(
+        ScrapyDeprecationWarning, match="use w3lib.url.add_http_if_no_scheme"
+    ):
+        assert add_http_if_no_scheme("www.example.com") == "http://www.example.com"
+
+
+def test_add_http_if_no_scheme_not_deprecated(monkeypatch: pytest.MonkeyPatch) -> None:
+    monkeypatch.delattr(w3lib.url, "add_http_if_no_scheme", raising=False)
+    assert add_http_if_no_scheme("www.example.com") == "http://www.example.com"
 
 
 @pytest.mark.parametrize(
EOF_NCA_TEST_PATCH_7f3a
: '>>>>> Start Test Output'
pytest -rA --color=no -p no:cacheprovider tests/test_utils_url.py
: '>>>>> End Test Output'
git checkout 5d789b24f994bcdfca97c34d976c73739e064849 -- tests/test_utils_url.py
