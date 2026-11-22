"""gdb pretty-printers for Flint values (ADR-021 section 7, ADR-027).

Loaded by `flint run --debug` and by the launch configurations `flint generate debug` writes:

    (gdb) source <flint>/tools/debug/flint_gdb.py

They print what a reader needs instead of raw fields: a Result as `ok: <value>` or `error: <Status> "message"`,
an Error with its status name, Buffer and Text handles with their size and arena identity, a RequestArena with its
use, a Context with its deadline, and D strings and slices as values.
"""
import re

import gdb
import gdb.printing

STATUS = ['ok', 'invalidArgument', 'outOfMemory', 'cancelled', 'timedOut', 'notFound', 'conflict', 'ioError',
          'unavailable', 'unsupported', 'permissionDenied', 'resourceExhausted']
NO_DEADLINE = (1 << 63) - 1


def field(value, name):
    """A struct member by name, or None (private members are ordinary fields in DWARF)."""
    try:
        return value[name]
    except gdb.error:
        return None


def d_string(value, limit=200):
    """A D `string` or `const(char)[]`: {length, ptr}."""
    length = int(value['length'])
    if length == 0:
        return '""'
    text = value['ptr'].string(length=min(length, limit), errors='replace')
    return repr(text) + ('...' if length > limit else '')


def status_code(error):
    """The `Status` of an Error. DMD emits the enum as an incomplete type, so read its int at the field's offset."""
    error = error.referenced_value() if error.type.code == gdb.TYPE_CODE_REF else error
    for item in error.type.strip_typedefs().fields():
        if item.name == 'code':
            address = int(error.address) + item.bitpos // 8
            return int(gdb.Value(address).cast(gdb.lookup_type('int').pointer()).dereference())
    return 0


def status_name(code):
    return STATUS[code] if 0 <= code < len(STATUS) else 'status(%d)' % code


class ErrorPrinter:
    def __init__(self, value):
        self.value = value

    def to_string(self):
        code = status_name(status_code(self.value))
        if code == 'ok':
            return 'ok'
        message = d_string(self.value['message'])
        offset = int(self.value['offset'])
        where = '' if offset == (1 << 64) - 1 else ' at byte %d' % offset
        return '%s %s%s' % (code, message, where)


class ResultPrinter:
    def __init__(self, value):
        self.value = value

    def to_string(self):
        error = self.value['error']
        if status_code(error) == 0:
            return 'ok: %s' % self.value['value'].format_string()
        return 'error: %s' % ErrorPrinter(error).to_string()


class BufferPrinter:
    def __init__(self, value):
        self.value = value

    def to_string(self):
        count = int(self.value['count'])
        if int(self.value['owner']) == 0:
            return 'Buffer(empty)'
        return 'Buffer(%d bytes at %d, arena %d epoch %d)' % (count, int(self.value['start']),
                                                              int(self.value['owner']), int(self.value['epoch']))


class TextPrinter:
    def __init__(self, value):
        self.value = value

    def to_string(self):
        return 'Text(%s)' % BufferPrinter(self.value['bytes']).to_string()[7:-1]


class ArenaPrinter:
    def __init__(self, value):
        self.value = value

    def to_string(self):
        capacity = int(self.value['storage']['length'])
        return 'RequestArena(%d of %d bytes used, peak %d, %d borrows, arena %d epoch %d)' % (
            int(self.value['cursor']), capacity, int(self.value['peak']), int(self.value['activeBorrows']),
            int(self.value['owner']), int(self.value['epoch']))


class ContextPrinter:
    def __init__(self, value):
        self.value = value

    def to_string(self):
        identity = int(self.value['id'])
        deadline = int(self.value['deadlineValue']['monotonicNanoseconds'])
        when = 'no deadline' if deadline == NO_DEADLINE else 'deadline at %d ns' % deadline
        return 'Context(%s, %s)' % ('background' if identity == 0 else 'id %d' % identity, when)


class StringPrinter:
    def __init__(self, value):
        self.value = value

    def to_string(self):
        return d_string(self.value)


PRINTERS = [
    (r'^flint\.arena\.Error$', ErrorPrinter),
    (r'^flint\.arena\.Result!\(.*\)\.Result$|^flint\.arena\.Result!.*', ResultPrinter),
    (r'^flint\.arena\.Buffer$', BufferPrinter),
    (r'^flint\.arena\.Text$', TextPrinter),
    (r'^flint\.arena\.RequestArena$', ArenaPrinter),
    (r'^flint\.conc\.Context$', ContextPrinter),
    (r'^(immutable\(char\)|const\(char\)|char)\[\]$|^string$', StringPrinter),
]


def lookup(value):
    name = value.type.strip_typedefs().unqualified().tag or str(value.type.strip_typedefs().unqualified())
    for pattern, printer in PRINTERS:
        if name and re.match(pattern, name):
            return printer(value)
    return None


gdb.pretty_printers.append(lookup)
