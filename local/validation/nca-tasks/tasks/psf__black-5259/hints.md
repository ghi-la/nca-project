Agreed with you on this particular case. It's a case of over-optimization that we decided to do due to a popular idiom in assignments and if statements:
- if there is just a single operator; and
- the line up to and including the operator is short enough; and
- the rest ends with a bracket (so we have something to split on); then

omit optional parentheses and split by the discovered bracket instead.

We should extend this rule to discover symmetrical cases like yours.
Maybe this rule should be eliminated instead?

The extra bracket has a purpose: it provides the line continuation, but unfortunately it also costs an extra line. However if it is not there, some other bracket needs to provide line continuation, which is quite awkward looking.

I have just added some more examples in #317 with reasoning why the popular idiom is bad in general. But maybe I miss something, is there any example, where this idiom produces a good result?
