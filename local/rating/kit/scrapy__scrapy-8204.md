# scrapy__scrapy-8204

- repo: `scrapy/scrapy`, created: 2026-09-21, base_commit: `7af73d44bf6b`
- PR: https://github.com/scrapy/scrapy/pull/8204
- issue: https://github.com/scrapy/scrapy/issues/1241
- FAIL_TO_PASS: 6 tests, PASS_TO_PASS: 53 tests, collection_error: **no**

## 1. Issue (what the agent sees)

Provide a way to propagate an exit code from a Spider
I think we need a way to propagate the exit code from the Spider.

Based on: #1231

## 2. Gold patch

```diff
diff --git a/docs/topics/stats.rst b/docs/topics/stats.rst
index fe4f82da75e..6d61f283b61 100644
--- a/docs/topics/stats.rst
+++ b/docs/topics/stats.rst
@@ -317,6 +317,18 @@ one per actual value of the placeholder.
 
     Set by :class:`~scrapy.extensions.corestats.CoreStats`.
 
+.. stat:: finish_reason_error
+
+``finish_reason_error``
+    Boolean indicating whether :stat:`finish_reason` denotes a failed crawl.
+    It matches the *error* argument of the :signal:`spider_closed` signal, and
+    :ref:`commands <topics-commands>` such as :command:`crawl` use it to
+    decide their process exit code.
+
+    .. versionadded:: VERSION
+
+    Set by :class:`~scrapy.extensions.corestats.CoreStats`.
+
 .. stat:: finish_time
 
 ``finish_time``
diff --git a/scrapy/commands/__init__.py b/scrapy/commands/__init__.py
index 632e2a27a48..9dc2d3f7d86 100644
--- a/scrapy/commands/__init__.py
+++ b/scrapy/commands/__init__.py
@@ -244,8 +244,8 @@ def _run_crawler(
         self.crawler_process.crawl(crawler, **opts.spargs)
         self.crawler_process.start()
         if self.crawler_process.bootstrap_failed or crawler.stats.get_value(
-            "finish_reason"
-        ) in {"closespider_errorcount", "start_error"}:
+            "finish_reason_error", False
+        ):
             self.exitcode = 1
 
     def _warn_if_feeds_unused(self, sender: Crawler, **kwargs: Any) -> None:
diff --git a/scrapy/core/engine.py b/scrapy/core/engine.py
index 162f03c0cdb..b86fe233db9 100644
--- a/scrapy/core/engine.py
+++ b/scrapy/core/engine.py
@@ -350,7 +350,9 @@ def close(self) -> Deferred[None]:  # pragma: no cover
         )
         return deferred_from_coro(self.close_async())
 
-    async def close_async(self, *, reason: str = "shutdown") -> None:
+    async def close_async(
+        self, *, reason: str = "shutdown", error: bool = False
+    ) -> None:
         """
         Gracefully close the execution engine.
         If it has already been started, stop it. In all cases, close the spider and the downloader.
@@ -359,7 +361,8 @@ async def close_async(self, *, reason: str = "shutdown") -> None:
             await self.stop_async()  # will also close spider and downloader
             return
         if self.spider is not None:
-            await self.close_spider_async(reason=reason)  # will also close downloader
+            # will also close downloader
+            await self.close_spider_async(reason=reason, error=error)
         else:
             self.downloader.close()
         if self._state not in (_EngineState.STOPPING, _EngineState.STOPPED):
@@ -385,7 +388,9 @@ async def _process_start_next(self) -> None:
         except CloseSpider as exception:
             self._start = None
             _schedule_coro(
-                self.close_spider_async(reason=exception.reason or "cancelled")
+                self.close_spider_async(
+                    reason=exception.reason or "cancelled", error=exception.error
+                )
             )
         except Exception as exception:
             self._start = None
@@ -719,9 +724,12 @@ def _spider_idle(self) -> None:
             return
         if self.spider_is_idle():
             default_reason = "start_error" if self._start_error else "finished"
-            ex = detected_ex.get(CloseSpider, CloseSpider(reason=default_reason))
+            ex = detected_ex.get(
+                CloseSpider,
+                CloseSpider(reason=default_reason, error=self._start_error),
+            )
             assert isinstance(ex, CloseSpider)  # typing
-            _schedule_coro(self.close_spider_async(reason=ex.reason))
+            _schedule_coro(self.close_spider_async(reason=ex.reason, error=ex.error))
 
     def close_spider(
         self,
@@ -769,6 +777,7 @@ async def close_spider_async(  # noqa: PLR0912, PLR0915
         *,
         reason: str = "cancelled",
         mode: _StopMode = "graceful",
+        error: bool = False,
     ) -> None:
         """Close (cancel) spider and clear all its outstanding requests.
 
@@ -825,6 +834,7 @@ async def close_spider_async(  # noqa: PLR0912, PLR0915
                 signal=signals.spider_closed,
                 spider=spider,
                 reason=reason,
+                error=error,
             )
         except Exception:
             logger.exception(
diff --git a/scrapy/core/scraper.py b/scrapy/core/scraper.py
index 6c68fc65a4b..08eff6ead10 100644
--- a/scrapy/core/scraper.py
+++ b/scrapy/core/scraper.py
@@ -366,7 +366,9 @@ def handle_spider_error(
         exc = _failure.value
         if isinstance(exc, CloseSpider):
             _schedule_coro(
-                self.crawler.engine.close_spider_async(reason=exc.reason or "cancelled")
+                self.crawler.engine.close_spider_async(
+                    reason=exc.reason or "cancelled", error=exc.error
+                )
             )
             return
         logkws = self.logformatter.spider_error(
diff --git a/scrapy/crawler.py b/scrapy/crawler.py
index 0ff45b3e72b..723f70fc181 100644
--- a/scrapy/crawler.py
+++ b/scrapy/crawler.py
@@ -302,7 +302,9 @@ def crawl(self, *args: Any, **kwargs: Any) -> Generator[Deferred[Any], Any, None
             try:
                 yield deferred_from_coro(self.engine.open_spider_async())
             except CloseSpider as exc:
-                yield deferred_from_coro(self.engine.close_async(reason=exc.reason))
+                yield deferred_from_coro(
+                    self.engine.close_async(reason=exc.reason, error=exc.error)
+                )
             else:
                 yield deferred_from_coro(self.engine.start_async())
         except Exception:
@@ -336,7 +338,7 @@ async def crawl_async(self, *args: Any, **kwargs: Any) -> None:
             try:
                 await self.engine.open_spider_async()
             except CloseSpider as exc:
-                await self.engine.close_async(reason=exc.reason)
+                await self.engine.close_async(reason=exc.reason, error=exc.error)
             else:
                 await self.engine.start_async()
         except Exception:
diff --git a/scrapy/exceptions.py b/scrapy/exceptions.py
index db8b5d19652..aa6203f7a84 100644
--- a/scrapy/exceptions.py
+++ b/scrapy/exceptions.py
@@ -66,7 +66,12 @@ class CloseSpider(Exception):
     .. versionchanged:: VERSION
        Added support for raising it from a downloader middleware.
 
-    *reason* is a string with the reason for closing.
+    .. versionadded:: VERSION
+       The *error* parameter.
+
+    *reason* is a string with the reason for closing. *error*, keyword-only,
+    marks the crawl as failed, which commands such as :command:`crawl` report
+    through their process exit code.
 
     For example:
 
@@ -77,9 +82,10 @@ def parse_page(self, response):
                 raise CloseSpider("bandwidth_exceeded")
     """
 
-    def __init__(self, reason: str = "cancelled"):
+    def __init__(self, reason: str = "cancelled", *, error: bool = False):
         super().__init__()
         self.reason = reason
+        self.error = error
 
 
 class StopDownload(Exception):
diff --git a/scrapy/extensions/closespider.py b/scrapy/extensions/closespider.py
index 1c0f0a4d2d8..3ae2858ac12 100644
--- a/scrapy/extensions/closespider.py
+++ b/scrapy/extensions/closespider.py
@@ -87,7 +87,7 @@ def from_crawler(cls, crawler: Crawler) -> Self:
     def error_count(self, failure: Failure, response: Response, spider: Spider) -> None:
         self.counter["errorcount"] += 1
         if self.counter["errorcount"] == self.close_on["errorcount"]:
-            self._close_spider("closespider_errorcount")
+            self._close_spider("closespider_errorcount", error=True)
 
     def page_count(self, response: Response, request: Request, spider: Spider) -> None:
         self.counter["pagecount"] += 1
@@ -144,5 +144,7 @@ def _count_items_produced(self) -> None:
             )
             self._close_spider("closespider_timeout_no_item")
 
-    def _close_spider(self, reason: str) -> None:
-        _schedule_coro(self.crawler.engine.close_spider_async(reason=reason))
+    def _close_spider(self, reason: str, *, error: bool = False) -> None:
+        _schedule_coro(
+            self.crawler.engine.close_spider_async(reason=reason, error=error)
+        )
diff --git a/scrapy/extensions/corestats.py b/scrapy/extensions/corestats.py
index b464942afd2..3c92b713a13 100644
--- a/scrapy/extensions/corestats.py
+++ b/scrapy/extensions/corestats.py
@@ -39,7 +39,7 @@ def spider_opened(self, spider: Spider) -> None:
         self._start_time_mono = monotonic()
         self.stats.set_value("start_time", self.start_time)
 
-    def spider_closed(self, spider: Spider, reason: str) -> None:
+    def spider_closed(self, spider: Spider, reason: str, error: bool = False) -> None:
         assert self.start_time is not None
         assert self._start_time_mono is not None
         finish_time, finish_time_mono = datetime.now(tz=timezone.utc), monotonic()
@@ -47,6 +47,7 @@ def spider_closed(self, spider: Spider, reason: str) -> None:
         self.stats.set_value("elapsed_time_seconds", elapsed_time_seconds)
         self.stats.set_value("finish_time", finish_time)
         self.stats.set_value("finish_reason", reason)
+        self.stats.set_value("finish_reason_error", error)
 
     def item_scraped(self, item: Any, spider: Spider) -> None:
         self.stats.inc_value("item_scraped_count")
```

## 3. Test patch

```diff
diff --git a/tests/test_closespider.py b/tests/test_closespider.py
index 99c552b8005..d5c029ff464 100644
--- a/tests/test_closespider.py
+++ b/tests/test_closespider.py
@@ -87,6 +87,7 @@ def test_closespider_errorcount(mockserver: MockServer):
     errorcount = crawler.stats.get_value(key)
     assert crawler.stats.get_value("spider_exceptions/count") >= close_on
     assert errorcount >= close_on
+    assert crawler.stats.get_value("finish_reason_error") is True
 
 
 @inline_callbacks_test
diff --git a/tests/test_command_crawl.py b/tests/test_command_crawl.py
index 6719127c20e..050371bd02f 100644
--- a/tests/test_command_crawl.py
+++ b/tests/test_command_crawl.py
@@ -134,6 +134,38 @@ async def start(self):
         assert "Spider closed (closespider_errorcount)" in err
         assert returncode != 0
 
+    def test_close_spider_error_exit_code(self, proj_path: Path) -> None:
+        spider_code = """
+import scrapy
+from scrapy.exceptions import CloseSpider
+
+class MySpider(scrapy.Spider):
+    name = 'myspider'
+
+    async def start(self):
+        raise CloseSpider('payment_required', error=True)
+        yield
+"""
+        returncode, _, err = self.crawl(spider_code, proj_path)
+        assert "Spider closed (payment_required)" in err
+        assert returncode != 0
+
+    def test_close_spider_custom_reason_exit_code(self, proj_path: Path) -> None:
+        spider_code = """
+import scrapy
+from scrapy.exceptions import CloseSpider
+
+class MySpider(scrapy.Spider):
+    name = 'myspider'
+
+    async def start(self):
+        raise CloseSpider('custom_reason')
+        yield
+"""
+        returncode, _, err = self.crawl(spider_code, proj_path)
+        assert "Spider closed (custom_reason)" in err
+        assert returncode == 0
+
     def test_start_error_exit_code(self, proj_path: Path) -> None:
         spider_code = """
 import scrapy
diff --git a/tests/test_engine.py b/tests/test_engine.py
index bd4646ce9c3..fc37b3a3b40 100644
--- a/tests/test_engine.py
+++ b/tests/test_engine.py
@@ -76,6 +76,11 @@ def spider_idle(self):
         raise CloseSpider(reason="custom_reason")
 
 
+class ErrorCloseReasonSpider(ChangeCloseReasonSpider):
+    def spider_idle(self):
+        raise CloseSpider(reason="custom_reason", error=True)
+
+
 class TestEngine(TestEngineBase):
     @coroutine_test
     async def test_crawler(self, mockserver: MockServer) -> None:
@@ -117,7 +122,21 @@ async def test_crawler_change_close_reason_on_idle(
         assert {
             "spider": run.crawler.spider,
             "reason": "custom_reason",
+            "error": False,
+        } == run.signals_caught[signals.spider_closed]
+
+    @coroutine_test
+    async def test_crawler_change_close_reason_and_error_on_idle(
+        self, mockserver: MockServer
+    ) -> None:
+        run = CrawlerRun(ErrorCloseReasonSpider)
+        await run.run(mockserver)
+        assert {
+            "spider": run.crawler.spider,
+            "reason": "custom_reason",
+            "error": True,
         } == run.signals_caught[signals.spider_closed]
+        assert run.crawler.stats.get_value("finish_reason_error") is True
 
     @coroutine_test
     async def test_close_downloader(self):
diff --git a/tests/test_stats.py b/tests/test_stats.py
index 4d7d11a06dd..53b2d09cded 100644
--- a/tests/test_stats.py
+++ b/tests/test_stats.py
@@ -56,6 +56,7 @@ def test_core_stats_default_stats_collector(
             "item_dropped_count": 1,
             "item_dropped_reasons_count/ZeroDivisionError": 1,
             "finish_reason": "finished",
+            "finish_reason_error": False,
             "elapsed_time_seconds": 0.0,
         }
 
diff --git a/tests/utils/bases/engine.py b/tests/utils/bases/engine.py
index a41a83a7b6a..cd34d828dc5 100644
--- a/tests/utils/bases/engine.py
+++ b/tests/utils/bases/engine.py
@@ -158,4 +158,5 @@ def _assert_signals_caught(run: CrawlerRun) -> None:
         assert {
             "spider": run.crawler.spider,
             "reason": "finished",
+            "error": False,
         } == run.signals_caught[signals.spider_closed]
```

## 4. FAIL_TO_PASS tests

- `tests/test_closespider.py::test_closespider_errorcount`
- `tests/test_command_crawl.py::TestCrawlCommand::test_close_spider_error_exit_code`
- `tests/test_engine.py::TestEngine::test_crawler`
- `tests/test_engine.py::TestEngine::test_crawler_change_close_reason_and_error_on_idle`
- `tests/test_engine.py::TestEngine::test_crawler_change_close_reason_on_idle`
- `tests/test_stats.py::TestCoreStatsExtension::test_core_stats_default_stats_collector`
