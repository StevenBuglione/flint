"""lldb summaries for Flint values (ADR-021 section 7, ADR-027); the lldb twin of flint_gdb.py.

    (lldb) command script import <flint>/tools/debug/flint_lldb.py
"""
import lldb

STATUS = ['ok', 'invalidArgument', 'outOfMemory', 'cancelled', 'timedOut', 'notFound', 'conflict', 'ioError',
          'unavailable', 'unsupported', 'permissionDenied', 'resourceExhausted']


def d_string(value, limit=200):
    length = value.GetChildMemberWithName('length').GetValueAsUnsigned()
    if length == 0:
        return '""'
    pointer = value.GetChildMemberWithName('ptr').GetValueAsUnsigned()
    error = lldb.SBError()
    data = value.GetProcess().ReadMemory(pointer, min(length, limit), error)
    text = data.decode('utf-8', 'replace') if error.Success() else '<unreadable>'
    return repr(text) + ('...' if length > limit else '')


def status(error_value):
    code = error_value.GetChildMemberWithName('code').GetValueAsSigned()
    return STATUS[code] if 0 <= code < len(STATUS) else 'status(%d)' % code


def error_summary(value, _):
    name = status(value)
    if name == 'ok':
        return 'ok'
    return '%s %s' % (name, d_string(value.GetChildMemberWithName('message')))


def result_summary(value, _):
    error = value.GetChildMemberWithName('error')
    if status(error) == 'ok':
        inner = value.GetChildMemberWithName('value')
        return 'ok: %s' % (inner.GetSummary() or inner.GetValue() or inner.GetTypeName())
    return 'error: %s' % error_summary(error, None)


def buffer_summary(value, _):
    get = lambda name: value.GetChildMemberWithName(name).GetValueAsUnsigned()
    if get('owner') == 0:
        return 'Buffer(empty)'
    return 'Buffer(%d bytes at %d, arena %d epoch %d)' % (get('count'), get('start'), get('owner'), get('epoch'))


def arena_summary(value, _):
    get = lambda name: value.GetChildMemberWithName(name).GetValueAsUnsigned()
    capacity = value.GetChildMemberWithName('storage').GetChildMemberWithName('length').GetValueAsUnsigned()
    return 'RequestArena(%d of %d bytes used, peak %d, %d borrows)' % (get('cursor'), capacity, get('peak'),
                                                                      get('activeBorrows'))


def string_summary(value, _):
    return d_string(value)


def __lldb_init_module(debugger, _):
    for pattern, function in [('^flint\\.arena\\.Error$', 'error_summary'),
                              ('^flint\\.arena\\.Result!', 'result_summary'),
                              ('^flint\\.arena\\.Buffer$', 'buffer_summary'),
                              ('^flint\\.arena\\.RequestArena$', 'arena_summary'),
                              ('^(immutable\\(char\\)|const\\(char\\)|char)\\[\\]$|^string$', 'string_summary')]:
        debugger.HandleCommand('type summary add -x "%s" -F flint_lldb.%s' % (pattern, function))
