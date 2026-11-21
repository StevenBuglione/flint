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
