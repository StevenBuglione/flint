#!/usr/bin/env python3
"""Generate docs/spring/java-differences.md: every place Flint's public API differs from the Java original.

The page is the hand-written front section (api/java-differences-intro.md) followed by lists generated from every
api/*/mapping.json:
- each adapted entry, with its rules or deviations, 'Java -> Flint' and its note;
- each excluded entry, with its category and note;
- deferred elements as counts per Java package, plus the deferred entries that record a reason.

An entry's free-text 'note' and 'reason' fields are where a lane records a behaviour difference a rule ID alone does
not show (for example, that Java's null-argument exceptions are not reproduced); both are rendered.

Elements are classified exactly as `flint api coverage` does: an exact id wins, then the pattern with the longest
literal prefix, then fewer '**', then the longer pattern; '*' stays within one name and '**' crosses everything.

It also renders the Deviations table of docs/spring/api-mapping.md from api/deviations/D-*.json (one file per
deviation: id, deviation, reason), so parallel lanes add deviations without touching the same lines.

--write rewrites the page and the table; --check (the API gate) fails when either is stale, or when an adapted entry
cites a rule or deviation that is not defined.
"""
import argparse
import collections
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = Path('docs/spring/java-differences.md')
INTRO = Path('api/java-differences-intro.md')
RULEBOOK = Path('docs/spring/api-mapping.md')
DEVIATIONS = Path('api/deviations')
DEPENDENCY_BASELINE = Path('api/dependency-baseline.json')
# Java types every port maps by rule rather than by a classified element: primitives, String (R14), Object (R23),
# Class (R4), boxed values (R5), the exception roots (R8, D exceptions), reflection members (D-AOT-MEMBER), and
# java.lang.Enum, Java's 'any enum', which maps to a template parameter constrained to D enums (is(E == enum)).
RULE_MAPPED = {'void', 'boolean', 'byte', 'char', 'short', 'int', 'long', 'float', 'double', 'String', 'Object', 'Class',
               'Integer', 'Long', 'Double', 'Float', 'Boolean', 'Short', 'Byte', 'Character', 'CharSequence', 'Number',
               'Throwable', 'Exception', 'RuntimeException', 'Error', 'Method', 'Constructor', 'Field', 'Member',
               'AccessibleObject', 'Executable', 'Enum'}
BEGIN = '<!-- BEGIN GENERATED deviations: tools/api_differences.py --write from api/deviations/*.json -->'
END = '<!-- END GENERATED deviations -->'
SEPARATORS = '.#(),'
DEVIATION_ID = re.compile(r'^D-[A-Z0-9]+(-[A-Z0-9]+)*$')


def deviation_key(ident):
    """D-1 < D-14 < D-AOT-MEMBER < D-DATA-2 < D-DATA-10: core numbers first, then by area and number."""
    parts = ident[2:].split('-')
    return [(0, int(p), '') if p.isdigit() else (1, 0, p) for p in parts]


def load_deviations(root, problems):
    """The deviation files, sorted; malformed files are reported in `problems`."""
    found = []
    for path in sorted((root / DEVIATIONS).glob('*.json')):
        try:
            item = json.loads(path.read_text())
        except ValueError as failure:
            problems.append(f'{DEVIATIONS / path.name}: {failure}')
            continue
        ident = item.get('id', '')
        if not DEVIATION_ID.match(ident) or path.stem != ident:
            problems.append(f'{DEVIATIONS / path.name}: id must be D-<AREA>-<n> and match the file name')
            continue
        if not item.get('deviation') or not item.get('reason'):
            problems.append(f'{DEVIATIONS / path.name}: needs non-empty deviation and reason')
            continue
        found.append(item)
    return sorted(found, key=lambda i: deviation_key(i['id']))


def with_deviation_table(text, deviations):
    """api-mapping.md with its generated Deviations table replaced; None when the markers are missing."""
    if BEGIN not in text or END not in text:
        return None
    head, rest = text.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    rows = ['| ID | Deviation | Reason |', '| --- | --- | --- |']
    rows += [f"| {d['id']} | {d['deviation']} | {d['reason']} |" for d in deviations]
    return head + BEGIN + '\n' + '\n'.join(rows) + '\n' + END + '\n\n' + tail.lstrip('\n')


def table_rows(text):
    """The generated table's rows by deviation ID."""
    if BEGIN not in text or END not in text:
        return {}
    block = text.split(BEGIN, 1)[1].split(END, 1)[0]
    return {m.group(1): line for line in block.splitlines() if (m := re.match(r'^\| (D-[A-Z0-9-]+) \|', line))}


def table_problems(current, expected):
    """Name each row of the generated table that differs from its file, and how to fix it."""
    have, want = table_rows(current), table_rows(expected)
    problems = []
    for ident in sorted(set(have) | set(want), key=deviation_key):
        source = f'{DEVIATIONS}/{ident}.json'
        if ident not in want:
            problems.append(f'{RULEBOOK}: the Deviations table has a row {ident} with no {source}; add that file '
                            '(the table is generated), then run: python3 tools/api_differences.py --write')
        elif ident not in have:
            problems.append(f'{RULEBOOK}: {source} has no row in the Deviations table; '
                            'run: python3 tools/api_differences.py --write')
        elif have[ident] != want[ident]:
            problems.append(f'{RULEBOOK}: the {ident} row differs from {source}; edit {source}, not the table '
                            '(it is generated), then run: python3 tools/api_differences.py --write')
    return problems or [f'{RULEBOOK}: the Deviations table does not match {DEVIATIONS}/; '
                        'run: python3 tools/api_differences.py --write']


def anchor(heading):
    """GitHub's anchor for a Markdown heading."""
    text = re.sub(r'[^\w\- ]', '', heading.strip().lower())
    return text.replace(' ', '-')


def rulebook(text):
    """The rule anchors (R1 -> anchor), the deviation IDs and the exclusion categories api-mapping.md defines."""
    rules = {m.group(1): anchor(m.group(0)[4:]) for m in re.finditer(r'^### (R\d+): .*$', text, re.M)}
    deviations, categories, section = set(), set(), None
    for line in text.splitlines():
        if line.startswith('## '):
            section = line[3:].strip()
        cell = re.match(r'^\| (`?)([A-Za-z0-9-]+)\1 \|', line)
        if not cell:
            continue
        if section == 'Deviations' and cell.group(2).startswith('D-'):
            deviations.add(cell.group(2))
        elif section == 'Exclusions' and cell.group(1) == '`':
            categories.add(cell.group(2))
    return rules, deviations, categories


def literal_prefix(pattern):
    star = pattern.find('*')
    return len(pattern) if star < 0 else star


def pattern_regex(pattern):
    parts = re.split(r'(\*\*|\*)', pattern)
    body = ''.join('.*' if p == '**' else '[^' + re.escape(SEPARATORS) + ']*' if p == '*' else re.escape(p)
                   for p in parts if p)
    return re.compile('^' + body + '$', re.S)


class Classifier:
    """flint api coverage's precedence, with candidate patterns indexed by literal prefix."""

    def __init__(self, elements):
        self.exact, self.by_prefix = {}, collections.defaultdict(list)
        for key, entry in elements.items():
            n = literal_prefix(key)
            if n == len(key):
                self.exact[key] = (key, entry)
            else:
                rank = (-n, key.count('**'), -len(key), key)
                self.by_prefix[key[:n]].append((rank, pattern_regex(key), key, entry))
        self.lengths = sorted({len(p) for p in self.by_prefix}, reverse=True)

    def classify(self, element):
        if element in self.exact:
            return self.exact[element]
        best = None
        for n in self.lengths:
            if n > len(element):
                continue
            for rank, regex, key, entry in self.by_prefix.get(element[:n], ()):
                if (best is None or rank < best[0]) and regex.match(element):
                    best = (rank, key, entry)
            if best is not None:
                # A longer literal prefix always ranks first, so no shorter prefix can win.
                return best[1], best[2]
        return None


def erase_type(text):
    """A Java type as written, reduced to its simple (or Outer.Inner) name: annotations, type arguments, arrays and
    varargs removed."""
    text = re.sub(r'@[\w.]+(\([^)]*\))?\s*', '', text or '')
    while '<' in text:
        text = re.sub(r'<[^<>]*>', '', text)
    text = text.replace('...', '').replace('[]', '').strip()
    return text.split(' ')[-1] if text else ''


def flint_java_types(root):
    """Type names flint:java* declares in D: a JDK type that exists there is available even before the Java SE
    manifest's classification catches up."""
    names = set()
    for path in (root / 'framework').glob('java*/source/**/*.d'):
        names |= set(re.findall(r'\b(?:class|interface|struct|enum|union|alias)\s+([A-Z]\w*)',
                                path.read_text(errors='replace')))
    return names


def dependency_gaps(root, found=None):
    """Every ported or adapted method or constructor whose Java parameter or return type has no D counterpart, as
    {"<element id> -> <type>": "<repo>: <resolved type id> is <status>"}. A type is available when it is rule-mapped
    (RULE_MAPPED), a type variable, classified ported or adapted, or a JDK type flint:java declares. Without imports a
    simple name can be ambiguous, so an entry fails only when no candidate with that name is available."""
    found = repos(root) if found is None else found
    jdk_types = flint_java_types(root)
    index, classifiers = collections.defaultdict(list), {}
    for repo, (elements, manifests) in found.items():
        classifier = classifiers[repo] = Classifier(elements)
        for _, manifest in manifests:
            for t in manifest['types']:
                match = classifier.classify(t['id'])
                status = 'unclassified' if match is None else match[1]['status']
                if match and status == 'excluded' and match[1].get('category') == 'deferred':
                    status = 'deferred'
                short = t['id'][len(t['package']) + 1:]
                for name in {short, short.split('.')[-1]}:
                    index[name].append((t['id'], t['package'], status))

    def available(name, candidate):
        identifier, package, status = candidate
        return status in ('ported', 'adapted') or (package.startswith(('java.', 'javax.')) and name in jdk_types)

    gaps = {}
    for repo, (elements, manifests) in found.items():
        classifier = classifiers[repo]
        for _, manifest in manifests:
            for t in manifest['types']:
                type_parameters = {p.split(' ')[0] for p in t.get('typeParameters', [])}
                for member in t['members']:
                    if member['kind'] not in ('method', 'constructor'):
                        continue
                    element = t['id'] + '#' + member['signature']
                    match = classifier.classify(element)
                    if match is None or match[1]['status'] not in ('ported', 'adapted'):
                        continue
                    # An adapted entry may name the Java types it deliberately replaces ('substitutes': {Java type:
                    # D type}), as when a deviation swaps java.lang.annotation.Annotation for AOT MergedAnnotation
                    # records; those names are not gaps.
                    substituted = set(match[1].get('substitutes', {})) if match[1]['status'] == 'adapted' else set()
                    signature = member['signature']
                    written = [p for p in signature[signature.index('(') + 1:-1].split(',') if p]
                    written += [member['type']] if member.get('type') else []
                    for raw in written:
                        name = erase_type(raw)
                        if (not name or name in RULE_MAPPED or name in type_parameters or name in substituted
                                or re.fullmatch(r'[A-Z][0-9A-Z]?', name)):
                            continue
                        candidates = index.get(name, [])
                        if not candidates or any(available(name, c) for c in candidates):
                            continue
                        best = ([c for c in candidates if c[1] == t['package']] or candidates)[0]
                        gaps[f'{element} -> {name}'] = f'{repo}: {best[0]} is {best[2]}'
    return gaps


def dependency_problems(root, write=False):
    """The ratchet over dependency_gaps: api/dependency-baseline.json lists the gaps recorded when the check landed
    (coordinator, 2026-11-26). A gap not listed fails ('mark it deferred, or port <type> first'); a listed gap that is
    resolved must leave the list, which --write does. --write never adds an entry."""
    path = root / DEPENDENCY_BASELINE
    if not path.is_file():
        return []
    baseline = json.loads(path.read_text())
    allowed = baseline.get('gaps', {})
    gaps = dependency_gaps(root)
    problems = []
    for key in sorted(gaps):
        if key not in allowed:
            element, _, name = key.partition(' -> ')
            problems.append(f'{element} is ported or adapted, but its type {name} has no D counterpart '
                            f'({gaps[key]}): mark it deferred, or port {name} first')
    resolved = sorted(k for k in allowed if k not in gaps)
    if resolved and write:
        baseline['gaps'] = {k: v for k, v in allowed.items() if k in gaps}
        path.write_text(json.dumps(baseline, indent=1, sort_keys=True) + '\n')
    elif resolved:
        problems.append(f'{len(resolved)} gaps in {DEPENDENCY_BASELINE} are resolved; shrink it: '
                        'python3 tools/api_differences.py --write')
    return problems


def repos(root):
    """Each repo's mapping elements and the manifests of the upstreams it classifies."""
    pins = json.loads((root / 'api' / 'upstreams.json').read_text())['upstreams']
    found = {}
    for path in sorted((root / 'api').glob('*/mapping.json')):
        repo = path.parent.name
        mapping = json.loads(path.read_text())
        manifests = []
        for key in mapping.get('upstream', []):
            project, _, version = key.partition('@')
            pin = next((p for p in pins if p['project'] == project and p['version'] == version), None)
            manifest = root / 'api' / 'upstream' / f'{project}-{version}.json'
            if pin and pin.get('api', True) and manifest.is_file():
                manifests.append((key, json.loads(manifest.read_text())))
        found[repo] = (mapping['elements'], manifests)
    return found


def elements_of(manifest):
    for t in manifest['types']:
        yield t['id'], t
        for m in t['members']:
            yield t['id'] + '#' + m['signature'], t


def package_of(key, packages):
    """The Java package an entry belongs to: its type's package, or, for a pattern, its literal prefix."""
    type_id = key.split('#', 1)[0]
    literal = type_id[:literal_prefix(type_id)].rstrip('.')
    for candidate in (type_id, literal):
        if candidate in packages:
            return packages[candidate]
    head = literal
    while head and head not in packages.values():
        head = head.rpartition('.')[0]
    return head or literal or '(root)'


def cell(text):
    return text.replace('|', '\\|').replace('\n', ' ')


def note_of(entry):
    """The entry's free-text note and reason, joined."""
    return ' '.join(cell(str(entry[k])) for k in ('note', 'reason') if entry.get(k))


def render(root, problems=None):
    problems = [] if problems is None else problems
    text = (root / RULEBOOK).read_text()
    rules, table_deviations, categories = rulebook(text)
    files = load_deviations(root, problems)
    deviations = {d['id'] for d in files} if (root / DEVIATIONS).is_dir() else table_deviations
    out = [(root / INTRO).read_text().rstrip('\n'), '']
    summary, adapted, excluded, deferred, reasons, gaps = [], {}, {}, {}, {}, {}
    for repo, (elements, manifests) in repos(root).items():
        classifier = Classifier(elements)
        packages, hits = {}, collections.Counter()
        counts = collections.defaultdict(collections.Counter)
        defer = collections.defaultdict(collections.Counter)
        for key, manifest in manifests:
            for element, t in elements_of(manifest):
                packages[t['id']] = t['package']
                found = classifier.classify(element)
                if found is None:
                    status = 'unclassified'
                else:
                    match, entry = found
                    hits[match] += 1
                    status = entry['status']
                    if status == 'excluded' and entry.get('category') == 'deferred':
                        status = 'deferred'
                        defer[t['package']]['phase ' + str(entry.get('phase', '?'))] += 1
                counts[key][status] += 1
        for key, c in counts.items():
            summary.append((repo, key, c))
        for match, entry in elements.items():
            status = entry.get('status')
            if status == 'ported' and note_of(entry):
                gaps.setdefault(repo, []).append((package_of(match, packages), match, entry, hits[match]))
            if status == 'adapted':
                cited = entry.get('rules', [])
                for rule in cited:
                    if rule not in rules and rule not in deviations:
                        problems.append(f'api/{repo}/mapping.json: {match} cites {rule}, which '
                                        f'{RULEBOOK} does not define')
                if not cited:
                    problems.append(f'api/{repo}/mapping.json: adapted {match} cites no rule or deviation')
                adapted.setdefault(repo, []).append((package_of(match, packages), match, entry, hits[match]))
            elif status == 'excluded' and entry.get('category') == 'deferred' and note_of(entry):
                reasons.setdefault(repo, []).append((package_of(match, packages), match, entry, hits[match]))
            elif status == 'excluded' and entry.get('category') != 'deferred':
                category = entry.get('category', '')
                if category not in categories:
                    problems.append(f'api/{repo}/mapping.json: {match} names category {category!r}, which '
                                    f'{RULEBOOK} does not define')
                excluded.setdefault(repo, []).append((package_of(match, packages), match, entry, hits[match]))
        deferred[repo] = defer

    def link_rule(rule):
        if rule in rules:
            return f'[{rule}](api-mapping.md#{rules[rule]})'
        if rule in deviations:
            return f'[{rule}](api-mapping.md#deviations)'
        return rule

    def scope(match, hit):
        return '' if literal_prefix(match) == len(match) else f' ({hit} elements)'

    out += ['## Summary', '', 'Element counts per upstream, as `flint api coverage` classifies them.', '',
            '| Repo | Upstream | Ported | Adapted | Excluded | Not yet ported |', '| --- | --- | ---: | ---: | ---: | ---: |']
    for repo, key, c in summary:
        out.append(f"| {repo} | {key} | {c['ported']:,} | {c['adapted']:,} | {c['excluded']:,} | {c['deferred']:,} |")
    if gaps:
        out += ['', '## Known gaps', '',
                'These elements keep Spring\'s signature, but their behaviour is not complete yet; the note says what '
                'differs. Each note is removed when the gap closes.', '', '| Repo | Java | Flint | Note |',
                '| --- | --- | --- | --- |']
        for repo in sorted(gaps):
            for _, match, entry, hit in sorted(gaps[repo], key=lambda r: r[1]):
                out.append(f"| {repo} | `{cell(match)}`{scope(match, hit)} | `{cell(entry.get('d', ''))}` "
                           f"| {note_of(entry)} |")
    out += ['', '## Adapted elements', '',
            'Each element below keeps its Spring meaning but changes shape in D, by the rule or deviation shown.', '']
    for repo in sorted(adapted):
        out += [f'### {repo}', '']
        for package, rows in groupby(adapted[repo]):
            out += [f'#### {package}', '', '| Java | Flint | Rules | Note |', '| --- | --- | --- | --- |']
            for _, match, entry, hit in rows:
                rules_cell = ', '.join(link_rule(r) for r in entry.get('rules', []))
                out.append(f"| `{cell(match)}`{scope(match, hit)} | `{cell(entry.get('d', ''))}` | {rules_cell} "
                           f"| {note_of(entry)} |")
            out.append('')
    out += ['## Excluded elements', '',
            'These Java elements have no Flint counterpart, for the reason the category gives '
            '([categories](api-mapping.md#exclusions)).', '']
    for repo in sorted(excluded):
        out += [f'### {repo}', '']
        for package, rows in groupby(excluded[repo]):
            out += [f'#### {package}', '', '| Java | Reason | Note |', '| --- | --- | --- |']
            for _, match, entry, hit in rows:
                out.append(f"| `{cell(match)}`{scope(match, hit)} | `{entry.get('category', '')}` | {note_of(entry)} |")
            out.append('')
    out += ['## Not yet ported', '',
            'Deferred elements, counted per Java package. Each is planned for the phase shown and is classified '
            'exactly once it is ported.', '']
    for repo in sorted(deferred):
        if not deferred[repo]:
            continue
        out += [f'### {repo}', '', '| Java package | Phase 2 | Phase 3 |', '| --- | ---: | ---: |']
        for package in sorted(deferred[repo]):
            c = deferred[repo][package]
            out.append(f"| {package} | {c['phase 2']:,} | {c['phase 3']:,} |")
        out.append('')
    if reasons:
        out += ['### Deferred entries with a recorded reason', '',
                'Most deferred elements simply wait for their lane. These record why, or what they wait on.', '',
                '| Repo | Java | Phase | Reason |', '| --- | --- | --- | --- |']
        for repo in sorted(reasons):
            for _, match, entry, hit in sorted(reasons[repo], key=lambda r: r[1]):
                out.append(f"| {repo} | `{cell(match)}`{scope(match, hit)} | {entry.get('phase', '')} | {note_of(entry)} |")
        out.append('')
    header = ('<!-- GENERATED by tools/api_differences.py from api/*/mapping.json and api/java-differences-intro.md. '
              'Do not edit; run: python3 tools/api_differences.py --write -->')
    return header + '\n' + '\n'.join(out).rstrip('\n') + '\n', problems


def groupby(rows):
    grouped = collections.defaultdict(list)
    for row in rows:
        grouped[row[0]].append(row)
    for package in sorted(grouped):
        yield package, sorted(grouped[package], key=lambda r: r[1])


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = p.add_mutually_exclusive_group(required=True)
    mode.add_argument('--write', action='store_true', help='rewrite docs/spring/java-differences.md')
    mode.add_argument('--check', action='store_true', help='fail when the page is stale or a citation is unknown')
    p.add_argument('--root', type=Path, default=ROOT)
    a = p.parse_args(argv)
    problems = []
    rulebook_path = a.root / RULEBOOK
    if (a.root / DEVIATIONS).is_dir():
        current = rulebook_path.read_text()
        expected = with_deviation_table(current, load_deviations(a.root, []))
        if expected is None:
            problems.append(f'{RULEBOOK} lacks the generated deviations markers')
        elif a.write and expected != current:
            rulebook_path.write_text(expected)
        elif not a.write and expected != current:
            problems += table_problems(current, expected)
    page, problems = render(a.root, problems)
    problems += dependency_problems(a.root, write=a.write)
    target = a.root / OUTPUT
    if a.write:
        target.write_text(page)
    elif not target.is_file() or target.read_text() != page:
        problems.append(f'{OUTPUT} does not match the mappings; run: python3 tools/api_differences.py --write')
    for problem in problems:
        print('api differences: ' + problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
