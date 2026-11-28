// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Java SE 21 `java.lang.IllegalMonitorStateException`, implemented from the public contract.
module flint.java.lang.illegalmonitorstateexception;

import flint.engine.aot.name : CanonicalName, typeNameOf;
import flint.java.lang.runtimeexception : CanonicalRuntimeName, JavaExceptionConstructors, RuntimeException;

@safe:

/// Thrown when a thread waits on or notifies a monitor it does not own.
@CanonicalName("flint.java.lang.IllegalMonitorStateException")
class IllegalMonitorStateException : RuntimeException
{
    mixin JavaExceptionConstructors;
    mixin CanonicalRuntimeName;
}
