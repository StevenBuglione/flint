"""The exchange pool's retention audit: `python3 tools/check_exchange_retention.py`.

A servlet exchange's request and response are façades over pooled storage (flint.engine.servlet.exchange). Once the
exchange completes they throw `IllegalStateException`, so a framework object that keeps one past its exchange breaks.
This check lists every field, static or module-level variable whose type is a servlet request, response or stream, or
the engine's pooled states, in non-test D source, and fails on any that is not in the reviewed allowlist below. Each
allowed holder is created per exchange and dies with it. A new holder needs a review that it is never kept in a
singleton, cache, queue or detached task (coordination/notes/exchange-pool.md, retention audit), then an entry here.

This is a tripwire, not a proof: it reads declared field types only. It cannot see a request captured by a closure
or delegate, one held as `Object` or `Any` (a request attribute holding its request, for example), one in an `auto`
typed variable, or one behind an alias. The pool's own guarantee does not rest on it: a retained façade throws
`IllegalStateException` after its exchange, whoever holds it.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOTS = ('framework', 'boot', 'packages', 'starters', 'apps')

RETAINED_TYPES = (
    'HttpServletRequest', 'HttpServletResponse', 'ServletRequest', 'ServletResponse', 'ServletEngineRequest',
    'ServletEngineResponse', 'ServletInputStream', 'ServletOutputStream', 'RequestState', 'ResponseState',
)

# (path, aggregate, field): reviewed holders, each one per exchange.
ALLOWED = {
    ('framework/jakarta-servlet/source/flint/jakarta/servlet/package.d', 'ServletRequestWrapper', 'request'):
        'a filter-made wrapper, passed down the chain of its exchange',
    ('framework/jakarta-servlet/source/flint/jakarta/servlet/package.d', 'ServletResponseWrapper', 'response'):
        'a filter-made wrapper, passed down the chain of its exchange',
    ('framework/web/source/flint/web/context/request/package.d', 'ServletRequestAttributes', 'request'):
        'a ServletWebRequest made per handler call (webmvc annotation.d, fast.d; boot error.d)',
    ('framework/web/source/flint/web/context/request/package.d', 'ServletRequestAttributes', 'response'):
        'a ServletWebRequest made per handler call (webmvc annotation.d, fast.d; boot error.d)',
    ('framework/framework-test/source/flint/mock/web.d', 'MockHttpServletResponse', 'outputStream'):
        "a mock response's own stream, made per test exchange",
    ('framework/web/source/flint/http/server.d', 'ServletServerHttpRequest', 'servletRequest'):
        'made by a message converter call within the exchange',
    ('framework/web/source/flint/http/server.d', 'ServletServerHttpResponse', 'servletResponse'):
        'made by a message converter call within the exchange',
    ('framework/engine-servlet/source/flint/engine/servlet/request.d', 'BodyInput', 'request'):
        "the request's own input stream, checked through the request's generation",
    ('framework/engine-servlet/source/flint/engine/servlet/request.d', 'ServletEngineRequest', 'state'):
        "the façade's pooled storage, checked by its generation",
    ('framework/engine-servlet/source/flint/engine/servlet/response.d', 'ServletEngineResponse', 'state'):
        "the façade's pooled storage, checked by its generation",
    ('framework/engine-servlet/source/flint/engine/servlet/response.d', 'ServletEngineResponse', 'stream'):
        "the façade's own output stream, checked through the response's generation",
}
# The response's output stream and writer (BodyOutput, BodyWriter) hold their response; they are per façade.
ALLOWED_PREFIXES = {
    ('framework/engine-servlet/source/flint/engine/servlet/response.d', 'response'):
        "a response's own output stream or writer, checked through the response's generation",
}

_TYPE = r'(?:const\s*\(\s*|immutable\s*\(\s*|shared\s*\(\s*)?(?:' + '|'.join(RETAINED_TYPES) + r')\b\s*\)?(?:\s*\[\s*\w*\s*\])*'
_ATTRIBUTE = r'(?:@\w+(?:\([^;]*?\))?|private|protected|public|package(?:\([\w.]+\))?|export|static|__gshared|shared|' \
    r'const|immutable|final|override|abstract|extern\([^)]*\)|scope|ref)'
_FIELD = re.compile(r'^(?:\s*' + _ATTRIBUTE + r'\b\s*)*\s*' + _TYPE + r'\s+(\w+)\s*(?:=[^;]*)?$', re.S)
_AGGREGATE = re.compile(r'\b(?:class|struct|union|interface)\s+(\w+)')
_TRANSPARENT = re.compile(r'^\s*(?:(?:else\s+)?(?:version|debug|static\s+if)\b|else\b|extern\s*\(|'
                          r'(?:private|protected|public|package|export|static|__gshared|shared|final|@\w+)\b\s*:?\s*$)')


def _blank(text):
    """The source with comments, strings and character literals blanked, line breaks kept."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        two = text[i:i + 2]
        if two == '//':
            j = text.find('\n', i)
            j = n if j < 0 else j
        elif two == '/*' or two == '/+':
            j = _comment_end(text, i)
        elif c == '"' or c == '`' or (c == "'" and _char_literal(text, i)):
            j = _string_end(text, i)
        elif two in ('r"', 'q"') and (i == 0 or not (text[i - 1].isalnum() or text[i - 1] == '_')):
            j = _string_end(text, i + 1)
        else:
            out.append(c)
            i += 1
            continue
        out.append(re.sub(r'[^\n]', ' ', text[i:j]))
        i = j
    return ''.join(out)


def _comment_end(text, start):
    if text[start + 1] == '*':
        end = text.find('*/', start + 2)
        return len(text) if end < 0 else end + 2
    depth, i = 0, start
    while i < len(text):
        if text.startswith('/+', i):
            depth += 1
            i += 2
        elif text.startswith('+/', i):
            depth -= 1
            i += 2
            if depth == 0:
                return i
        else:
            i += 1
    return len(text)


def _char_literal(text, start):
    return re.match(r"'(?:\\.[^']*|[^\\'])'", text[start:start + 12]) is not None


def _string_end(text, start):
    quote = text[start]
    i = start + 1
    while i < len(text):
        if quote != '`' and text[start - 1:start] != 'r' and text[i] == '\\':
            i += 2
            continue
        if text[i] == quote:
            return i + 1
        i += 1
    return len(text)


def holders(path, text):
    """Every (aggregate or None for module scope, field name, line) of a retained type declared outside a function."""
    source = _blank(text)
    found = []
    scopes = []  # each: ('aggregate', name) | ('function', None) | ('transparent', None)
    segment_start = 0
    for index, c in enumerate(source):
        if c not in '{};':
            continue
        segment = source[segment_start:index]
        if c == '{':
            match = _AGGREGATE.search(segment)
            if match and '(' not in segment[:match.start()].replace('new', ''):
                scopes.append(('aggregate', match.group(1)))
            elif _TRANSPARENT.match(segment) or not segment.strip():
                scopes.append(('transparent', None) if segment.strip() else ('function', None))
            elif re.search(r'\benum\b', segment):
                scopes.append(('enum', None))
            else:
                scopes.append(('function', None))
        elif c == '}':
            if scopes:
                scopes.pop()
        else:
            owner = _effective(scopes)
            if owner is not False:
                match = _FIELD.match(segment.strip())
                if match:
                    line = source.count('\n', 0, segment_start + len(segment) - len(segment.lstrip())) + 1
                    found.append((owner, match.group(1), line))
        segment_start = index + 1
    return found


def _effective(scopes):
    """The aggregate name, None for module scope, or False inside a function or enum."""
    for kind, name in reversed(scopes):
        if kind == 'transparent':
            continue
        return name if kind == 'aggregate' else False
    return None


def _allowed(relative, owner, field):
    if (relative, owner, field) in ALLOWED:
        return True
    return owner is not None and (relative, field) in ALLOWED_PREFIXES


def violations(root=ROOT):
    result = []
    for top in SOURCE_ROOTS:
        for path in sorted((root / top).rglob('*.d')):
            relative = path.relative_to(root).as_posix()
            if '/source/' not in relative or '/tests/' in relative:
                continue
            for owner, field, line in holders(relative, path.read_text(encoding='utf-8', errors='replace')):
                if not _allowed(relative, owner, field):
                    where = 'module scope' if owner is None else owner
                    result.append(f'{relative}:{line}: {where}.{field} holds a servlet exchange object')
    return result


def main():
    found = violations()
    for line in found:
        print(line)
    if found:
        print(f'{len(found)} unreviewed holder(s) of exchange objects: review each per tools/check_exchange_retention.py')
        return 1
    print('exchange retention audit: every holder of a request or response is a reviewed per-exchange object')
    return 0


if __name__ == '__main__':
    sys.exit(main())
