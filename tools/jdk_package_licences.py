"""Licence boundaries for OpenJDK ports and the shrinking migration list (owner decision c32da028)."""

import json
import os
import re
from pathlib import Path

from request_allocation_ratchet import git

PENDING = 'policy/jdk-licence-pending.json'
GPL_CLASSPATH = 'GPL-2.0-only WITH Classpath-exception-2.0'
SOURCE_SUFFIXES = {'.d', '.di', '.java', '.c', '.h', '.cc', '.cpp', '.hpp', '.py'}
HEADER = re.compile(r'\s*(?:(?://[^\n]*|/\*.*?\*/|/\+.*?\+/|#[^\n]*)\s*)*', re.S)


def gpl_upstreams(root):
    policy = json.loads((root / 'policy/upstream-licences.json').read_text(encoding='utf-8'))
    return {entry['name'] for entry in policy['projects'] if entry['use'] == 'gpl-ce-module'}


def requires_gpl(name, module, upstreams):
    # The original java aggregate still has a descriptive upstream field.
    upstream = module.get('upstream', '').split('@', 1)[0]
    return name == 'java' or name.startswith('java-') or upstream in upstreams


def pending_names(text):
    document = json.loads(text)
    if document.get('schema') != 1:
        raise ValueError(f'{PENDING}: schema must be 1')
    names = document.get('pending')
    if not isinstance(names, list) or any(not isinstance(name, str) for name in names):
        raise ValueError(f'{PENDING}: expected a list of package names')
    if names != sorted(set(names)):
        raise ValueError(f'{PENDING}: package names must be unique and sorted')
    return set(names)


def pending_at(root, eligible):
    pending = pending_names((root / PENDING).read_text(encoding='utf-8'))
    invalid = pending - eligible
    if invalid:
        raise ValueError(f'{PENDING}: unknown or ineligible packages: {", ".join(sorted(invalid))}')
    if not (root / '.git').exists():
        return pending
    if git(root, 'rev-parse', '--is-shallow-repository').stdout.strip() == 'true':
        raise ValueError(f'{PENDING}: licence ratchet requires full git history')
    commits = git(root, 'log', '--first-parent', '--reverse', '--format=%H', 'HEAD', '--', PENDING).stdout.split()
    versions = []
    for commit in commits:
        shown = git(root, 'show', f'{commit}:{PENDING}', check=False)
        versions.append((commit[:12], pending_names(shown.stdout) if not shown.returncode else set()))
    versions.append(('working tree', pending))
    for (_, previous), (label, current) in zip(versions, versions[1:]):
        added = current - previous
        if added:
            raise ValueError(f'{PENDING}: pending packages added in {label}: {", ".join(sorted(added))}')
    return pending


def package_files(name, base, licence, required, pending):
    """Check package-level files while preserving the existing EPL-only source rule in gates.py."""
    migrated = licence == GPL_CLASSPATH
    if required and not pending and not migrated:
        raise ValueError(f'{name}: DUB licence must be {GPL_CLASSPATH}')
    if migrated and not required:
        raise ValueError(f'{name}: GPL with Classpath Exception requires a gpl-ce-module upstream')
    if migrated and pending:
        raise ValueError(f'{name}: remove the migrated package from {PENDING}')

    licence_file = base / 'LICENSE'
    if (licence == 'EPL-2.0' or migrated) != licence_file.is_file():
        raise ValueError(f'{name}: only EPL-2.0 and GPL-2.0 with Classpath Exception modules carry their own LICENSE')
    if not migrated:
        return

    licence_text = ' '.join(licence_file.read_text(encoding='utf-8').split())
    if 'Version 2, June 1991' not in licence_text or (
            'permission to link this library with independent modules' not in licence_text):
        raise ValueError(f'{name}: LICENSE must include GPL version 2 and the Classpath Exception')
    if not (base / 'NOTICE').is_file():
        raise ValueError(f'{name}: a GPL with Classpath Exception package must carry NOTICE')


def check_headers(base, licence):
    """Check source headers, including tests and tooling. Ignore generated hidden build trees."""
    migrated = licence == GPL_CLASSPATH
    for directory, children, files in os.walk(base):
        children[:] = sorted(child for child in children if not child.startswith('.'))
        for filename in sorted(files):
            path = Path(directory) / filename
            if path.suffix not in SOURCE_SUFFIXES:
                continue
            with path.open(encoding='utf-8', errors='replace') as stream:
                header = HEADER.match(stream.read(8192).lstrip('\ufeff'))[0].lower()
            gpl2 = 'gnu general public license version 2' in header or 'gpl-2.0' in header or (
                'gnu general public license, version 2' in header)
            classpath = any(mark in header for mark in (
                '"classpath" exception', 'classpath exception', 'classpath-exception-2.0'))
            apache = any(mark in header for mark in (
                'spdx-license-identifier: apache-2.0', 'licensed under the apache license',
                'licensed to the apache software foundation'))
            epl_option = licence == 'EPL-2.0' and 'spdx-license-identifier: epl-2.0 or gpl-2.0' in header
            if gpl2 and classpath and not epl_option and (not migrated or apache):
                raise ValueError(f'{path}: GPL with Classpath Exception source requires a matching package licence and no Apache-licensed material')
            if migrated and apache:
                raise ValueError(f'{path}: Apache-licensed source cannot share a GPL with Classpath Exception package')
