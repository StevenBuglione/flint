"""What a server's memory is made of, from /proc/<pid>/smaps: totals, the largest mappings by resident size, and the
anonymous mappings bucketed by size (druntime's GC pools are anonymous mappings of their pool size, so a 1 MiB or a
4 MiB pool shows as its own bucket). Diagnostic only (Astra's RSS review, 41053ce3: what grows during the fixed-rate
phase, for Flint and for Go)."""
from __future__ import annotations

import re
from pathlib import Path

HEADER = re.compile(r'^([0-9a-f]+)-([0-9a-f]+) (\S+) \S+ \S+ \d+\s*(.*)$')
FIELDS = ('Rss', 'Pss', 'Anonymous', 'Private_Dirty', 'Swap')


def parse(text):
    """[(name, size_kb, {field: kb})] for every mapping."""
    mappings, current = [], None
    for line in text.splitlines():
        match = HEADER.match(line)
        if match:
            start, end, _, name = match.groups()
            current = (name.strip() or '[anon]', (int(end, 16) - int(start, 16)) // 1024, {})
            mappings.append(current)
        elif current and ':' in line:
            key, _, value = line.partition(':')
            if key in FIELDS:
                current[2][key] = int(value.split()[0])
    return mappings


def summarize(mappings, top=12):
    totals = {key: sum(m[2].get(key, 0) for m in mappings) for key in FIELDS}
    groups = {}
    for name, _, fields in mappings:
        row = groups.setdefault(name, {key: 0 for key in FIELDS} | {'mappings': 0})
        row['mappings'] += 1
        for key in FIELDS:
            row[key] += fields.get(key, 0)
    anon = {}
    for name, size, fields in mappings:
        if name == '[anon]':
            bucket = anon.setdefault(str(size), {'mappings': 0, 'Rss': 0, 'Anonymous': 0})
            bucket['mappings'] += 1
            bucket['Rss'] += fields.get('Rss', 0)
            bucket['Anonymous'] += fields.get('Anonymous', 0)
    return {'totals_kb': totals,
            'largest_kb': dict(sorted(groups.items(), key=lambda kv: -kv[1]['Rss'])[:top]),
            'anon_by_size_kb': dict(sorted(anon.items(), key=lambda kv: -kv[1]['Rss']))}


def snapshot(pid):
    try:
        return summarize(parse(Path(f'/proc/{pid}/smaps').read_text()))
    except OSError as exc:
        return {'error': str(exc)}
