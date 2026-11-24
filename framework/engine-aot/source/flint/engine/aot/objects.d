/++
Java's `Object` methods over `Object` references, for the API layer: `objectEquals`, `objectToHash` and
`objectToString` (see `flint.engine.aot.sys.objects` for why they exist), and `statelessInstance`, the one shared
instance of a class with no fields (Java's shared constants; see `flint.engine.aot.sys.constant`), and the views
Java-style erased collections of a class use (`flint.engine.aot.sys.erasure`).
+/
module flint.engine.aot.objects;

public import flint.engine.aot.sys.objects : objectEquals, objectToHash, objectToString;
public import flint.engine.aot.sys.constant : isStateless, statelessInstance;
public import flint.engine.aot.sys.erasure : asObjects, assumeClass, assumeClasses;

@safe:
