/// Allocation-free validation of caller-owned DTOs and arena-backed text.
module flint.validate;

import flint.arena : RequestArena;
import flint.validate.internal.schema : validateCore;

@safe:

/// Recursively validate a nested struct or collection of structs.
struct Valid
{
}

/// Require at least one non-whitespace Unicode scalar.
struct NotBlank
{
}

/// Inclusive numeric lower bound.
struct Min
{
    /// Lower endpoint.
    long value;
}

/// Inclusive numeric upper bound.
struct Max
{
    /// Upper endpoint.
    long value;
}

/// Require an unquoted ASCII email address.
struct Email
{
}

/// Require a full match against a compile-time regular expression.
struct Pattern
{
    /// The supported ASCII pattern syntax.
    string value;
}

/// Inclusive length interval, measured in Unicode scalars for UTF-8 text.
struct Size
{
    /// Minimum accepted length.
    size_t min;
    /// Maximum accepted length.
    size_t max;
}

/// One failed constraint and the static path of its associated field.
struct Violation
{
    /// Field path. Array positions appear as [].
    string field;
    /// Name of the failed constraint.
    string constraint;
    /// Static diagnostic text with no input values embedded.
    string message;
    /// Positions corresponding to [] segments in the field path.
    uint[8] indexes;
    /// Number of populated positions.
    ubyte indexCount;
}

/// Counts of stored and encountered failures.
struct ValidationReport
{
    /// Number of output elements used.
    size_t written;
    /// Number of violations. 4097 signals overflow beyond 4096.
    size_t total;
    /// True when no constraint failed.
    bool valid;
}

private struct ValidationTypes
{
    alias Nested = Valid;
    alias NonBlank = NotBlank;
    alias Minimum = Min;
    alias Maximum = Max;
    alias Mail = Email;
    alias Expression = Pattern;
    alias Length = Size;
    alias Diagnostic = Violation;
    alias Report = ValidationReport;
}

/// Validate the supplied value. Arena text requires validateIn.
ValidationReport validate(T)(scope const ref T value, scope Violation[] output) nothrow @nogc
{
    RequestArena unavailable;
    return validateCore!(T, ValidationTypes)(value, unavailable, output);
}

/// Validate the supplied value and resolve Text through its owning arena.
ValidationReport validateIn(T)(scope const ref T dto, ref scope RequestArena arena, scope Violation[] log) nothrow @nogc
{
    return validateCore!(T, ValidationTypes)(dto, arena, log);
}
