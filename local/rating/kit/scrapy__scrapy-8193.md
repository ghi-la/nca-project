# scrapy__scrapy-8193

- repo: `scrapy/scrapy`, created: 2026-09-21, base_commit: `b6ac7852a2aa`
- PR: https://github.com/scrapy/scrapy/pull/8193
- issue: https://github.com/scrapy/scrapy/issues/939
- FAIL_TO_PASS: 8 tests, PASS_TO_PASS: 54 tests, collection_error: **no**

## 1. Issue (what the agent sees)

Media pipeline problem
I think contrib.pipline.media.MediaPipeline should be add config to disable downloaded cache, when I use ImagePipeline to scrapy full site image, alway make memory leak. The media download should be make unique by user not scrapy framwork.

## 2. Gold patch

```diff
diff --git a/docs/topics/media-pipeline.rst b/docs/topics/media-pipeline.rst
index 362480515b8..5e9c99ca6d2 100644
--- a/docs/topics/media-pipeline.rst
+++ b/docs/topics/media-pipeline.rst
@@ -563,6 +563,25 @@ To handle media redirections, set this setting to ``True``:
 
     MEDIA_ALLOW_REDIRECTS = True
 
+Limiting the result cache
+-------------------------
+
+.. setting:: MEDIA_CACHE_SIZE
+
+Media pipelines remember the outcome of every media request they handle, so
+that a file referenced by several items is downloaded once. By default every
+outcome is kept for the whole crawl, which takes about 600 bytes per distinct
+media URL.
+
+.. versionadded:: VERSION
+
+To cap that memory, set :setting:`MEDIA_CACHE_SIZE` to the number of most
+recently used outcomes to keep, or to ``0`` to keep none:
+
+.. code-block:: python
+
+    MEDIA_CACHE_SIZE = 10000
+
 .. _topics-media-pipeline-override:
 
 Extending the Media Pipelines
diff --git a/docs/topics/optimize.rst b/docs/topics/optimize.rst
index 1dbb5949f32..e82d2f258b0 100644
--- a/docs/topics/optimize.rst
+++ b/docs/topics/optimize.rst
@@ -295,6 +295,9 @@ Lowering memory usage
 
     -   Set :setting:`JOBDIR` to offload all scheduled requests to disk.
 
+-   Set :setting:`MEDIA_CACHE_SIZE` if you use :ref:`media pipelines
+    <topics-media-pipeline>`.
+
 -   Be on the lookout for :ref:`memory leaks <topics-leaks>`.
 
 
diff --git a/scrapy/pipelines/media.py b/scrapy/pipelines/media.py
index 41b2e17c95f..58cc21246bc 100644
--- a/scrapy/pipelines/media.py
+++ b/scrapy/pipelines/media.py
@@ -5,7 +5,7 @@
 import logging
 import warnings
 from abc import ABC, abstractmethod
-from collections import defaultdict
+from collections import OrderedDict, defaultdict
 from typing import TYPE_CHECKING, Any, Literal, TypeAlias, TypedDict, cast
 
 from twisted.internet.defer import Deferred, DeferredList
@@ -80,7 +80,7 @@ class SpiderInfo:
         def __init__(self, spider: Spider):
             self.spider: Spider = spider
             self.downloading: set[bytes] = set()
-            self.downloaded: dict[bytes, FileInfo | Failure] = {}
+            self.downloaded: OrderedDict[bytes, FileInfo | Failure] = OrderedDict()
             self.waiting: defaultdict[bytes, list[Deferred[FileInfo]]] = defaultdict(
                 list
             )
@@ -111,6 +111,7 @@ def __init__(
             resolve("MEDIA_ALLOW_REDIRECTS"), False
         )
         self._handle_statuses(self.allow_redirects)
+        self._cache_size: int = settings.getint(resolve("MEDIA_CACHE_SIZE"))
 
     def _handle_statuses(self, allow_redirects: bool) -> None:
         self.handle_httpstatus_list = None
@@ -177,6 +178,7 @@ async def _process_request(
         # Return cached result if request was already seen
         if fp in info.downloaded:
             await _process_pending_io()
+            info.downloaded.move_to_end(fp)
             cached_result = info.downloaded[fp]
             if isinstance(cached_result, Failure):
                 if eb:
@@ -276,6 +278,8 @@ def _cache_result_and_execute_waiters(
 
         info.downloading.remove(fp)
         info.downloaded[fp] = result  # cache result
+        if 0 <= self._cache_size < len(info.downloaded):
+            info.downloaded.popitem(last=False)
         for wad in info.waiting.pop(fp):
             if isinstance(result, Failure):
                 wad.errback(result)
diff --git a/scrapy/settings/default_settings.py b/scrapy/settings/default_settings.py
index 0c0216ed2cd..e619811e65d 100644
--- a/scrapy/settings/default_settings.py
+++ b/scrapy/settings/default_settings.py
@@ -158,6 +158,7 @@
     "MAIL_SSL",
     "MAIL_TLS",
     "MAIL_USER",
+    "MEDIA_CACHE_SIZE",
     "MEMDEBUG_ENABLED",
     "MEMUSAGE_CHECK_INTERVAL_SECONDS",
     "MEMUSAGE_ENABLED",
@@ -488,6 +489,8 @@
 MAIL_SSL = False
 MAIL_TLS = False
 
+MEDIA_CACHE_SIZE = -1
+
 MEMDEBUG_ENABLED = False  # enable memory debugging
 
 MEMUSAGE_ENABLED = True
```

## 3. Test patch

```diff
diff --git a/tests/test_pipeline_media.py b/tests/test_pipeline_media.py
index fd377fb7f3b..09d470cc5a1 100644
--- a/tests/test_pipeline_media.py
+++ b/tests/test_pipeline_media.py
@@ -455,6 +455,32 @@ async def rsp2_func():
         new_item = await self.pipe.process_item(item)
         assert new_item["results"] == [(True, {}), (True, {})]
 
+    @pytest.mark.parametrize(
+        ("size", "prefixed", "cached_urls"),
+        [
+            (2, False, ["http://url1", "http://url3"]),
+            (2, True, ["http://url1", "http://url3"]),
+            (0, False, []),
+            (-1, False, ["http://url2", "http://url1", "http://url3"]),
+        ],
+    )
+    @coroutine_test
+    async def test_cache_size(self, size: int, prefixed: bool, cached_urls: list[str]):
+        key = "MEDIA_CACHE_SIZE"
+        if prefixed:
+            key = f"{self.pipeline_class.__name__.upper()}_{key}"
+        crawler = get_crawler(DefaultSpider, {key: size})
+        crawler.spider = crawler._create_spider()
+        crawler.engine = MagicMock(download_async=mocked_download_func)
+        pipe = build_from_crawler(self.pipeline_class, crawler)
+        pipe.open_spider()
+        for url in ["http://url1", "http://url2", "http://url1", "http://url3"]:
+            req = Request(url, meta={"response": Response(url)})
+            await pipe.process_item({"requests": req})
+        assert list(pipe.spiderinfo.downloaded) == [
+            self.fingerprint(Request(url)) for url in cached_urls
+        ]
+
     @coroutine_test
     async def test_use_media_to_download_result(self):
         req = Request("http://url", meta={"result": "ITSME"})
```

## 4. FAIL_TO_PASS tests

- `tests/test_pipeline_media.py::TestAsyncMediaDownloaded::test_cache_size[-1-False-cached_urls3]`
- `tests/test_pipeline_media.py::TestAsyncMediaDownloaded::test_cache_size[0-False-cached_urls2]`
- `tests/test_pipeline_media.py::TestAsyncMediaDownloaded::test_cache_size[2-False-cached_urls0]`
- `tests/test_pipeline_media.py::TestAsyncMediaDownloaded::test_cache_size[2-True-cached_urls1]`
- `tests/test_pipeline_media.py::TestMediaPipeline::test_cache_size[-1-False-cached_urls3]`
- `tests/test_pipeline_media.py::TestMediaPipeline::test_cache_size[0-False-cached_urls2]`
- `tests/test_pipeline_media.py::TestMediaPipeline::test_cache_size[2-False-cached_urls0]`
- `tests/test_pipeline_media.py::TestMediaPipeline::test_cache_size[2-True-cached_urls1]`
