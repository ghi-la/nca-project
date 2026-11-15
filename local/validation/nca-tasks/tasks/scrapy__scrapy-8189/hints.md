Good idea for `escape_ajax`, looks generic and useful enough. (Should we also have an `unescape_ajax`?)
I'm not sure about `add_http_if_no_scheme()`. Would it be useful outside of scrapy? Also one couldargue why it adds "http://" and not "https://".

I'm using `add_http_if_no_scheme` in pretty much every project where user provides a URL as an input. I think it should add http, not https because this is what browsers add if you enter a URL without a schema to the address bar. Many websites don't work with https, so adding https to a user-provided URL is likely to break it; sites which work with https often provide a redirect from http to https version anyways.

hm, what's the use case for unescape_ajax?

> hm, what's the use case for unescape_ajax?

I was thinking to make ajax-escaped URLs more readable. Is `_escaped_fragment_` still that commonly used anyway?

Also, we have a couple of dual functions in `w3lib.url` already (`add_or_replace_parameter`/`url_query_parameter`, `file_uri_to_path`/`path_to_file_uri`)

I think Google deprecated `_escaped_fragment_`, but as there are sites who support it escape_ajax can still be useful for crawling.

unescape_ajax looks less useful because there are no ajax-escaped links on websites. It may be helpful to parse logs though. But I'd not implement it unless we have a real use case.

Hi! I'd love to give this a shot -- if it's still relevant? :-) 