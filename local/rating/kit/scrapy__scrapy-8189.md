# scrapy__scrapy-8189

- repo: `scrapy/scrapy`, created: 2026-09-21, base_commit: `5d789b24f994`
- PR: https://github.com/scrapy/scrapy/pull/8189
- issue: https://github.com/scrapy/scrapy/issues/2186
- FAIL_TO_PASS: 113 tests, PASS_TO_PASS: 0 tests, collection_error: **yes**

## 1. Issue (what the agent sees)

move more functions from scrapy.utils.url to w3lib
Hey,

What do you think about moving `add_http_if_no_scheme` and `escape_ajax` functions to w3lib?

## 2. Gold patch

```diff
diff --git a/scrapy/core/downloader/handlers/_base_streaming.py b/scrapy/core/downloader/handlers/_base_streaming.py
index 6e4dd687061..c7f4c82d8d1 100644
--- a/scrapy/core/downloader/handlers/_base_streaming.py
+++ b/scrapy/core/downloader/handlers/_base_streaming.py
@@ -23,7 +23,7 @@
     normalize_bind_address,
 )
 from scrapy.utils.asyncio import is_asyncio_available
-from scrapy.utils.url import add_http_if_no_scheme
+from scrapy.utils.url import _add_http_if_no_scheme
 
 from ._base_http import BaseHttpDownloadHandler
 
@@ -286,7 +286,7 @@ def _extract_proxy(request: Request) -> tuple[str | None, str | None]:
         proxy: str | None = request.meta.get("proxy")
         if not proxy:
             return None, None
-        proxy = add_http_if_no_scheme(proxy)
+        proxy = _add_http_if_no_scheme(proxy)
         auth_header: bytes | None = request.headers.get(b"Proxy-Authorization")
         return proxy, auth_header.decode("ascii") if auth_header else None
 
diff --git a/scrapy/core/downloader/handlers/http11.py b/scrapy/core/downloader/handlers/http11.py
index f3eaa3411ec..37b27c8a699 100644
--- a/scrapy/core/downloader/handlers/http11.py
+++ b/scrapy/core/downloader/handlers/http11.py
@@ -62,7 +62,7 @@
 from scrapy.utils.deprecate import warn_on_deprecated_spider_attribute
 from scrapy.utils.httpobj import urlparse_cached
 from scrapy.utils.python import to_bytes, to_unicode
-from scrapy.utils.url import add_http_if_no_scheme
+from scrapy.utils.url import _add_http_if_no_scheme
 
 from ._base_http import BaseHttpDownloadHandler
 
@@ -456,7 +456,7 @@ def _get_agent(self, request: Request, timeout: float) -> Agent:
         bindaddress = normalize_bind_address(bindaddress)
         proxy = request.meta.get("proxy")
         if proxy:
-            proxy = add_http_if_no_scheme(proxy)
+            proxy = _add_http_if_no_scheme(proxy)
             proxy_parsed = urlparse(proxy)
             proxy_host = proxy_parsed.hostname
             proxy_port = proxy_parsed.port
diff --git a/scrapy/utils/url.py b/scrapy/utils/url.py
index 21ef4aac7ed..de2e38728c3 100644
--- a/scrapy/utils/url.py
+++ b/scrapy/utils/url.py
@@ -10,8 +10,11 @@
 from typing import TYPE_CHECKING, TypeAlias
 from urllib.parse import ParseResult, urlparse, urlunparse
 
+import w3lib.url
 from w3lib.url import any_to_uri, parse_url
 
+from scrapy.exceptions import ScrapyDeprecationWarning
+
 if TYPE_CHECKING:
     from collections.abc import Iterable
 
@@ -57,17 +60,25 @@ def url_has_any_extension(url: UrlT, extensions: Iterable[str]) -> bool:
     return any(lowercase_path.endswith(ext) for ext in extensions)
 
 
-def add_http_if_no_scheme(url: str) -> str:
-    """Add http as the default scheme if it is missing from the url."""
-    match = re.match(r"^\w+://", url, flags=re.IGNORECASE)
-    if not match:
-        parts = urlparse(url)
-        scheme = "http:" if parts.netloc else "http://"
+def _add_http_if_no_scheme(url: str) -> str:
+    if not re.match(r"^\w+://", url, flags=re.IGNORECASE):
+        scheme = "http:" if urlparse(url).netloc else "http://"
         url = scheme + url
-
     return url
 
 
+def add_http_if_no_scheme(url: str) -> str:
+    """Add http as the default scheme if it is missing from the url."""
+    if hasattr(w3lib.url, "add_http_if_no_scheme"):
+        warnings.warn(
+            "scrapy.utils.url.add_http_if_no_scheme() is deprecated, use "
+            "w3lib.url.add_http_if_no_scheme() instead.",
+            ScrapyDeprecationWarning,
+            stacklevel=2,
+        )
+    return _add_http_if_no_scheme(url)
+
+
 def _is_posix_path(string: str) -> bool:
     return bool(
         re.match(
@@ -115,7 +126,7 @@ def guess_scheme(url: str) -> str:
     http:// otherwise."""
     if _is_filesystem_path(url):
         return any_to_uri(url)
-    return add_http_if_no_scheme(url)
+    return _add_http_if_no_scheme(url)
 
 
 def strip_url(
```

## 3. Test patch

```diff
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
```

## 4. FAIL_TO_PASS tests (first 40)

- `tests/test_utils_url.py::TestStripUrl::test_credentials[ftp://me:user%40domain.com@www.example.com/index.html?somekey=somevalue#section-ftp://www.example.com/index.html?somekey=somevalue]`
- `tests/test_utils_url.py::TestStripUrl::test_credentials[ftp://username:password@www.example.com/index.html?somekey=somevalue#section-ftp://www.example.com/index.html?somekey=somevalue]`
- `tests/test_utils_url.py::TestStripUrl::test_credentials[http://username%40@www.example.com/index.html?somekey=somevalue#section-http://www.example.com/index.html?somekey=somevalue]`
- `tests/test_utils_url.py::TestStripUrl::test_credentials[http://username@www.example.com/index.html?somekey=somevalue#section-http://www.example.com/index.html?somekey=somevalue]`
- `tests/test_utils_url.py::TestStripUrl::test_credentials[https://username%3Apass:@www.example.com/index.html?somekey=somevalue#section-https://www.example.com/index.html?somekey=somevalue]`
- `tests/test_utils_url.py::TestStripUrl::test_credentials[https://username:@www.example.com/index.html?somekey=somevalue#section-https://www.example.com/index.html?somekey=somevalue]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports[ftp://user:21@www.example.com:21/file.txt-ftp://user:21@www.example.com/file.txt]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports[ftp://username:password@www.example.com:21/file.txt-ftp://username:password@www.example.com/file.txt]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports[ftp://username:password@www.example.com:221/file.txt-ftp://username:password@www.example.com:221/file.txt]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports[http://user:80@www.example.com:80/index.html-http://user:80@www.example.com/index.html]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports[http://username:password@www.example.com:443/index.html-http://username:password@www.example.com:443/index.html]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports[http://username:password@www.example.com:80/index.html-http://username:password@www.example.com/index.html]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports[http://username:password@www.example.com:8080/index.html-http://username:password@www.example.com:8080/index.html]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports[https://user:443@www.example.com:443/index.html-https://user:443@www.example.com/index.html]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports[https://username:password@www.example.com:442/index.html-https://username:password@www.example.com:442/index.html]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports[https://username:password@www.example.com:443/index.html-https://username:password@www.example.com/index.html]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports[https://username:password@www.example.com:80/index.html-https://username:password@www.example.com:80/index.html]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports_creds_off[ftp://username:password@www.example.com:21/file.txt-ftp://www.example.com/file.txt]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports_creds_off[ftp://username:password@www.example.com:221/file.txt-ftp://www.example.com:221/file.txt]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports_creds_off[http://username:password@www.example.com:443/index.html?somekey=somevalue&someotherkey=sov#section-http://www.example.com:443/index.html?somekey=somevalue&someotherkey=sov]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports_creds_off[http://username:password@www.example.com:80/index.html?somekey=somevalue#section-http://www.example.com/index.html?somekey=somevalue]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports_creds_off[http://username:password@www.example.com:8080/index.html#section-http://www.example.com:8080/index.html]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports_creds_off[https://username:password@www.example.com:442/index.html-https://www.example.com:442/index.html]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports_creds_off[https://username:password@www.example.com:443/index.html-https://www.example.com/index.html]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports_creds_off[https://username:password@www.example.com:80/index.html-https://www.example.com:80/index.html]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports_keep[ftp://username:password@www.example.com:21/file.txt-ftp://username:password@www.example.com:21/file.txt]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports_keep[ftp://username:password@www.example.com:221/file.txt-ftp://username:password@www.example.com:221/file.txt]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports_keep[http://username:password@www.example.com:443/index.html-http://username:password@www.example.com:443/index.html]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports_keep[http://username:password@www.example.com:80/index.html?somekey=somevalue&someotherkey=sov#section-http://username:password@www.example.com:80/index.html?somekey=somevalue&someotherkey=sov]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports_keep[http://username:password@www.example.com:8080/index.html?somekey=somevalue&someotherkey=sov#section-http://username:password@www.example.com:8080/index.html?somekey=somevalue&someotherkey=sov]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports_keep[https://username:password@www.example.com:442/index.html-https://username:password@www.example.com:442/index.html]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports_keep[https://username:password@www.example.com:443/index.html-https://username:password@www.example.com:443/index.html]`
- `tests/test_utils_url.py::TestStripUrl::test_default_ports_keep[https://username:password@www.example.com:80/index.html-https://username:password@www.example.com:80/index.html]`
- `tests/test_utils_url.py::TestStripUrl::test_fragments`
- `tests/test_utils_url.py::TestStripUrl::test_noop[http://www.example.com/index.html?somekey=somevalue]`
- `tests/test_utils_url.py::TestStripUrl::test_noop[http://www.example.com/index.html]`
- `tests/test_utils_url.py::TestStripUrl::test_origin_only[http://username:password@www.example.com/index.html-http://www.example.com/]`
- `tests/test_utils_url.py::TestStripUrl::test_origin_only[http://username:password@www.example.com:80/foo/bar?query=value#somefrag-http://www.example.com/]`
- `tests/test_utils_url.py::TestStripUrl::test_origin_only[http://username:password@www.example.com:8008/foo/bar?query=value#somefrag-http://www.example.com:8008/]`
- `tests/test_utils_url.py::TestStripUrl::test_origin_only[https://username:password@www.example.com:443/index.html-https://www.example.com/]`
