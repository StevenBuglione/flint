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

--write rewrites the page; --check (the API gate) fails when the page is stale, or when an adapted entry cites a
rule or deviation that docs/spring/api-mapping.md does not define.
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
SEPARATORS = '.#(),'


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


def render(root):
    text = (root / RULEBOOK).read_text()
    rules, deviations, categories = rulebook(text)
    problems = []
    out = [(root / INTRO).read_text().rstrip('\n'), '']
    summary, adapted, excluded, deferred, reasons = [], {}, {}, {}, {}
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
    page, problems = render(a.root)
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
