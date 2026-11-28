// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module ziperror_test;

import flint.java.lang.virtualmachineerror : InternalError, VirtualMachineError;
import flint.java.util.zip.ziperror : ZipError;

@safe:

@("ZipError is a catchable InternalError with Java's detail")
unittest
{
    static assert(is(ZipError : InternalError));
    static assert(is(ZipError : VirtualMachineError));

    const nullMessage = new ZipError(null);
    assert(nullMessage.getMessage() is null);

    auto invalid = new ZipError("invalid zip");
    assert(invalid.getMessage() == "invalid zip");

    bool caught;
    try
        throw invalid;
    catch (VirtualMachineError failure)
        caught = cast(ZipError) failure is invalid && failure.getMessage() == "invalid zip";
    assert(caught);
}

@("ZipError reports an explicitly empty detail as absent")
unittest
{
    string detail = "invalid zip";
    auto empty = detail[0 .. 0];
    assert(empty !is null);
    assert((new ZipError(empty)).getMessage() is null);
}
