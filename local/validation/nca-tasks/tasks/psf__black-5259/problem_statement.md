List concatenation, multiple lines
Probably not a bug, but I was wondering if the code below shouldn't be formatted more like call chains are.
I did not expect black to change anything other than quotes in this example.
Aligned brackets feel much more readable.

```
# before
-    search_fields = (
-        ['file__%s' % field for field in FileAdmin.search_fields] +
-        ['resource__%s' % field for field in ResourceAdmin.search_fields]
-    )
# black output
+    search_fields = ["file__%s" % field for field in FileAdmin.search_fields] + [
+        "resource__%s" % field for field in ResourceAdmin.search_fields
+    ]
```

Operating system: OSX 10.11.6
Python version: 3.6.5
Black version: 18.5b0
Does also happen on master: yes
