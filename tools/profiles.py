"""Canonical build profiles shared with the flint CLI (policy/profiles.toml, ADR-018)."""
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / 'policy/profiles.toml'
NAMES = ('dev', 'test', 'release', 'size', 'sanitize')
FIELDS = {'description': str, 'compiler': str, 'compilers': list, 'build_type': str, 'dflags': list,
          'lflags': list, 'compile_server': bool, 'dub_pipeline': bool, 'native_profile': str,
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
        for key in ('compilers', 'dflags', 'lflags'):
            if not all(isinstance(value, str) and value for value in profile[key]):
                raise ValueError(name + '.' + key + ': expected nonempty strings')
        if profile['compiler'] not in ('dmd', 'ldc2') or profile['compiler'] not in profile['compilers']:
            raise ValueError(name + ': compiler must be dmd or ldc2 and listed in compilers')
    return profiles


def dflags(name, path=POLICY):
    return list(load(path)[name]['dflags'])
