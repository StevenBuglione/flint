module java_concurrent_lock_contract_test;

import flint.java.util.concurrent : TimeUnit;
import flint.java.util.concurrent.locks : Condition, Lock, ReadWriteLock;
import flint.java.util.concurrent.locks.contracts : LeafCondition = Condition, LeafLock = Lock,
    LeafReadWriteLock = ReadWriteLock;
import flint.java.util.date : Date;

@safe:

@("Java lock and condition signatures use the canonical TimeUnit and Date")
unittest
{
    static assert(is(Lock == interface) && is(Condition == interface) && is(ReadWriteLock == interface));
    static assert(is(Lock == LeafLock) && is(Condition == LeafCondition) && is(ReadWriteLock == LeafReadWriteLock));

    static assert(is(typeof(Lock.init.lock()) == void));
    static assert(is(typeof(Lock.init.lockInterruptibly()) == void));
    static assert(is(typeof(Lock.init.tryLock()) == bool));
    static assert(is(typeof(Lock.init.tryLock(0L, TimeUnit.NANOSECONDS)) == bool));
    static assert(!__traits(compiles, Lock.init.tryLock(0L, null)));
    static assert(is(typeof(Lock.init.unlock()) == void));
    static assert(is(typeof(Lock.init.newCondition()) == Condition));

    static assert(is(typeof(Condition.init.await()) == void));
    static assert(is(typeof(Condition.init.awaitUninterruptibly()) == void));
    static assert(is(typeof(Condition.init.awaitNanos(0L)) == long));
    static assert(is(typeof(Condition.init.await(0L, TimeUnit.NANOSECONDS)) == bool));
    static assert(!__traits(compiles, Condition.init.await(0L, null)));
    static assert(is(typeof(Condition.init.awaitUntil(Date.init)) == bool));
    static assert(is(typeof(Condition.init.signal()) == void));
    static assert(is(typeof(Condition.init.signalAll()) == void));

    static assert(is(typeof(ReadWriteLock.init.readLock()) == Lock));
    static assert(is(typeof(ReadWriteLock.init.writeLock()) == Lock));
}
