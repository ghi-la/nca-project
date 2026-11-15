I like this idea. 

We can't do it from Spider because spider doesn't necessarily terminate the process - it is CrawlerProcess who does that.So we may need to expose CrawlerProcess to the spider. See also: https://github.com/scrapy/scrapy/issues/1226

Well what I mean was terminate the process and be able to add an exit code with the outcome. We already have an [exception](https://github.com/scrapy/scrapy/blob/master/scrapy/exceptions.py#L23) to terminate the process from the spider.

This exception stops the spider, not necessarily terminates the process. You can have multiple spiders in the same process running at the same time.

In our case, an exception is being thrown by an external API call in the `start_requests` method. The spider is being invoked using a `subprocess.check_call` that uses the `scrapy crawl spname` command. The exception is not bubbling up to the crawler process that invokes it, resulting in a 0 exit code. Do you guys have any thoughts about how this issue? Can you point me to where I can look?

I am interested in submitted a pull request and am looking for your guidance in implementing it. 
