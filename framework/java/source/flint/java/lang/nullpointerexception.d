// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Java SE 21 `java.lang.NullPointerException`, implemented from the public contract.
module flint.java.lang.nullpointerexception;

import flint.engine.aot.name : CanonicalName, typeNameOf;
import flint.java.lang.runtimeexception : CanonicalRuntimeName, JavaExceptionConstructors, RuntimeException;

@safe:

/// Thrown when `null` is used where an object is required.
@CanonicalName("flint.java.lang.NullPointerException")
class NullPointerException : RuntimeException
{
    mixin JavaExceptionConstructors;
    mixin CanonicalRuntimeName;
}
