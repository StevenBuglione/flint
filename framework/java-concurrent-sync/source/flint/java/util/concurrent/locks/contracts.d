/*
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

/*
 * This file is available under and governed by the GNU General Public
 * License version 2 only, as published by the Free Software Foundation.
 * However, the following notice accompanied the original version of this
 * file:
 *
 * Written by Doug Lea with assistance from members of JCP JSR-166
 * Expert Group and released to the public domain, as explained at
 * http://creativecommons.org/publicdomain/zero/1.0/
 */

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/concurrent/locks/Lock.java
// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/concurrent/locks/Condition.java
// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/concurrent/locks/ReadWriteLock.java
// Modified by the Flint authors.
module flint.java.util.concurrent.locks.contracts;

import flint.java.util.concurrent : TimeUnit;
import flint.java.util.date : Date;

@safe:

/// An explicit lock with blocking, interruptible, and nonblocking acquisition.
interface Lock
{
    /// Acquire the lock, waiting if necessary.
    void lock();

    /// Acquire the lock or propagate InterruptedException.
    void lockInterruptibly();

    /// Acquire the lock immediately if it is available.
    bool tryLock();

    /// Acquire the lock before the timeout or propagate InterruptedException.
    bool tryLock(long time, TimeUnit unit);

    /// Release this acquisition of the lock.
    void unlock();

    /// Create a condition associated with this lock.
    Condition newCondition();
}

/// An object that waits for a condition while releasing its associated lock.
interface Condition
{
    /// Wait and reacquire the lock before returning or propagating InterruptedException.
    void await();

    /// Wait through interruption and reacquire the lock before returning.
    void awaitUninterruptibly();

    /// Wait up to the specified nanoseconds and return an estimate of the remaining time.
    /// Propagates InterruptedException if interrupted.
    long awaitNanos(long nanosTimeout);

    /// Wait up to the specified time and report whether the wait avoided timing out.
    /// Propagates InterruptedException if interrupted.
    bool await(long time, TimeUnit unit);

    /// Wait until the deadline and report whether the wait avoided timing out.
    /// Propagates InterruptedException if interrupted.
    /// Implementations reject a null deadline with NullPointerException.
    bool awaitUntil(Date deadline);

    /// Wake one waiting task so it can reacquire the lock.
    void signal();

    /// Wake all waiting tasks so they can reacquire the lock.
    void signalAll();
}

/// A pair of locks for shared reading and exclusive writing.
interface ReadWriteLock
{
    /// Return the shared read lock.
    Lock readLock();

    /// Return the exclusive write lock.
    Lock writeLock();
}
