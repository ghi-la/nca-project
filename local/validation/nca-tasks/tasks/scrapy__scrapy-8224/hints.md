i will try to resolve this 
Could you see if it reproduced before 2.13, e.g. in 2.12? I wonder if it might have to do with the use of separate queues to store start requests and follow-up requests.
The way I see it, the first request (`/sbn`) goes through and gets added to the dupefilter without problem.
Then the second request comes in `/sbn/`, it gets forwarded to `/bn`, which then gets retried.
The `RetryMiddleware` adds `dont_filter=True` to the request and when that gets forwarded to `/sbn` this is kept, I think that's the problem.
The `RedirectMiddleware` should not just copy the `dont_filter` attribute of an intermediate request but of the original request that it belongs to, does that make sense?

I tried with the following version and I get the same result, i.e. `/sbn` is downloaded twice.
```
Scrapy       : 2.12.0
lxml         : 5.4.0.0
libxml2      : 2.13.8
cssselect    : 1.3.0
parsel       : 1.10.0
w3lib        : 2.3.1
Twisted      : 25.5.0
Python       : 3.12.3 (main, May 26 2025, 18:50:19) [GCC 13.3.0]
pyOpenSSL    : 25.1.0 (OpenSSL 3.5.0 8 Apr 2025)
cryptography : 45.0.4
Platform     : Linux-6.11.0-26-generic-x86_64-with-glibc2.39
```
Great analysis.

However, I am not sure what the proper fix is.

Yes, that `dont_filter` should stop applying when the URL changes, but only in the scenario where such `dont_filter` was added by the retry middleware.

I wonder if it could be a matter of changing the retry middleware to:
- Keep a set or mapping of requests¹ being retried to which dont_filter was added (i.e. it was not there already).
- In parse_response, set dont_filter to False for such requests if a retry is not needed anymore.

¹ One where the key is automatically removed when the request is; we have such a (dict) structure already somewhere in the code base.
@ben-freist i have tested this theory yesterday , and did prove it was false , turns out the issue was allotment of different fingerprints to the same url , refer #6906 to know more.
@pragnyanramtha I think it may be you who is in the wrong here. While it is possible that 2 different URLs get the same fingerprint, it is highly unlikely that the same URL gets 2 different fingerprints.
@Gallaecio , thats not what I exactly meant but

the issue I have been investigating isn't that a single URL yields different fingerprints. The problem arises when a request's dont_filter=True flag, which is specifically added by the RetryMiddleware for a retry attempt, then propagates through subsequent redirects handled by the RedirectMiddleware.

This propagation causes the final URL in the redirect chain (which, based on our canonicalization rules, does have a consistent and unique fingerprint) to bypass the DupeFilter entirely. So, even if its fingerprint FP_X is already present in the DupeFilter from a previous successful crawl, the request will be re-downloaded because dont_filter=True tells Scrapy to ignore the duplication check.

Your proposed solution of the RetryMiddleware keeping track of the dont_filter flags it adds and resetting them when retries are no longer needed directly addresses this propagation issue, ensuring that the DupeFilter can correctly perform its function on all requests (including those at the end of a retry-redirect chain) that don't legitimately require a dont_filter bypass.

put simply you are right in saying that a single url will never have 2 different fingerprints but the urls 
```https://localhost``` and ```https://localhost/``` will not be considered the same hence , they may have different fingerprints , resulting in crawling the same page twice.
> the issue I have been investigating isn't that a single URL yields different fingerprints. The problem arises when a request's dont_filter=True flag, which is specifically added by the RetryMiddleware for a retry attempt, then propagates through subsequent redirects handled by the RedirectMiddleware.
> 
> This propagation causes the final URL in the redirect chain (which, based on our canonicalization rules, does have a consistent and unique fingerprint) to bypass the DupeFilter entirely. So, even if its fingerprint FP_X is already present in the DupeFilter from a previous successful crawl, the request will be re-downloaded because dont_filter=True tells Scrapy to ignore the duplication check.

To me, this sounds exactly like what @ben-freist describes, to which you replied:

> i have tested this theory yesterday , and did prove it was false , turns out the issue was allotment of different fingerprints to the same url 

So I am a bit confused.

---

> but the urls
> `https://localhost` and `https://localhost/` will not be considered the same hence , they may have different fingerprints , resulting in crawling the same page twice.

I don’t think this is happening.

[The default fingerprinter uses w3lib.url.canonicalize_url](https://github.com/scrapy/scrapy/blob/d70f8a3f14252715fbc9b9541364c5b5d142335f/scrapy/utils/request.py#L92C20-L92C36), and:

```python
>>> from w3lib.url import canonicalize_url
>>> canonicalize_url("https://example.com")
'https://example.com/'
>>> canonicalize_url("https://example.com/")
'https://example.com/'
```
i apologise for causing the confusion about this, i was wrong in theorizing that the canonicalization_url gave different outputs for the same urls , 

My confusion stemmed from a specific test I ran locally yesterday and today: when I manually altered canonicalization to forcefully remove trailing slashes (which was part of my initial, perhaps misguided, local experimentation), it appeared to remove duplicate crawls. This led me to incorrectly assume that the underlying issue was w3lib giving different fingerprints for these types of URLs, and that my manual slash removal was fixing it.

However, upon re-testing thoroughly , it became clear that my test was wrong, my specific custom code did not crawl the initial website that was intended to populate the DupeFilter first. This meant the DupeFilter was effectively empty for the scenario I was trying to test. So, any subsequent request (even if it was a 'duplicate' that would normally be filtered) was treated as a first-time crawl, making the output appear idempotent and masking the true dont_filter=True propagation bug.

> > the issue I have been investigating isn't that a single URL yields different fingerprints. The problem arises when a request's dont_filter=True flag, which is specifically added by the RetryMiddleware for a retry attempt, then propagates through subsequent redirects handled by the RedirectMiddleware.
> > This propagation causes the final URL in the redirect chain (which, based on our canonicalization rules, does have a consistent and unique fingerprint) to bypass the DupeFilter entirely. So, even if its fingerprint FP_X is already present in the DupeFilter from a previous successful crawl, the request will be re-downloaded because dont_filter=True tells Scrapy to ignore the duplication check.
> 
> To me, this sounds exactly like what [@ben-freist](https://github.com/ben-freist) describes, to which you replied:


things got pretty clear after i tested out the dont_filter= true flag , hence at that point i was thinking both of us were right ( i still thought the same urls with and without the trailing / were generating different url)

in essence , I was conflating two separate issues and misinterpreting my local test results. The true bug is the dont_filter=True propagation, and I now have a much clearer understanding of it, thanks to your patience and guidance.

Hey,
I think there might be two ways to fix this, at the moment what I'm doing in my code is something like this:
```
class MyRedirectMiddleware(scrapy.downloadermiddlewares.redirect.RedirectMiddleware):
    def process_response(
        self, request: scrapy.http.Request, response: scrapy.http.Response, spider: scrapy.Spider
    ) -> scrapy.http.Request | scrapy.http.Response:
        res = super().process_response(request, response, spider)
        if isinstance(res, scrapy.http.Request):            
            res.dont_filter = res.meta.get(scrapy_constants.META_DONT_FILTER, res.dont_filter)
        return res

class MyRetryMiddleware(scrapy.downloadermiddlewares.retry.RetryMiddleware):
    def process_response(
        self, request: scrapy.http.Request, response: scrapy.http.Response, spider: scrapy.Spider
    ) -> scrapy.http.Request | scrapy.http.Response:
        res = super().process_response(request, response, spider)
        if isinstance(res, scrapy.http.request.Request):
            if scrapy_constants.META_DONT_FILTER not in res.meta:
                res.meta[scrapy_constants.META_DONT_FILTER] = request.dont_filter
        return res
```
I just replace the default `RedirectMiddleware` and `RetryMiddleware` with my own versions and after that the number of duplicates has gone down significantly.

But I think a better way to handle this would be to do something that's closer to how `IgnoreRequest` works.
You would throw a `RetryRequest` exception in a downloader middleware, and then handle that in `ExecutionEngine._handle_downloader_output`.
At the moment it feels a bit like a hack to modify the `dont_filter` attribute, because the semantics of using that yourself vs. it being attached to a request on the fly are different.
i tried to do something similar and failed , i realised pretty soon how big of a task that would be, and gave up , if this can be sucessfully implemented it would be a major change 

Instead of a major change, I are implementing a targeted, cooperative signaling fix between the two middlewares:
Marking the Request: When ```RetryMiddleware``` creates a retry attempt, it adds a special, private flag (```_retry_dont_filter```) to that request's metadata. This acts as a signal that the ```dont_filter=True``` on this request is temporary and was set by the retry logic.

Checking the Signal: When ```RedirectMiddleware``` later processes a redirect for this exact request, it checks for the presence of that special flag.

Breaking the Chain: If the flag is found, ```RedirectMiddleware``` knows the ```dont_filter=True``` was temporary and deliberately creates the new, redirected request with ```dont_filter=False```, preventing the flag from being incorrectly passed on.

In short, ```RetryMiddleware``` leaves a "fragment" that only ```RedirectMiddleware``` looks for, allowing it to intelligently break the chain of duplication. This surgically fixes the bug within the existing architecture.

Let me know your thoughts on it.
The problem I see is that then we need to modify all middlewares like the retry one, and user need to modify custom middlewares.

I think we need to go for a clean solution here. Users can go for quick patches in their own code like the OP did, but for a Scrapy solution we need something reliable.

Maybe it is best to pause work on this one for a while.
Workaround for Issue #6895
This solution involves subclassing the default RetryMiddleware and RedirectMiddleware to create a "cooperative signal" that prevents the dont_filter flag from being incorrectly propagated after a retry.

Step 1: Create a middlewares.py file

In your Scrapy project's main directory (e.g., myproject/myproject/middlewares.py), add the following code:
Generated python

# myproject/middlewares.py
```python

from scrapy.downloadermiddlewares.redirect import RedirectMiddleware
from scrapy.downloadermiddlewares.retry import RetryMiddleware, get_retry_request

class ProjectRetryMiddleware(RetryMiddleware):
    """
    This middleware intelligently flags requests that it is retrying.
    It only adds the flag if it is the one setting dont_filter=True.
    """
    def _retry(self, request, reason, spider):
        # Check the state of dont_filter on the *original* failing request.
        dont_filter_was_set = request.dont_filter

        new_request = get_retry_request(
            request,
            reason=reason,
            spider=spider,
            max_retry_times=self.max_retry_times,
            priority_adjust=self.priority_adjust,
        )

        # Only add the meta flag if we are the ones changing the dont_filter state.
        if new_request and not dont_filter_was_set:
            new_request.meta['_retry_dont_filter'] = True

        return new_request

class ProjectRedirectMiddleware(RedirectMiddleware):
    """
    This middleware respects the flag set by ProjectRetryMiddleware.
    It prevents the propagation of a temporary dont_filter flag to a redirected request.
    """
    def _redirect(self, redirected, request, spider, reason):
        # Check if the dont_filter flag was temporarily set by our retry middleware.
        is_temporary_retry = request.meta.get('_retry_dont_filter', False)
        
        # If it was a temporary retry, do not propagate dont_filter.
        # Otherwise, respect the original request's dont_filter value.
        redirected.dont_filter = request.dont_filter and not is_temporary_retry
        
        # Call the rest of the original _redirect method, but without the dont_filter logic.
        # We can't call super()._redirect() as it would re-apply the flawed logic.
        ttl = request.meta.setdefault("redirect_ttl", self.max_redirect_times)
        redirects = request.meta.get("redirect_times", 0) + 1

        if ttl and redirects <= self.max_redirect_times:
            redirected.meta["redirect_times"] = redirects
            redirected.meta["redirect_ttl"] = ttl - 1
            redirected.meta["redirect_urls"] = [
                *request.meta.get("redirect_urls", []),
                request.url,
            ]
            redirected.meta["redirect_reasons"] = [
                *request.meta.get("redirect_reasons", []),
                reason,
            ]
            redirected.priority = request.priority + self.priority_adjust
            self.logger.debug(
                "Redirecting (%(reason)s) to %(redirected)s from %(request)s",
                {"reason": reason, "redirected": redirected, "request": request},
                extra={"spider": spider},
            )
            return redirected
        
        self.logger.debug(
            "Discarding %(request)s: max redirections reached",
            {"request": request},
            extra={"spider": spider},
        )
        raise IgnoreRequest("max redirections reached")
```
Use code with caution.
Python
Step 2: Update your settings.py
Enable your new middlewares and adjust their order to replace the default ones.
Generated python
# myproject/settings.py
```
DOWNLOADER_MIDDLEWARES = {
   # Disable the default middlewares
   'scrapy.downloadermiddlewares.retry.RetryMiddleware': None,
   'scrapy.downloadermiddlewares.redirect.RedirectMiddleware': None,

   # Enable our custom middlewares, keeping the original order
   'myproject.middlewares.ProjectRetryMiddleware': 550,
   'myproject.middlewares.ProjectRedirectMiddleware': 600,
}
```
Use code with caution.
This will resolve the duplicate request issue without waiting for a core library change. I hope this helps others who run into this problem.