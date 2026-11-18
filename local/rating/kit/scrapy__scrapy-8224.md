# scrapy__scrapy-8224

- repo: `scrapy/scrapy`, created: 2026-09-26, base_commit: `a951e1f961f9`
- PR: https://github.com/scrapy/scrapy/pull/8224
- issue: https://github.com/scrapy/scrapy/issues/6895
- FAIL_TO_PASS: 6 tests, PASS_TO_PASS: 36 tests, collection_error: **no**

## 1. Issue (what the agent sees)

request slips through dupefilter after retry/redirect
<!--

Thanks for taking an interest in Scrapy!

If you have a question that starts with "How to...", please see the Scrapy Community page: https://scrapy.org/community/.
The GitHub issue tracker's purpose is to deal with bug reports and feature requests for the project itself.

Keep in mind that by filing an issue, you are expected to comply with Scrapy's Code of Conduct, including treating everyone with respect: https://github.com/scrapy/scrapy/blob/master/CODE_OF_CONDUCT.md

The following is a suggested template to structure your issue, you can find more guidelines at https://doc.scrapy.org/en/latest/contributing.html#reporting-bugs

-->

### Description

With the default configuration urls are sometimes crawled twice.

### Steps to Reproduce

I'm using server.py
```
from __future__ import annotations

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, RedirectResponse


app = FastAPI()


@app.get("/sbn/")
def sbn_slash():
    return RedirectResponse("/bn")


@app.get("/sbn")
def sbn():
    return HTMLResponse("I am /sbn")


first_time = True


@app.get("/bn")
def bn():
    global first_time
    if first_time:
        first_time = False
        return HTMLResponse("not ready", 503)
    else:
        return RedirectResponse("/sbn")
```

And crawler.py
```
import scrapy.crawler


class QuotesSpider(scrapy.Spider):
    name = "quotes"

    async def start(self):
        urls = ["http://localhost/sbn", "http://localhost/sbn/"]
        for url in urls:
            yield scrapy.Request(url=url, callback=self.parse)

    def parse(self, response):
        self.log(f"parsed {response.url}")


if __name__ == "__main__":
    p = scrapy.crawler.CrawlerProcess()
    p.crawl(QuotesSpider)
    p.start()
```

**Expected behavior:** [What you expect to happen]

When I'm running `python crawler.py` I would expect the output:
```
[scrapy.dupefilters] DEBUG: Filtered duplicate request: <GET http://localhost/sbn> - no more duplicates will be shown (see DUPEFILTER_DEBUG to show all duplicates)
[quotes] DEBUG: parsed http://localhost/sbn
```

**Actual behavior:** [What actually happens]
The first time this runs, I'm actually getting:
```
[quotes] DEBUG: parsed http://localhost/sbn
[quotes] DEBUG: parsed http://localhost/sbn
```

**Reproduces how often:** [What percentage of the time does it reproduce?]
reliably reproducible

### Versions

Scrapy       : 2.13.2
lxml         : 5.4.0
libxml2      : 2.13.8
cssselect    : 1.3.0
parsel       : 1.10.0
w3lib        : 2.3.1
Twisted      : 25.5.0
Python       : 3.12.3 (main, May 26 2025, 18:50:19) [GCC 13.3.0]
pyOpenSSL    : 25.1.0 (OpenSSL 3.5.0 8 Apr 2025)
cryptography : 45.0.4
Platform     : Linux-6.11.0-26-generic-x86_64-with-glibc2.39

### Additional context

Any additional information, configuration, data or output from commands that might be necessary to reproduce or understand the issue. Please try not to include screenshots of code or the command line, paste the contents as text instead. You can use [GitHub Flavored Markdown](https://help.github.com/en/articles/creating-and-highlighting-code-blocks) to make the text look better.

## 2. Gold patch

```diff
diff --git a/docs/topics/request-response.rst b/docs/topics/request-response.rst
index 39f8701f176..869dbb55ff7 100644
--- a/docs/topics/request-response.rst
+++ b/docs/topics/request-response.rst
@@ -896,6 +896,7 @@ Those are:
 * :reqmeta:`referrer_policy`
 * :reqmeta:`retry_times`
 * :reqmeta:`rule`
+* :reqmeta:`skip_dupefilter_once`
 * :reqmeta:`verbatim_url`
 
 Scrapy components also use meta keys whose name starts with an underscore, such
@@ -1025,6 +1026,20 @@ The meta key is used set retry times per request. When set, the
 :reqmeta:`max_retry_times` meta key takes higher precedence over the
 :setting:`RETRY_TIMES` setting.
 
+.. reqmeta:: skip_dupefilter_once
+
+skip_dupefilter_once
+--------------------
+
+.. versionadded:: VERSION
+
+Set this key to ``True`` to skip :setting:`duplicate filtering
+<DUPEFILTER_CLASS>` for this request. The :ref:`scheduler <topics-scheduler>`
+removes this key, so requests derived from this request, e.g. redirects, are
+filtered as usual.
+
+:func:`~scrapy.downloadermiddlewares.retry.get_retry_request` sets this key.
+
 .. reqmeta:: verbatim_url
 
 verbatim_url
diff --git a/scrapy/core/engine.py b/scrapy/core/engine.py
index f9e9efd9acb..d45024bf39a 100644
--- a/scrapy/core/engine.py
+++ b/scrapy/core/engine.py
@@ -64,6 +64,21 @@
 logger = logging.getLogger(__name__)
 
 
+def _supports_skip_dupefilter_once(scheduler: BaseScheduler) -> bool:
+    # A subclass that overrides enqueue_request() does not inherit support.
+    cls = type(scheduler)
+    owner = next(
+        (
+            c
+            for c in cls.__mro__
+            if "enqueue_request" in vars(c)
+            or "supports_skip_dupefilter_once" in vars(c)
+        ),
+        cls,
+    )
+    return bool(vars(owner).get("supports_skip_dupefilter_once", False))
+
+
 class EngineState(Enum):
     """The lifecycle state of :class:`ExecutionEngine`.
 
@@ -173,6 +188,7 @@ def __init__(
         self.signals: SignalManager = crawler.signals
         self.logformatter: LogFormatter = crawler.logformatter
         self._slot: _Slot | None = None
+        self._warned_skip_dupefilter_once: bool = False
         self.spider: Spider | None = None
         self._state: EngineState = EngineState.CREATED
         # The reason and error flag of a close requested while the spider is
@@ -581,7 +597,24 @@ def _schedule_request(self, request: Request) -> None:
         for _, result in request_scheduled_result:
             if isinstance(result, Failure) and isinstance(result.value, IgnoreRequest):
                 return
-        if not self._slot.scheduler.enqueue_request(request):  # type: ignore[union-attr]
+        assert self._slot is not None
+        if request.meta.get(
+            "skip_dupefilter_once"
+        ) and not _supports_skip_dupefilter_once(self._slot.scheduler):
+            del request.meta["skip_dupefilter_once"]
+            request.dont_filter = True
+            if not self._warned_skip_dupefilter_once:
+                self._warned_skip_dupefilter_once = True
+                warnings.warn(
+                    f"{global_object_name(type(self._slot.scheduler))} does "
+                    f"not set supports_skip_dupefilter_once to True, so "
+                    f"requests with the skip_dupefilter_once meta key get "
+                    f"dont_filter=True instead, which requests derived from "
+                    f"them inherit. Support for such schedulers is deprecated.",
+                    ScrapyDeprecationWarning,
+                    stacklevel=2,
+                )
+        if not self._slot.scheduler.enqueue_request(request):
             self.signals.send_catch_log(
                 signals.request_dropped, request=request, spider=self.spider
             )
diff --git a/scrapy/core/scheduler.py b/scrapy/core/scheduler.py
index ff119215a4d..27b2c4326fd 100644
--- a/scrapy/core/scheduler.py
+++ b/scrapy/core/scheduler.py
@@ -65,6 +65,16 @@ class BaseScheduler(metaclass=BaseSchedulerMeta):
     The methods defined in this class constitute the minimal interface that the Scrapy engine will interact with.
     """
 
+    supports_skip_dupefilter_once: bool = False
+    """Must be ``True``, to declare that :meth:`enqueue_request` handles the
+    :reqmeta:`skip_dupefilter_once` meta key.
+
+    It is not inherited by subclasses that override :meth:`enqueue_request`,
+    which must set it again.
+
+    .. versionadded:: VERSION
+    """
+
     @classmethod
     def from_crawler(cls, crawler: Crawler) -> Self:
         """
@@ -102,12 +112,19 @@ def enqueue_request(self, request: Request) -> bool:
         """
         Process a request received by the engine.
 
+        .. versionchanged:: VERSION
+           Must handle the :reqmeta:`skip_dupefilter_once` meta key.
+
         Return ``True`` if the request is stored correctly, ``False`` otherwise.
 
         If ``False``, the engine will fire a ``request_dropped`` signal, and
         will not make further attempts to schedule the request at a later time.
         For reference, the default Scrapy scheduler returns ``False`` when the
         request is rejected by the dupefilter.
+
+        If the request has the :reqmeta:`skip_dupefilter_once` meta key, remove
+        it and, if it was ``True``, do not filter out the request as a
+        duplicate. See also :attr:`supports_skip_dupefilter_once`.
         """
         raise NotImplementedError
 
@@ -254,6 +271,8 @@ class Scheduler(BaseScheduler):
     which may also write data inside the job directory.
     """
 
+    supports_skip_dupefilter_once = True
+
     @classmethod
     def from_crawler(cls, crawler: Crawler) -> Self:
         dupefilter_cls = load_object(crawler.settings["DUPEFILTER_CLASS"])
@@ -380,7 +399,12 @@ def enqueue_request(self, request: Request) -> bool:
 
         Return ``True`` if the request was stored successfully, ``False`` otherwise.
         """
-        if not request.dont_filter and self.df.request_seen(request):
+        skip_dupefilter = request.meta.pop("skip_dupefilter_once", False)
+        if (
+            not request.dont_filter
+            and not skip_dupefilter
+            and self.df.request_seen(request)
+        ):
             self.df.log(request, self.spider)
             return False
         dqok = self._dqpush(request)
diff --git a/scrapy/downloadermiddlewares/retry.py b/scrapy/downloadermiddlewares/retry.py
index b8eed4da909..01b24f4bd70 100644
--- a/scrapy/downloadermiddlewares/retry.py
+++ b/scrapy/downloadermiddlewares/retry.py
@@ -108,7 +108,7 @@ def parse(self, response):
         )
         new_request: Request = request.copy()
         new_request.meta["retry_times"] = retry_times
-        new_request.dont_filter = True
+        new_request.meta["skip_dupefilter_once"] = True
         if priority_adjust is None:
             priority_adjust = settings.getint("RETRY_PRIORITY_ADJUST")
         new_request.priority = request.priority + priority_adjust
```

## 3. Test patch

```diff
diff --git a/tests/test_downloadermiddleware_retry.py b/tests/test_downloadermiddleware_retry.py
index a9dc1525a5a..6cae9d4df52 100644
--- a/tests/test_downloadermiddleware_retry.py
+++ b/tests/test_downloadermiddleware_retry.py
@@ -1,17 +1,20 @@
 from __future__ import annotations
 
 import logging
-from typing import Any, cast
+from typing import TYPE_CHECKING, Any, cast
+from urllib.parse import urlencode
 
 import pytest
 from twisted.internet.error import ConnectError, ConnectionDone, ConnectionLost
 
+from scrapy.core.scheduler import Scheduler
 from scrapy.downloadermiddlewares.retry import RetryMiddleware, get_retry_request
 from scrapy.exceptions import (
     CannotResolveHostError,
     DownloadConnectionRefusedError,
     DownloadTimeoutError,
     IgnoreRequest,
+    ScrapyDeprecationWarning,
 )
 from scrapy.http import Request, Response
 from scrapy.settings.default_settings import RETRY_EXCEPTIONS
@@ -19,6 +22,12 @@
 from scrapy.utils.misc import build_from_crawler
 from scrapy.utils.spider import DefaultSpider
 from scrapy.utils.test import get_crawler
+from tests.utils.decorators import coroutine_test
+
+if TYPE_CHECKING:
+    from collections.abc import AsyncIterator
+
+    from tests.mockserver.http import MockServer
 
 
 class TestRetry:
@@ -308,7 +317,7 @@ def test_basic_usage(self, caplog: pytest.LogCaptureFixture) -> None:
             )
         assert isinstance(new_request, Request)
         assert new_request != request
-        assert new_request.dont_filter
+        assert new_request.meta["skip_dupefilter_once"] is True
         expected_retry_times = 1
         assert new_request.meta["retry_times"] == expected_retry_times
         assert new_request.priority == -1
@@ -358,7 +367,7 @@ def test_one_retry(self, caplog: pytest.LogCaptureFixture) -> None:
             )
         assert isinstance(new_request, Request)
         assert new_request != request
-        assert new_request.dont_filter
+        assert new_request.meta["skip_dupefilter_once"] is True
         expected_retry_times = 1
         assert new_request.meta["retry_times"] == expected_retry_times
         assert new_request.priority == -1
@@ -392,7 +401,7 @@ def test_two_retries(self, caplog: pytest.LogCaptureFixture) -> None:
                 )
             assert isinstance(new_request, Request)
             assert new_request != request
-            assert new_request.dont_filter
+            assert new_request.meta["skip_dupefilter_once"] is True
             expected_retry_times = index + 1
             assert new_request.meta["retry_times"] == expected_retry_times
             assert new_request.priority == -expected_retry_times
@@ -751,3 +760,74 @@ def test_custom_stats_key(self):
             f"{stats_key}/reason_count/{expected_reason}",
         ):
             assert spider.crawler.stats.get_value(stat) == 1
+
+
+class _RetryThenRedirectSpider(Spider):
+    """Retries two requests whose retries redirect to an already-seen URL."""
+
+    name = "retry_then_redirect"
+    mockserver: MockServer
+
+    def __init__(self, *args: Any, **kwargs: Any) -> None:
+        super().__init__(*args, **kwargs)
+        self.seen_parsed = 0
+
+    async def start(self) -> AsyncIterator[Any]:
+        seen = self.mockserver.url("/status?n=200")
+        yield Request(seen)
+        for n in range(2):
+            url = self.mockserver.url(
+                "/redirect-to?" + urlencode({"goto": seen, "n": n})
+            )
+            yield Request(
+                url, meta={"dont_redirect": True, "handle_httpstatus_list": [302]}
+            )
+
+    def parse(self, response: Response) -> Request | None:
+        if response.status == 200:
+            self.seen_parsed += 1
+            return None
+        assert response.request is not None
+        request = get_retry_request(response.request, spider=self)
+        assert request is not None
+        del request.meta["dont_redirect"]
+        del request.meta["handle_httpstatus_list"]
+        return request
+
+
+class _LegacyScheduler(Scheduler):
+    supports_skip_dupefilter_once = False
+
+
+class _OverridingScheduler(Scheduler):
+    def enqueue_request(self, request: Request) -> bool:
+        if not request.dont_filter and self.df.request_seen(request):
+            self.df.log(request, self.spider)
+            return False
+        self._mqpush(request)
+        return True
+
+
+@coroutine_test
+async def test_retry_redirect_dupefilter(mockserver: MockServer) -> None:
+    crawler = get_crawler(_RetryThenRedirectSpider)
+    await crawler.crawl_async(mockserver=mockserver)
+    assert crawler.spider is not None
+    assert cast("_RetryThenRedirectSpider", crawler.spider).seen_parsed == 1
+    assert crawler.stats is not None
+    assert crawler.stats.get_value("dupefilter/filtered") == 2
+
+
+@pytest.mark.parametrize("scheduler", [_LegacyScheduler, _OverridingScheduler])
+@coroutine_test
+async def test_retry_redirect_dupefilter_legacy_scheduler(
+    mockserver: MockServer, scheduler: type[Scheduler]
+) -> None:
+    crawler = get_crawler(_RetryThenRedirectSpider, {"SCHEDULER": scheduler})
+    with pytest.warns(
+        ScrapyDeprecationWarning, match="supports_skip_dupefilter_once"
+    ) as record:
+        await crawler.crawl_async(mockserver=mockserver)
+    assert sum("supports_skip_dupefilter_once" in str(w.message) for w in record) == 1
+    assert crawler.spider is not None
+    assert cast("_RetryThenRedirectSpider", crawler.spider).seen_parsed == 3
```

## 4. FAIL_TO_PASS tests

- `tests/test_downloadermiddleware_retry.py::TestGetRetryRequest::test_basic_usage`
- `tests/test_downloadermiddleware_retry.py::TestGetRetryRequest::test_one_retry`
- `tests/test_downloadermiddleware_retry.py::TestGetRetryRequest::test_two_retries`
- `tests/test_downloadermiddleware_retry.py::test_retry_redirect_dupefilter`
- `tests/test_downloadermiddleware_retry.py::test_retry_redirect_dupefilter_legacy_scheduler[_LegacyScheduler]`
- `tests/test_downloadermiddleware_retry.py::test_retry_redirect_dupefilter_legacy_scheduler[_OverridingScheduler]`
