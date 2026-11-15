#!/bin/bash
set -uxo pipefail
cd /testbed
git config --global --add safe.directory /testbed
git status
git -c core.fileMode=false diff b6ac7852a2aaea3d8512aba6062dbc271ea90dcb
git checkout b6ac7852a2aaea3d8512aba6062dbc271ea90dcb -- tests/test_pipeline_media.py
git apply -v - <<'EOF_NCA_TEST_PATCH_7f3a'
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
EOF_NCA_TEST_PATCH_7f3a
: '>>>>> Start Test Output'
pytest -rA --color=no -p no:cacheprovider tests/test_pipeline_media.py
: '>>>>> End Test Output'
git checkout b6ac7852a2aaea3d8512aba6062dbc271ea90dcb -- tests/test_pipeline_media.py
