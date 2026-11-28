// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.native_thread_identity_test;

import flint.java.nativethreadidentity : nativeThreadIdentity;

@safe:

@("Native thread identity calls the factory once per thread") unittest
{
    assert(nativeThreadIdentity(false, null) is null);
    assert(nativeThreadIdentity(true, null) is null);
    auto candidate = new Object;
    assert(nativeThreadIdentity(true, candidate) is candidate);
    assert(nativeThreadIdentity(false, null) is candidate);
    assert(nativeThreadIdentity(true, new Object) is candidate);
}
