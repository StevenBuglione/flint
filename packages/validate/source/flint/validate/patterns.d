/// Run-time regular expressions for Spring-layer validators whose patterns arrive as data
/// (Jakarta `@Pattern` read from Flint AOT descriptors).
module flint.validate.patterns;

@safe:

package(flint) import flint.validate.internal.pattern : RuntimePattern, compileRuntimePattern;

/// Whether `cp` is a letter (`Character.isLetter` on JDK 21), for engines that implement `\p{L}` themselves.
package(flint) import flint.validate.internal.letters : isUnicodeLetter;

@("a run-time pattern matches as the compile-time one does")
unittest
{
    import flint.validate.internal.pattern : matchPattern;

    const phone = compileRuntimePattern(`\d{1,10}`);
    assert(phone.error is null);
    foreach (input; ["0", "6085551023", "", "12345678901", "60855a"])
        assert(phone.matches(cast(const(ubyte)[]) input) == matchPattern!`\d{1,10}`(cast(const(ubyte)[]) input));
    const name = compileRuntimePattern("[A-Z][a-z]+( [A-Z][a-z]+)?");
    assert(name.matches(cast(const(ubyte)[]) "George Franklin") && !name.matches(cast(const(ubyte)[]) "george"));
    assert(compileRuntimePattern("(unclosed").error !is null);
    assert(!compileRuntimePattern("(unclosed").matches(cast(const(ubyte)[]) "x"));
}
