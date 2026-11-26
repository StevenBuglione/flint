// Ported from eclipse-aspectj/aspectj 1.9.27: org/aspectj/lang/annotation/Aspect.java
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

// Ported from eclipse-aspectj/aspectj 1.9.27: org/aspectj/lang/annotation/AdviceName.java
/*******************************************************************************
 * Copyright (c) 2005 Contributors.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v 2.0
 * which accompanies this distribution, and is available at
 * https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.txt
 *
 * Contributors:
 *   Adrian Colyer									initial implementation
 *******************************************************************************/

// Ported from eclipse-aspectj/aspectj 1.9.27: org/aspectj/lang/annotation/Before.java
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

// Ported from eclipse-aspectj/aspectj 1.9.27: org/aspectj/lang/annotation/Around.java
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

// Ported from eclipse-aspectj/aspectj 1.9.27: org/aspectj/lang/annotation/After.java
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

// Ported from eclipse-aspectj/aspectj 1.9.27: org/aspectj/lang/annotation/AfterReturning.java
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

// Ported from eclipse-aspectj/aspectj 1.9.27: org/aspectj/lang/annotation/AfterThrowing.java
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

// Ported from eclipse-aspectj/aspectj 1.9.27: org/aspectj/lang/annotation/Pointcut.java
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

// Ported from eclipse-aspectj/aspectj 1.9.27: org/aspectj/lang/annotation/DeclareParents.java
/*******************************************************************************
 * Copyright (c) 2005 Contributors.
 * All rights reserved.
 * This program and the accompanying materials are made available
 * under the terms of the Eclipse Public License v 2.0
 * which accompanies this distribution and is available at
 * https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.txt
 *
 * Contributors:
 * initial implementation              Adrian Colyer
 *******************************************************************************/

// Ported from eclipse-aspectj/aspectj 1.9.27: org/aspectj/lang/annotation/DeclarePrecedence.java
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

// SPDX-License-Identifier: EPL-2.0
// Modified by the Flint authors.
module flint.aspectj.lang.annotation;

import flint.java.classref : ClassRef, classOf;

@safe:

/// Identifies an aspect and its instantiation expression.
struct Aspect
{
    /// An empty expression selects one shared aspect instance.
    string value = "";
}

/// Gives an advice method its declared AspectJ name.
struct AdviceName
{
    /// The advice name.
    string value;
}

/// Advice that runs before a matching joinpoint.
struct Before
{
    /// The pointcut expression.
    string value;
    /// Explicit advice argument bindings, in parameter order.
    string argNames = "";
}

/// Advice that controls whether and how a matching joinpoint proceeds.
struct Around
{
    /// The pointcut expression.
    string value;
    /// Explicit advice argument bindings, in parameter order.
    string argNames = "";
}

/// Advice that runs on both normal and exceptional completion.
struct After
{
    /// The pointcut expression.
    string value;
    /// Explicit advice argument bindings, in parameter order.
    string argNames = "";
}

/// Advice that runs after a matching joinpoint returns successfully.
struct AfterReturning
{
    /// The pointcut expression.
    string value = "";
    /// An explicit pointcut expression that takes precedence over value.
    string pointcut = "";
    /// The argument bound to the returned value.
    string returning = "";
    /// Explicit advice argument bindings, in parameter order.
    string argNames = "";
}

/// Advice that runs when a matching joinpoint throws.
struct AfterThrowing
{
    /// The pointcut expression.
    string value = "";
    /// An explicit pointcut expression that takes precedence over value.
    string pointcut = "";
    /// The argument bound to the exception.
    string throwing = "";
    /// Explicit advice argument bindings, in parameter order.
    string argNames = "";
}

/// Declares a named pointcut on a method.
struct Pointcut
{
    /// The pointcut expression.
    string value = "";
    /// Explicit pointcut argument names, in parameter order.
    string argNames = "";
}

/// Declares an introduced interface for types matching a pattern.
struct DeclareParents
{
    /// The target type pattern.
    string value;
    /// The implementation type, or the annotation type when unspecified.
    ClassRef defaultImpl = classOf!DeclareParents;
}

/// Declares precedence among matching aspects.
struct DeclarePrecedence
{
    /// A comma-separated sequence of aspect type patterns.
    string value;
}
