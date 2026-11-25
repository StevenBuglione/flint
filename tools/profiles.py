"""Canonical build profiles shared with the flint CLI (policy/profiles.toml, ADR-018)."""
import os
import platform
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / 'policy/profiles.toml'
NAMES = ('dev', 'test', 'release', 'size', 'sanitize')
FIELDS = {'description': str, 'compiler': str, 'compilers': list, 'build_type': str, 'dflags': list,
          'lflags': list, 'glibc_lflags': list, 'elf_lflags': list, 'compile_server': bool, 'dub_pipeline': bool, 'native_profile': str,
          'native_sanitize': str}


def load(path=POLICY):
    """Return {name: profile} after checking the closed schema flint also enforces."""
    document = tomllib.loads(Path(path).read_text())
    if set(document) != {'profile'}:
        raise ValueError('profiles policy has unknown top-level keys: ' + ', '.join(sorted(set(document) - {'profile'})))
    profiles = document['profile']
    if set(profiles) != set(NAMES):
        raise ValueError('profiles policy must define exactly: ' + ', '.join(NAMES))
    for name, profile in profiles.items():
        if set(profile) != set(FIELDS):
            raise ValueError(name + ': profile keys differ from the policy schema')
        for key, kind in FIELDS.items():
            if not isinstance(profile[key], kind):
                raise ValueError(name + '.' + key + ': expected ' + kind.__name__)
        for key in ('compilers', 'dflags', 'lflags', 'glibc_lflags', 'elf_lflags'):
            if not all(isinstance(value, str) and value for value in profile[key]):
                raise ValueError(name + '.' + key + ': expected nonempty strings')
        if profile['compiler'] not in ('dmd', 'ldc2') or profile['compiler'] not in profile['compilers']:
            raise ValueError(name + ': compiler must be dmd or ldc2 and listed in compilers')
    return profiles


def dflags(name, path=POLICY):
    return list(load(path)[name]['dflags'])


def glibc_host():
    """This host builds Linux glibc position-independent executables natively (flint's hostTarget)."""
    if not sys.platform.startswith('linux'):
        return False
    machine = platform.machine()
    return not os.path.exists('/lib/ld-musl-' + ('aarch64' if machine in ('aarch64', 'arm64') else machine) + '.so.1')


def link_dflags(name, path=POLICY, glibc=None, elf=None):
    """The profile's linker flags as -L compiler flags, with glibc_lflags on a glibc host and elf_lflags on any Linux
    host, as flint builds the host's native executable."""
    profile = load(path)[name]
    flags = list(profile['lflags'])
    if glibc_host() if glibc is None else glibc:
        flags += profile['glibc_lflags']
    if sys.platform.startswith('linux') if elf is None else elf:
        flags += profile['elf_lflags']
    return ['-L' + flag for flag in flags]
