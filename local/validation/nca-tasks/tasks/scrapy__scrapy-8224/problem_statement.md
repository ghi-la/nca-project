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

