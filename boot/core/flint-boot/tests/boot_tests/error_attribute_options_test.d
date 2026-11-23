/// Flint tests for `ErrorAttributeOptions` (upstream has no dedicated test class; its behaviour is exercised by
/// `DefaultErrorAttributesTests`, which needs the servlet layer and is ported with the webmvc module).
module boot_tests.error_attribute_options_test;

import flint.boot.web.error : ErrorAttributeOptions;
import flint.java.util : LinkedHashMap;

@safe:

private alias Include = ErrorAttributeOptions.Include;

@("flint.errorAttributeOptions.defaults") unittest
{
    const options = ErrorAttributeOptions.defaults();
    assert(options.getIncludes() == [Include.STATUS, Include.ERROR, Include.PATH]);
    assert(!options.isIncluded(Include.MESSAGE));
}

@("flint.errorAttributeOptions.includingAndExcluding") unittest
{
    const options = ErrorAttributeOptions.defaults().including(Include.MESSAGE,
            Include.STACK_TRACE).excluding(Include.PATH);
    assert(options.getIncludes() == [
        Include.STACK_TRACE, Include.MESSAGE, Include.STATUS, Include.ERROR
    ]);
    assert(ErrorAttributeOptions.key(Include.STACK_TRACE) == "trace");
    assert(ErrorAttributeOptions.key(Include.BINDING_ERRORS) == "errors");
}

@("flint.errorAttributeOptions.retainIncluded") unittest
{
    auto map = new LinkedHashMap!(string, Object);
    foreach (key; ["timestamp", "status", "error", "message", "trace", "path"])
        map.put(key, null);
    ErrorAttributeOptions.defaults().retainIncluded(map);
    assert(map.containsKey("timestamp") && map.containsKey("status") && map.containsKey("error"));
    assert(map.containsKey("path") && !map.containsKey("message") && !map.containsKey("trace"));
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
