// Ported from eclipse-aspectj/aspectj 1.9.27: org/aspectj/lang/annotation/control/CodeGenerationHint.java
/*******************************************************************************
 * Copyright (c) 2013 Contributors.
 * All rights reserved.
 * This program and the accompanying materials are made available
 * under the terms of the Eclipse Public License v 2.0
 * which accompanies this distribution and is available at
 * https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.txt
 *
 * Contributors:
 * initial implementation              Andy Clement
 *******************************************************************************/

// Modified by the Flint authors. SPDX-License-Identifier: EPL-2.0
module flint.aspectj.lang.annotation.control;

@safe:

/// Supplies a compiler hint for a generated pointcut member.
struct CodeGenerationHint
{
    /// Optional suffix for the member generated for an if pointcut.
    string ifNameSuffix = "";
}
