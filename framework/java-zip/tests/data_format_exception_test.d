// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module data_format_exception_test;

import flint.java.util.zip : DataFormatException;

@safe:

@("data format exceptions treat any empty detail as absent")
unittest
{
    string detail = "invalid compressed data";
    auto empty = detail[0 .. 0];
    assert(empty !is null);
    assert((new DataFormatException(empty)).msg is null);
    assert((new DataFormatException(null)).msg is null);
    assert((new DataFormatException()).msg is null);
    assert((new DataFormatException(detail)).msg == detail);
}
