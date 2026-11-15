# Return cached result if request was already seen

if fp in info.downloaded:
    return defer_result(info.downloaded[fp]).addCallbacks(cb, eb)

this code will be cache missing very much, but use much memory.

hello @pczhaoyun , sorry for this very very very late feedback.
If you're still having this problem, can you explain a bit more what you're experiencing and what is not correct in your view with how media is downloaded? Sorry I don't understand it from your description and comment.

Not sure if this is 100% what @pczhaoyun meant, but looks like ``MediaPipeline`` caches results of ``media_downloaded`` method permanently into ``info.downloaded``: https://github.com/scrapy/scrapy/blob/1.4.0/scrapy/pipelines/media.py#L143 and I don't see if this is removed anywhere (definitely not in this module, and search does not turn up any other places where it might be removed).
I observe this caching in practice too, with a slightly extended pipeline (https://github.com/TeamHG-Memex/scrapy-cdr/blob/d2150e5ae09b555da0eb53bf5dcbb248181b7c0d/scrapy_cdr/media_pipeline.py#L15). I think this applies to default pipeline as well, did not check yet.
Indeed, looks like there's unconditional caching. Makes sense to be able to disable it.
I would also disable it by default but that's backwards incompatible...
We could also give the user an option to limit the maximal number of cached items - that's what I would prefer in my use case (although it's easy to override if needed). I'm fine with some constant memory overhead in oder to avoid downloading same media items again, but would not like it to grow.
I had been facing the same issue, so far the simplest solution I found is inside `item_completed`, after getting all things done, reset downloaded to empty. `self.spiderinfo.downloaded = {}`, memory leak issue resolved. 