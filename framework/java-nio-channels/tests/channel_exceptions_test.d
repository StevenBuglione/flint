// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests for the 20 unchecked Java SE 21 java.nio.channels exceptions.
module channel_exceptions_test;

import flint.java.lang : IllegalArgumentException, IllegalStateException, RuntimeException;
import flint.java.nio.channels.acceptpendingexception : AcceptPendingException;
import flint.java.nio.channels.alreadyboundexception : AlreadyBoundException;
import flint.java.nio.channels.alreadyconnectedexception : AlreadyConnectedException;
import flint.java.nio.channels.cancelledkeyexception : CancelledKeyException;
import flint.java.nio.channels.closedselectorexception : ClosedSelectorException;
import flint.java.nio.channels.connectionpendingexception : ConnectionPendingException;
import flint.java.nio.channels.illegalblockingmodeexception : IllegalBlockingModeException;
import flint.java.nio.channels.illegalchannelgroupexception : IllegalChannelGroupException;
import flint.java.nio.channels.illegalselectorexception : IllegalSelectorException;
import flint.java.nio.channels.noconnectionpendingexception : NoConnectionPendingException;
import flint.java.nio.channels.nonreadablechannelexception : NonReadableChannelException;
import flint.java.nio.channels.nonwritablechannelexception : NonWritableChannelException;
import flint.java.nio.channels.notyetboundexception : NotYetBoundException;
import flint.java.nio.channels.notyetconnectedexception : NotYetConnectedException;
import flint.java.nio.channels.overlappingfilelockexception : OverlappingFileLockException;
import flint.java.nio.channels.readpendingexception : ReadPendingException;
import flint.java.nio.channels.shutdownchannelgroupexception : ShutdownChannelGroupException;
import flint.java.nio.channels.unresolvedaddressexception : UnresolvedAddressException;
import flint.java.nio.channels.unsupportedaddresstypeexception : UnsupportedAddressTypeException;
import flint.java.nio.channels.writependingexception : WritePendingException;

@safe:

private void verifyChannelException(E, Base)()
{
    auto ex = new E;
    assert(ex.getMessage() is null);
    assert(ex.getCause() is null);

    auto root = new RuntimeException("root");
    assert(ex.initCause(root) is ex);
    assert(ex.getCause() is root);

    bool secondInitFailed;
    try
        ex.initCause(new RuntimeException("second"));
    catch (IllegalStateException)
        secondInitFailed = true;
    assert(secondInitFailed);

    Base caughtBase;
    try
        throw ex;
    catch (Base value)
        caughtBase = value;
    assert(cast(E) caughtBase is ex);

    RuntimeException caughtRuntime;
    try
        throw ex;
    catch (RuntimeException value)
        caughtRuntime = value;
    assert(cast(E) caughtRuntime is ex);
}

@("All 16 IllegalStateException-derived java.nio.channels exceptions match Java SE 21 contracts")
unittest
{
    verifyChannelException!(AcceptPendingException, IllegalStateException)();
    verifyChannelException!(AlreadyBoundException, IllegalStateException)();
    verifyChannelException!(AlreadyConnectedException, IllegalStateException)();
    verifyChannelException!(CancelledKeyException, IllegalStateException)();
    verifyChannelException!(ClosedSelectorException, IllegalStateException)();
    verifyChannelException!(ConnectionPendingException, IllegalStateException)();
    verifyChannelException!(IllegalBlockingModeException, IllegalStateException)();
    verifyChannelException!(NoConnectionPendingException, IllegalStateException)();
    verifyChannelException!(NonReadableChannelException, IllegalStateException)();
    verifyChannelException!(NonWritableChannelException, IllegalStateException)();
    verifyChannelException!(NotYetBoundException, IllegalStateException)();
    verifyChannelException!(NotYetConnectedException, IllegalStateException)();
    verifyChannelException!(OverlappingFileLockException, IllegalStateException)();
    verifyChannelException!(ReadPendingException, IllegalStateException)();
    verifyChannelException!(ShutdownChannelGroupException, IllegalStateException)();
    verifyChannelException!(WritePendingException, IllegalStateException)();
}

@("All 4 IllegalArgumentException-derived java.nio.channels exceptions match Java SE 21 contracts")
unittest
{
    verifyChannelException!(IllegalChannelGroupException, IllegalArgumentException)();
    verifyChannelException!(IllegalSelectorException, IllegalArgumentException)();
    verifyChannelException!(UnresolvedAddressException, IllegalArgumentException)();
    verifyChannelException!(UnsupportedAddressTypeException, IllegalArgumentException)();
}
