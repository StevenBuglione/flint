"""Conservative lexer for policy checks, not a replacement for the D compiler."""
from dataclasses import dataclass
import re

@dataclass(frozen=True)
class Token:
    value: str
    offset: int
    line: int


def tokens(source):
    i, n, line = 0, len(source), 1
    while i < n:
        start, ln, c = i, line, source[i]
        if c.isspace():
            line += c == '\n'; i += 1; continue
        if source.startswith('//', i):
            j = source.find('\n', i); i = n if j < 0 else j; continue
        if source.startswith('/*', i):
            j = source.find('*/', i + 2)
            if j < 0: raise ValueError('unterminated block comment')
            line += source[i:j+2].count('\n'); i = j+2; continue
        if source.startswith('/+', i):
            depth = 1; i += 2
            while i < n and depth:
                if source.startswith('/+', i): depth += 1; i += 2
                elif source.startswith('+/', i): depth -= 1; i += 2
                else: line += source[i] == '\n'; i += 1
            if depth: raise ValueError('unterminated nested comment')
            continue
        # Token strings are allowed only inside approved generators. Reject here so
        # unusual string syntax cannot hide a policy violation from this lexer.
        if source.startswith('q"', i) or source.startswith('q{', i):
            raise ValueError('use checked generator files; token strings require AST review')
        if c in ['"', "'", '`'] or (c in 'rx' and i+1<n and source[i+1]=='"'):
            raw = c in 'rx`'; quote = source[i+1] if c in 'rx' else c
            i += 2 if c in 'rx' else 1
            while i < n:
                ch = source[i]; line += ch == '\n'; i += 1
                if ch == quote: break
                if ch == '\\' and not raw and i<n: line += source[i]=='\n'; i += 1
            else: raise ValueError('unterminated literal')
            yield Token('<literal>', start, ln); continue
        m = re.match(r'[A-Za-z_][A-Za-z_0-9]*|[0-9]+', source[i:])
        if m: value=m.group(); i += len(value)
        else: value=c; i += 1
        yield Token(value,start,ln)


def imported_modules(ts):
    out=[]; vals=[t.value for t in ts]
    for i,v in enumerate(vals):
        if v != 'import' or i+1>=len(vals) or vals[i+1]=='(': continue
        j=i+1; clause=[]
        while j<len(vals) and vals[j]!=';': clause.append(vals[j]); j+=1
        if j==len(vals): raise ValueError('unterminated import')
        if ':' in clause: clause=clause[:clause.index(':')]
        groups=[]; group=[]
        for x in clause+[',']:
            if x==',': groups.append(group);group=[]
            else:group.append(x)
        for g in groups:
            if '=' in g:g=g[g.index('=')+1:]
            mod=''.join(g)
            if not re.fullmatch(r'[A-Za-z_]\w*(\.[A-Za-z_]\w*)*',mod):raise ValueError('unsupported import declaration '+mod)
            out.append(mod)
    return out


def declared_module(ts):
    vals = [t.value for t in ts]
    if not vals or vals[0] != 'module':
        raise ValueError('canonical D modules require an explicit module declaration first')
    try:
        end = vals.index(';', 1)
    except ValueError as exc:
        raise ValueError('unterminated module declaration') from exc
    name = ''.join(vals[1:end])
    if not re.fullmatch(r'[A-Za-z_]\w*(\.[A-Za-z_]\w*)*', name):
        raise ValueError('invalid module name')
    return name


def module_default(ts):
    """Return the first module default before any non-import declaration.

    A nested @safe: or a late declaration cannot satisfy this policy.
    """
    vals = [t.value for t in ts]
    declared_module(ts)
    index = vals.index(';') + 1
    while index < len(vals):
        if vals[index:index + 3] in (['@', 'safe', ':'], ['@', 'system', ':'], ['@', 'trusted', ':']):
            return vals[index + 1]
        look = index
        while look < len(vals) and vals[look] in ('public', 'private', 'package', 'protected', 'static'):
            look += 1
        if look < len(vals) and vals[look] == 'import' and look + 1 < len(vals) and vals[look + 1] != '(':
            try:
                index = vals.index(';', look) + 1
            except ValueError as exc:
                raise ValueError('unterminated module import') from exc
            continue
        return None
    return None


def has_string_mixin(ts):
    vals = [t.value for t in ts]
    return any(vals[i:i + 2] == ['mixin', '('] for i in range(len(vals) - 1))


def compiler_dependency_edges(text):
    """Read DMD -deps output; reject records we cannot interpret."""
    pattern = re.compile(r'^([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s+\(.*?\)\s*:\s*[^:]+\s*:\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s+\(')
    edges = []
    for line in text.splitlines():
        if not line.strip():
            continue
        match = pattern.match(line)
        if not match:
            raise ValueError('unrecognized DMD dependency record: ' + line[:160])
        edges.append(match.groups())
    return edges


# Attribute words that may open a block or label whose declarations stay at module scope.
_SCOPE_ATTRIBUTES = {'public', 'private', 'package', 'protected', 'export', 'extern', 'align', 'deprecated',
                     'static', 'nothrow', 'pure', 'override', 'final', 'abstract', 'version', 'debug', 'else',
                     'if', 'foreach', 'shared', '__gshared', 'immutable', 'const', 'synchronized', 'auto', 'ref'}
# Storage classes that make a module-scope variable process-global or immutable instead of thread-local.
_GLOBAL_STORAGE = {'shared', '__gshared', 'immutable', 'const', 'enum'}
_NON_VARIABLES = {'import', 'module', 'alias', 'struct', 'class', 'union', 'interface', 'template', 'mixin',
                  'unittest', 'invariant', 'this', '~', 'assert', 'version', 'debug'}
_TRAILING_FUNCTION = {')', 'nothrow', 'pure', 'nogc', 'safe', 'trusted', 'system', 'property', 'const', 'scope',
                      'return', 'inout', 'immutable', 'shared', 'live'}


def _skip_group(vals, i, opening, closing):
    """Index just past the group that opens at vals[i]."""
    depth = 0
    while i < len(vals):
        depth += (vals[i] == opening) - (vals[i] == closing)
        i += 1
        if depth == 0:
            return i
    raise ValueError('unbalanced ' + opening)


def _attributes(vals):
    """Split leading attributes from a declaration. Returns (global storage seen, remaining tokens, attribute-only)."""
    i, storage = 0, False
    while i < len(vals):
        v = vals[i]
        following = vals[i + 1] if i + 1 < len(vals) else None
        if v == '@':
            i += 2
            if i < len(vals) and vals[i] == '(':
                i = _skip_group(vals, i, '(', ')')
            elif i - 1 < len(vals) and vals[i - 1] == '(':
                i = _skip_group(vals, i - 1, '(', ')')
            continue
        if v in _GLOBAL_STORAGE and following != '(':
            storage = True
            i += 1
            continue
        if v in ('version', 'debug') and following == '=':
            break
        if v in _SCOPE_ATTRIBUTES and v not in ('shared', 'immutable', 'const'):
            i += 1
            if i < len(vals) and vals[i] == '(':
                i = _skip_group(vals, i, '(', ')')
            continue
        break
    return storage, vals[i:], i == len(vals)


def _has_top_level(vals, token):
    depth = 0
    for v in vals:
        depth += (v in '([') - (v in ')]')
        if depth == 0 and v == token:
            return True
    return False


def module_thread_locals(ts):
    """Module-scope variables that D makes thread-local and mutable: no shared, __gshared, immutable, const or
    enum storage. Declarations inside attribute, version and static-if blocks count as module scope; function,
    aggregate and template bodies do not. Returns (name, line) pairs."""
    vals = [t.value for t in ts]
    lines = [t.line for t in ts]
    found = []
    # Each open transparent block records whether a storage class on it already makes its contents global.
    blocks = []
    start, i = 0, 0
    declared_module(ts)
    labelled = [False]

    def classify(begin, end):
        storage, rest, _ = _attributes(vals[begin:end])
        if storage or any(blocks) or labelled[-1] or not rest or rest[0] in _NON_VARIABLES:
            return
        head, depth = [], 0
        for v in rest:
            depth += (v in '([') - (v in ')]')
            if depth == 0 and v == '=':
                break
            head.append(v)
        # A single name after stripped attributes is an inferred declaration such as `auto cache = [1];`.
        inferred = len(head) == 1 and len(rest) > 1 and len(rest) < end - begin
        if (len(head) < 2 and not inferred) or head[-1] in _TRAILING_FUNCTION \
                or not re.fullmatch(r'[A-Za-z_]\w*', head[-1]):
            return
        # const(T) name, immutable(T) name and shared(T) name qualify the variable itself; a pointer or slice
        # suffix after the group leaves the variable mutable and thread-local.
        if head[0] in ('const', 'immutable', 'shared') and head[1] == '(' \
                and _skip_group(head, 1, '(', ')') == len(head) - 1:
            return
        offset = end - len(rest) + len(head) - 1
        found.append((head[-1], lines[offset]))

    while i < len(vals):
        v = vals[i]
        if v in ('(', '['):
            i = _skip_group(vals, i, v, ')' if v == '(' else ']')
            continue
        if v == ';':
            classify(start, i)
            i += 1
            start = i
            continue
        if v == ':' and _attributes(vals[start:i])[2] and i > start:
            if _attributes(vals[start:i])[0]:
                labelled[-1] = True
            i += 1
            start = i
            continue
        if v == '{':
            storage, _, only_attributes = _attributes(vals[start:i])
            if _has_top_level(vals[start:i], '='):
                i = _skip_group(vals, i, '{', '}')
                continue
            if only_attributes:
                blocks.append(storage)
                labelled.append(labelled[-1])
                i += 1
                start = i
                continue
            i = _skip_group(vals, i, '{', '}')
            start = i
            continue
        if v == '}':
            if not blocks:
                raise ValueError('unbalanced }')
            blocks.pop()
            labelled.pop()
            i += 1
            start = i
            continue
        i += 1
    return found
