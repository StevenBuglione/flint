// Ported from eclipse-aspectj/aspectj 1.9.27: org/aspectj/lang/JoinPoint.java
// Ported from eclipse-aspectj/aspectj 1.9.27: org/aspectj/lang/Signature.java
// Ported from eclipse-aspectj/aspectj 1.9.27: org/aspectj/lang/NoAspectBoundException.java
/* *******************************************************************
 * Copyright (c) 1999-2001 Xerox Corporation,
 *               2002 Palo Alto Research Center, Incorporated (PARC).
 * All rights reserved.
 * This program and the accompanying materials are made available
 * under the terms of the Eclipse Public License v 2.0
 * which accompanies this distribution and is available at
 * https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.txt
 *
 * Contributors:
 *     Xerox/PARC     initial implementation
 * ******************************************************************/

// Ported from eclipse-aspectj/aspectj 1.9.27: org/aspectj/lang/ProceedingJoinPoint.java
/*******************************************************************************
 * Copyright (c) 2005 Contributors.
 * All rights reserved.
 * This program and the accompanying materials are made available
 * under the terms of the Eclipse Public License v 2.0
 * which accompanies this distribution and is available at
 * https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.txt
 *
 * Contributors:
 * initial implementation              Alexandre Vasseur
 *******************************************************************************/

// Ported from eclipse-aspectj/aspectj 1.9.27: org/aspectj/lang/SoftException.java
/* *******************************************************************
 * Copyright (c) 1999-2001 Xerox Corporation,
 *               2002 Palo Alto Research Center, Incorporated (PARC),
 *               2004 Contributors.
 * All rights reserved.
 * This program and the accompanying materials are made available
 * under the terms of the Eclipse Public License v 2.0
 * which accompanies this distribution and is available at
 * https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.txt
 *
 * Contributors:
 *     Xerox/PARC     initial implementation
 * ******************************************************************/

// Modified by the Flint authors. SPDX-License-Identifier: EPL-2.0
module flint.aspectj.lang;

import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor;
import flint.java.lang : RuntimeException, javaToString;
import std.typecons : Nullable;

@safe:

/// The declaring type, name, and display forms of a join-point signature.
interface Signature
{
    string toString() const;
    /// Returns an abbreviated description.
    string toShortString();
    /// Returns a detailed description.
    string toLongString();
    string getName();
    int getModifiers();
    const(Descriptor) getDeclaringType();
    string getDeclaringTypeName();
}

/// The runtime and static context available to advice.
interface JoinPoint
{
    /// Execution of a method body.
    enum METHOD_EXECUTION = "method-execution";
    /// Call to a method.
    enum METHOD_CALL = "method-call";
    /// Execution of a constructor body.
    enum CONSTRUCTOR_EXECUTION = "constructor-execution";
    /// Call to a constructor.
    enum CONSTRUCTOR_CALL = "constructor-call";
    /// Read of a field.
    enum FIELD_GET = "field-get";
    /// Write of a field.
    enum FIELD_SET = "field-set";
    /// Initialization of a type's static state.
    enum STATICINITIALIZATION = "staticinitialization";
    /// The initial phase before construction.
    enum PREINITIALIZATION = "preinitialization";
    /// Initialization of a newly constructed object.
    enum INITIALIZATION = "initialization";
    /// Execution of an exception handler.
    enum EXCEPTION_HANDLER = "exception-handler";
    /// Acquisition of a synchronization lock.
    enum SYNCHRONIZATION_LOCK = "lock";
    /// Release of a synchronization lock.
    enum SYNCHRONIZATION_UNLOCK = "unlock";
    /// Execution of advice.
    enum ADVICE_EXECUTION = "adviceexecution";

    string toString() const;
    /// Returns an abbreviated description.
    string toShortString();
    /// Returns a detailed description.
    string toLongString();

    /// The currently executing object, or Any.init when absent.
    Any getThis();

    /// The target object, or Any.init when absent.
    Any getTarget();

    /// Arguments supplied at the join point.
    Any[] getArgs();

    Signature getSignature();
    string getKind();
    StaticPart getStaticPart();

    /// Metadata for a join point that is independent of a particular invocation.
    static interface StaticPart
    {
        Signature getSignature();
        string getKind();

        /// Index of the join point within its advised type.
        int getId();

        string toString() const;
        /// Returns an abbreviated description.
        string toShortString();
        /// Returns a detailed description.
        string toLongString();
    }

    /// The static metadata of an enclosing join point.
    static interface EnclosingStaticPart : StaticPart
    {
    }
}

/// The continuation available to around advice.
interface ProceedingJoinPoint : JoinPoint
{
    /// Continues with the current arguments. Propagates a failure from the advice chain or target.
    Any proceed();

    /// Continues with replacement arguments in AspectJ binding order.
    Any proceed(Any[] arguments);
}

/// Thrown when an aspect is unavailable or could not be initialized.
class NoAspectBoundException : RuntimeException
{
    private Throwable inner;

    /// Records an unbound aspect without a name.
    this()
    {
        super();
    }

    /// Records the aspect name and the failure, if initialization threw one.
    this(Nullable!string aspectName, Throwable inner)
    {
        super(detailMessage(aspectName, inner));
        this.inner = inner;
    }

    override inout(Throwable) getCause() inout pure nothrow @nogc
    {
        return inner;
    }

    private static string detailMessage(Nullable!string aspectName, Throwable failure)
    {
        if (failure is null)
            return aspectName.isNull ? null : aspectName.get;

        const name = aspectName.isNull ? "null" : aspectName.get;
        auto runtime = cast(RuntimeException) failure;
        const detail = runtime is null ? javaToString(failure) : runtime.toString();
        return "Exception while initializing " ~ name ~ ": " ~ detail;
    }
}

/// Wraps a failure softened at a join point.
class SoftException : RuntimeException
{
    private Throwable inner;

    /// Wraps the supplied failure and leaves the detail message empty.
    this(Throwable inner)
    {
        super();
        this.inner = inner;
    }

    /// Returns the original failure.
    inout(Throwable) getWrappedThrowable() inout pure nothrow @nogc
    {
        return inner;
    }

    override inout(Throwable) getCause() inout pure nothrow @nogc
    {
        return inner;
    }
}
