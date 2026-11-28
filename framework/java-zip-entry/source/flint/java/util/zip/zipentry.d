/*
 * Copyright (c) 1995, 2022, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13:
//   src/java.base/share/classes/java/util/zip/ZipEntry.java
//   src/java.base/share/classes/java/util/zip/ZipUtils.java (the entry-time helpers)
//   src/java.base/share/classes/java/util/zip/ZipConstants64.java (the extra-field tags)
// Modified by the Flint authors: a D class, `FileTime` is a value struct (R11) so a nullable time is
// `Nullable!FileTime` (R5) and its setter takes the value type only, and the default zone is UTC.

module flint.java.util.zip.zipentry;

import flint.java.lang : IllegalArgumentException, NullPointerException, stringHashCode;
import flint.java.nio.file.attribute.filetime : FileTime;
import flint.java.time : DateTimeException, Instant, LocalDateTime, ZoneId, ZonedDateTime;
import flint.java.util.concurrent : TimeUnit, toMillis;
import std.typecons : Nullable;

@safe:

// Approximately 128 years, in milliseconds (ignoring leap years etc).
// This establishes an approximate high-bound value for DOS times in milliseconds since epoch, used to
// enable an efficient but sufficient bounds check to avoid generating extended last modified time entries.
private enum long UPPER_DOSTIME_BOUND = 128L * 365 * 24 * 60 * 60 * 1000;

// Extra-field tags (ZipConstants64).
private enum int EXTID_ZIP64 = 0x0001; // Zip64
private enum int EXTID_NTFS = 0x000a; // NTFS
private enum int EXTID_EXTT = 0x5455; // Info-ZIP Extended Timestamp
private enum long ZIP64_MAGICVAL = 0xFFFFFFFFL;
private enum long WINDOWS_TIME_NOT_AVAILABLE = long.min;
// used to adjust values between Windows and java epoch
private enum long WINDOWS_EPOCH_IN_MICROSECONDS = -11_644_473_600_000_000L;

/// This class is used to represent a ZIP file entry.
class ZipEntry
{
    package(flint.java.util.zip) string name; // entry name
    package(flint.java.util.zip) long xdostime = -1; // last modification time (in extended DOS time,
    // where milliseconds lost in conversion might
    // be encoded into the upper half)
    package(flint.java.util.zip) Nullable!FileTime mtime; // last modification time, from extra field data
    package(flint.java.util.zip) Nullable!FileTime atime; // last access time, from extra field data
    package(flint.java.util.zip) Nullable!FileTime ctime; // creation time, from extra field data
    package(flint.java.util.zip) long crc = -1; // crc-32 of entry data
    package(flint.java.util.zip) long size = -1; // uncompressed size of entry data
    package(flint.java.util.zip) long csize = -1; // compressed size of entry data
    package(flint.java.util.zip) bool csizeSet = false; // Only true if csize was explicitly set by
    // a call to setCompressedSize()
    package(flint.java.util.zip) int method = -1; // compression method
    package(flint.java.util.zip) int flag = 0; // general purpose flag
    package(flint.java.util.zip) byte[] extra; // optional extra field data for entry
    package(flint.java.util.zip) string comment; // optional comment string for entry
    package(flint.java.util.zip) int extraAttributes = -1; // e.g. POSIX permissions, sym links.

    /// Compression method for uncompressed entries.
    enum int STORED = 0;

    /// Compression method for compressed (deflated) entries.
    enum int DEFLATED = 8;

    /// DOS time constant for representing timestamps before 1980.
    package(flint.java.util.zip) enum long DOSTIME_BEFORE_1980 = (1L << 21) | (1L << 16);

    /// Creates a new zip entry with the specified name.
    this(string name)
    {
        if (name is null)
            throw new NullPointerException("name");
        if (name.length > 0xFFFF)
            throw new IllegalArgumentException("entry name too long");
        this.name = name;
    }

    /// Creates a new zip entry with fields taken from the specified zip entry.
    this(ZipEntry e)
    {
        if (e is null)
            throw new NullPointerException("entry");
        name = e.name;
        xdostime = e.xdostime;
        mtime = e.mtime;
        atime = e.atime;
        ctime = e.ctime;
        crc = e.crc;
        size = e.size;
        csize = e.csize;
        csizeSet = e.csizeSet;
        method = e.method;
        flag = e.flag;
        extra = e.extra;
        comment = e.comment;
        extraAttributes = e.extraAttributes;
    }

    /// Returns the name of the entry.
    string getName()
    {
        return name;
    }

    /// Sets the last modification time of the entry, in milliseconds since the epoch.
    void setTime(long time)
    {
        this.xdostime = javaToExtendedDosTime(time);
        // Avoid setting the mtime field if time is in the valid range for a DOS time
        if (this.xdostime != DOSTIME_BEFORE_1980 && time <= UPPER_DOSTIME_BOUND)
        {
            this.mtime = Nullable!FileTime.init;
        }
        else
        {
            const localYear = javaEpochToLocalDateTime(time).getYear();
            if (localYear >= 1980 && localYear <= 2099)
                this.mtime = Nullable!FileTime.init;
            else
                this.mtime = Nullable!FileTime(FileTime.from(time, TimeUnit.MILLISECONDS));
        }
    }

    /// Returns the last modification time of the entry in milliseconds since the epoch, or -1 if not specified.
    long getTime()
    {
        if (!mtime.isNull)
            return mtime.get.toMillis();
        return (xdostime != -1) ? extendedDosToJavaTime(xdostime) : -1;
    }

    /// Sets the last modification time of the entry in local date-time.
    void setTimeLocal(LocalDateTime time)
    {
        const year = time.getYear() - 1980;
        const second = time.getSecond();
        if (year < 0)
        {
            this.xdostime = DOSTIME_BEFORE_1980;
        }
        else
        {
            const dos = (cast(long) year << 25) | (cast(long) time.getMonthValue() << 21) | (
                    cast(long) time.getDayOfMonth() << 16) | (cast(long) time.getHour() << 11) | (
                    cast(long) time.getMinute() << 5) | (cast(long) second >> 1);
            this.xdostime = (dos & 0xffffffffL) + (cast(long)(((second & 0x1) * 1000) + time.getNano() / 1_000_000) << 32);
        }
        if (xdostime != DOSTIME_BEFORE_1980 && year <= 0x7f)
            this.mtime = Nullable!FileTime.init;
        else
            this.mtime = Nullable!FileTime(FileTime.from(ZonedDateTime.of(time, ZoneId.systemDefault()).toInstant()));
    }

    /// Returns the last modification time of the entry in local date-time.
    LocalDateTime getTimeLocal()
    {
        if (!mtime.isNull)
            return LocalDateTime.ofInstant(mtime.get.toInstant(), ZoneId.systemDefault());
        const ms = cast(int)(xdostime >> 32);
        return LocalDateTime.of(cast(int)(((xdostime >> 25) & 0x7f) + 1980),
                cast(int)((xdostime >> 21) & 0x0f), cast(int)((xdostime >> 16) & 0x1f),
                cast(int)((xdostime >> 11) & 0x1f), cast(int)((xdostime >> 5) & 0x3f),
                cast(int)((xdostime << 1) & 0x3e) + ms / 1000, (ms % 1000) * 1_000_000);
    }

    /// Sets the last modification time of the entry.
    ZipEntry setLastModifiedTime(FileTime time)
    {
        this.mtime = Nullable!FileTime(time);
        this.xdostime = javaToExtendedDosTime(time.to(TimeUnit.MILLISECONDS));
        return this;
    }

    /// Returns the last modification time of the entry, or an empty `Nullable` if not specified.
    Nullable!FileTime getLastModifiedTime()
    {
        if (!mtime.isNull)
            return mtime;
        if (xdostime == -1)
            return Nullable!FileTime.init;
        return Nullable!FileTime(FileTime.from(getTime(), TimeUnit.MILLISECONDS));
    }

    /// Sets the last access time of the entry.
    ZipEntry setLastAccessTime(FileTime time)
    {
        this.atime = Nullable!FileTime(time);
        return this;
    }

    /// Returns the last access time of the entry, or an empty `Nullable` if not specified.
    Nullable!FileTime getLastAccessTime()
    {
        return atime;
    }

    /// Sets the creation time of the entry.
    ZipEntry setCreationTime(FileTime time)
    {
        this.ctime = Nullable!FileTime(time);
        return this;
    }

    /// Returns the creation time of the entry, or an empty `Nullable` if not specified.
    Nullable!FileTime getCreationTime()
    {
        return ctime;
    }

    /// Sets the uncompressed size of the entry data.
    void setSize(long size)
    {
        if (size < 0)
            throw new IllegalArgumentException("invalid entry size");
        this.size = size;
    }

    /// Returns the uncompressed size of the entry data, or -1 if not known.
    long getSize()
    {
        return size;
    }

    /// Returns the size of the compressed entry data.
    long getCompressedSize()
    {
        return csize;
    }

    /// Sets the size of the compressed entry data.
    void setCompressedSize(long csize)
    {
        this.csize = csize;
        this.csizeSet = true;
    }

    /// Sets the CRC-32 checksum of the uncompressed entry data.
    void setCrc(long crc)
    {
        if (crc < 0 || crc > 0xFFFFFFFFL)
            throw new IllegalArgumentException("invalid entry crc-32");
        this.crc = crc;
    }

    /// Returns the CRC-32 checksum of the uncompressed entry data, or -1 if not known.
    long getCrc()
    {
        return crc;
    }

    /// Sets the compression method for the entry.
    void setMethod(int method)
    {
        if (method != STORED && method != DEFLATED)
            throw new IllegalArgumentException("invalid compression method");
        this.method = method;
    }

    /// Returns the compression method of the entry, or -1 if not specified.
    int getMethod()
    {
        return method;
    }

    /// Sets the optional extra field data for the entry.
    void setExtra(byte[] extra)
    {
        setExtra0(extra, false, true);
    }

    /// Sets the optional extra field data, optionally reading ZIP64 sizes, for a LOC or CEN header.
    package(flint.java.util.zip) void setExtra0(byte[] extra, bool doZIP64, bool isLOC)
    {
        if (extra !is null)
        {
            if (extra.length > 0xFFFF)
                throw new IllegalArgumentException("invalid extra field length");
            // extra fields are in "HeaderID(2)DataSize(2)Data..." format
            size_t off = 0;
            const len = extra.length;
            while (off + 4 < len)
            {
                const tag = get16(extra, off);
                const sz = get16(extra, off + 2);
                off += 4;
                if (off + sz > len) // invalid data
                    break;
                switch (tag)
                {
                case EXTID_ZIP64:
                    if (doZIP64)
                    {
                        if (isLOC)
                        {
                            // LOC extra zip64 entry MUST include BOTH original and compressed file size
                            // fields. If invalid zip64 extra fields, simply skip.
                            if (sz >= 16)
                            {
                                size = get64(extra, off);
                                csize = get64(extra, off + 8);
                            }
                        }
                        else
                        {
                            // CEN extra zip64
                            if (size == ZIP64_MAGICVAL)
                            {
                                if (off + 8 > len) // invalid zip64 extra fields, just skip
                                    break;
                                size = get64(extra, off);
                            }
                            if (csize == ZIP64_MAGICVAL)
                            {
                                if (off + 16 > len) // invalid zip64 extra fields, just skip
                                    break;
                                csize = get64(extra, off + 8);
                            }
                        }
                    }
                    break;
                case EXTID_NTFS:
                    if (sz < 32) // reserved 4 bytes + tag 2 bytes + size 2 bytes
                        break; // m[a|c]time 24 bytes
                    const pos = off + 4; // reserved 4 bytes
                    if (get16(extra, pos) != 0x0001 || get16(extra, pos + 2) != 24)
                        break;
                    long wtime = get64(extra, pos + 4);
                    if (wtime != WINDOWS_TIME_NOT_AVAILABLE)
                        mtime = Nullable!FileTime(winTimeToFileTime(wtime));
                    wtime = get64(extra, pos + 12);
                    if (wtime != WINDOWS_TIME_NOT_AVAILABLE)
                        atime = Nullable!FileTime(winTimeToFileTime(wtime));
                    wtime = get64(extra, pos + 20);
                    if (wtime != WINDOWS_TIME_NOT_AVAILABLE)
                        ctime = Nullable!FileTime(winTimeToFileTime(wtime));
                    break;
                case EXTID_EXTT:
                    const extFlag = cast(int)(extra[off] & 0xff);
                    int sz0 = 1;
                    // The CEN-header extra field contains the modification time only, or no timestamp at
                    // all. 'sz' is used to flag its presence or absence. But if mtime is present in LOC it
                    // must be present in CEN as well.
                    if ((extFlag & 0x1) != 0 && (sz0 + 4) <= sz)
                    {
                        mtime = Nullable!FileTime(unixTimeToFileTime(get32S(extra, off + sz0)));
                        sz0 += 4;
                    }
                    if ((extFlag & 0x2) != 0 && (sz0 + 4) <= sz)
                    {
                        atime = Nullable!FileTime(unixTimeToFileTime(get32S(extra, off + sz0)));
                        sz0 += 4;
                    }
                    if ((extFlag & 0x4) != 0 && (sz0 + 4) <= sz)
                    {
                        ctime = Nullable!FileTime(unixTimeToFileTime(get32S(extra, off + sz0)));
                        sz0 += 4;
                    }
                    break;
                default:
                }
                off += sz;
            }
        }
        this.extra = extra;
    }

    /// Returns the extra field data for the entry, or null if none.
    byte[] getExtra()
    {
        return extra;
    }

    /// Sets the optional comment string for the entry.
    void setComment(string comment)
    {
        this.comment = comment;
    }

    /// Returns the comment string for the entry, or null if none.
    string getComment()
    {
        return comment;
    }

    /// Returns true if this is a directory entry: one whose name ends with a '/'.
    bool isDirectory()
    {
        return name.length > 0 && name[$ - 1] == '/';
    }

    /// Returns a string representation of the ZIP entry.
    override string toString()
    {
        return getName();
    }

    /// Returns the hash code value for this entry.
    int hashCode()
    {
        return stringHashCode(name);
    }

    /// Returns a copy of this entry.
    Object clone()
    {
        auto copy = new ZipEntry(this);
        copy.extra = extra is null ? null : extra.dup;
        return copy;
    }
}

// ---------------------------------------------------------------------------------------------------------------
// ZipUtils entry-time helpers

private FileTime winTimeToFileTime(long wtime)
{
    return FileTime.from(wtime / 10 + WINDOWS_EPOCH_IN_MICROSECONDS, TimeUnit.MICROSECONDS);
}

private FileTime unixTimeToFileTime(long utime)
{
    return FileTime.from(utime, TimeUnit.SECONDS);
}

private long extendedDosToJavaTime(long xdostime)
{
    const time = dosToJavaTime(xdostime);
    return time + (xdostime >> 32);
}

private LocalDateTime javaEpochToLocalDateTime(long time)
{
    const instant = Instant.ofEpochMilli(time);
    return LocalDateTime.ofInstant(instant, ZoneId.systemDefault());
}

private long javaToExtendedDosTime(long time)
{
    const ldt = javaEpochToLocalDateTime(time);
    if (ldt.getYear() >= 1980)
        return javaToDosTime(ldt) + ((time % 2000) << 32);
    return ZipEntry.DOSTIME_BEFORE_1980;
}

private long javaToDosTime(LocalDateTime ldt)
{
    const dos = (cast(long)(ldt.getYear() - 1980) << 25) | (cast(long) ldt.getMonthValue() << 21) | (
            cast(long) ldt.getDayOfMonth() << 16) | (cast(long) ldt.getHour() << 11) | (
            cast(long) ldt.getMinute() << 5) | (cast(long) ldt.getSecond() >> 1);
    return dos & 0xffffffffL;
}

private long dosToJavaTime(long dtime)
{
    const year = cast(int)(((dtime >> 25) & 0x7f) + 1980);
    const month = cast(int)((dtime >> 21) & 0x0f);
    const day = cast(int)((dtime >> 16) & 0x1f);
    const hour = cast(int)((dtime >> 11) & 0x1f);
    const minute = cast(int)((dtime >> 5) & 0x3f);
    const second = cast(int)((dtime << 1) & 0x3e);

    if (month > 0 && month < 13 && day > 0 && hour < 24 && minute < 60 && second < 60)
    {
        try
        {
            const ldt = LocalDateTime.of(year, month, day, hour, minute, second);
            return TimeUnit.SECONDS.toMillis(ldt.toEpochSecond(ZoneId.systemDefault().offset()));
        }
        catch (DateTimeException)
        {
            // ignore
        }
    }
    return overflowDosToJavaTime(year, month, day, hour, minute, second);
}

// Deal with corner cases where an arguably mal-formed DOS time is used. Java's deprecated Date field
// constructor (year-1900, month-1, day, hour, minute, second) normalises the fields in the default zone; the
// default zone is UTC in Flint, so the arithmetic is the proleptic Gregorian day plus the normalised clock.
private long overflowDosToJavaTime(int year, int month, int day, int hour, int minute, int second)
{
    int y = year - 1900;
    int m = month - 1;
    y += m / 12;
    m %= 12;
    if (m < 0)
    {
        m += 12;
        y--;
    }
    const epochDay = daysFromCivil(y, m + 1, 1) + (day - 1);
    return (epochDay * 86_400L + hour * 3_600L + minute * 60L + second) * 1_000L;
}

// Days since 1970-01-01 of a proleptic Gregorian date (Howard Hinnant's civil-from-days inverse).
private long daysFromCivil(long y, int m, int d)
{
    y -= m <= 2;
    const era = (y >= 0 ? y : y - 399) / 400;
    const yoe = y - era * 400;
    const doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    const doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146_097 + doe - 719_468;
}

// ---------------------------------------------------------------------------------------------------------------
// Little-endian field readers (ZipUtils)

private int get16(scope const(byte)[] b, size_t off)
{
    return (b[off] & 0xff) | ((b[off + 1] & 0xff) << 8);
}

private long get32(scope const(byte)[] b, size_t off)
{
    return (get16(b, off) | (cast(long) get16(b, off + 2) << 16)) & 0xffffffffL;
}

private long get64(scope const(byte)[] b, size_t off)
{
    return get32(b, off) | (get32(b, off + 4) << 32);
}

private int get32S(scope const(byte)[] b, size_t off)
{
    return get16(b, off) | (get16(b, off + 2) << 16);
}
