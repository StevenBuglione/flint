/*
 * Copyright 2017 VMware, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/util/TimeUtils.java
// Modified by the Flint authors.
module flint.micrometer.core.instrument.util;

import flint.java.util.concurrent : TimeUnit, toNanos;

@safe:

/// Time unit conversions for measurements with fractional precision.
final class TimeUtils
{
    private this()
    {
    }

    /// Convert between units using a single multiplication or division.
    static double convert(double amount, TimeUnit sourceUnit, TimeUnit destinationUnit) pure nothrow @nogc
    {
        if (sourceUnit == destinationUnit)
            return amount;

        const sourceNanos = sourceUnit.toNanos(1);
        const destinationNanos = destinationUnit.toNanos(1);
        return sourceNanos < destinationNanos ? amount / (destinationNanos / sourceNanos) : amount * (
                sourceNanos / destinationNanos);
    }

    /// Convert a measurement in nanoseconds.
    static double nanosToUnit(double amount, TimeUnit destinationUnit) pure nothrow @nogc
    {
        return destinationUnit == TimeUnit.NANOSECONDS ? amount : amount / destinationUnit.toNanos(1);
    }

    /// Convert a measurement in microseconds.
    static double microsToUnit(double amount, TimeUnit destinationUnit) pure nothrow @nogc
    {
        return convert(amount, TimeUnit.MICROSECONDS, destinationUnit);
    }

    /// Convert a measurement in milliseconds.
    static double millisToUnit(double amount, TimeUnit destinationUnit) pure nothrow @nogc
    {
        return convert(amount, TimeUnit.MILLISECONDS, destinationUnit);
    }

    /// Convert a measurement in seconds.
    static double secondsToUnit(double amount, TimeUnit destinationUnit) pure nothrow @nogc
    {
        return convert(amount, TimeUnit.SECONDS, destinationUnit);
    }

    /// Convert a measurement in minutes.
    static double minutesToUnit(double amount, TimeUnit destinationUnit) pure nothrow @nogc
    {
        return convert(amount, TimeUnit.MINUTES, destinationUnit);
    }

    /// Convert a measurement in hours.
    static double hoursToUnit(double amount, TimeUnit destinationUnit) pure nothrow @nogc
    {
        return convert(amount, TimeUnit.HOURS, destinationUnit);
    }

    /// Convert a measurement in days.
    static double daysToUnit(double amount, TimeUnit destinationUnit) pure nothrow @nogc
    {
        return convert(amount, TimeUnit.DAYS, destinationUnit);
    }
}
