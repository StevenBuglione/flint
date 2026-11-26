"""Per-module linked-bytes budgets (policy/budgets.json "module_linked_bytes", Phase 0 binary-size levers).

ADR-019 budgets each of the 37 packages. A module belongs to one of them or to a Spring-layer module of
policy/framework.json (framework/<artifact>), and either kind may be listed in `required_packages`. The Spring port adds framework modules by the thousand, so each module
can also carry its own budget for the bytes it adds to a linked executable:

    "module_linked_bytes": {
      "required_packages": ["engine-web"],
      "modules": {
        "flint.engine.web.router": {
          "fixture": "packages/engine-web/bench/modules/router",
          "baseline": "packages/engine-web/bench/modules/baseline",
          "linked_bytes": 4096
        }
      }
    }

The fixture is a minimal executable that uses the module and the baseline the same executable without it.
tools/measure_builds.py builds both with the release (O3) and size (Oz) profiles and records the larger
difference in loadable section bytes (the allocated sections, not the page-rounded file size) as the module's
`incremental_linked_bytes`, exactly as for packages. tools/gates.py fails a module above its budget or one that grew past the regression ratio against the base commit. Every
module of a package in `required_packages` must have a budget, so a package opts in once and every module
it adds later needs one.
"""
from __future__ import annotations

import json
from pathlib import Path
import re

KEY = 'module_linked_bytes'
MODULE = re.compile(r'flint(\.[a-z_][a-z0-9_]*)+')


def require(value, message):
    if not value:
        raise ValueError(message)


def owners(packages, root):
    """{name: (module, directory)} of the 37 engine packages and the Spring-layer modules of policy/framework.json."""
    result = {name: ((meta['module'],), 'packages/' + name) for name, meta in packages.items()}
    framework = Path(root) / 'policy/framework.json'
    if framework.is_file():
        for name, meta in json.loads(framework.read_text(encoding='utf-8'))['modules'].items():
            require(name not in result, 'framework module name collides with a package: ' + name)
            # "also" lists further package roots of one module (spring-tx: flint.dao and flint.transaction).
            result[name] = (tuple([meta['module']] + meta.get('also', [])), meta['directory'])
    return result


def owner(module, units):
    matches = [n for n, (roots, _) in units.items()
               if any(module == m or module.startswith(m + '.') for m in roots)]
    require(len(matches) <= 1, 'ambiguous module owner ' + module)
    return matches[0] if matches else None


def package_modules(root, directory):
    """The module names of a package's sources."""
    base = Path(root) / directory / 'source'
    names = set()
    for path in sorted(base.rglob('*.d')) if base.is_dir() else []:
        parts = list(path.relative_to(base).with_suffix('').parts)
        if parts[-1] == 'package':
            parts.pop()
        names.add('.'.join(parts))
    return names


def load(budgets, packages, root):
    """The validated module budgets, {module: entry}; any malformed or missing budget fails."""
    policy = budgets.get(KEY)
    require(isinstance(policy, dict) and set(policy) == {'required_packages', 'modules'},
            KEY + ' must hold exactly required_packages and modules')
    required, modules = policy['required_packages'], policy['modules']
    require(isinstance(required, list) and all(isinstance(n, str) for n in required) and len(set(required)) == len(required),
            KEY + '.required_packages must be a list of distinct package names')
    require(isinstance(modules, dict), KEY + '.modules must be an object')
    units = owners(packages, root)
    for name in required:
        require(name in units, KEY + ': unknown required package ' + name)
    for module, entry in modules.items():
        where = KEY + '.' + module
        require(MODULE.fullmatch(module) is not None, where + ': not a Flint module name')
        require(owner(module, units) is not None, where + ': no package owns this module')
        require(isinstance(entry, dict) and set(entry) == {'fixture', 'baseline', 'linked_bytes'},
                where + ': needs exactly fixture, baseline and linked_bytes')
        require(type(entry['linked_bytes']) is int and entry['linked_bytes'] > 0, where + ': linked_bytes must be a positive integer')
        require(entry['fixture'] != entry['baseline'], where + ': fixture and baseline must differ')
        for key in ('fixture', 'baseline'):
            directory = Path(root) / entry[key]
            require(isinstance(entry[key], str) and not Path(entry[key]).is_absolute()
                    and directory.resolve().is_relative_to(Path(root).resolve()), where + '.' + key + ': must stay inside the repository')
            require((directory / 'dub.sdl').is_file() and (directory / 'source/app.d').is_file(),
                    where + '.' + key + ': needs dub.sdl and source/app.d')
    for name in required:
        missing = sorted(package_modules(root, units[name][1]) - set(modules))
        require(not missing, KEY + ': package ' + name + ' requires a budget for every module; missing ' + ', '.join(missing))
    return modules


def check_measured(modules, current, baseline, ratio):
    """Fail a measured module above its budget, or above `ratio` times its base-commit size."""
    measured = current.get('modules')
    require(isinstance(measured, dict) and set(measured) == set(modules), 'module size measurements differ from the module budgets')
    for module, entry in modules.items():
        size = measured[module]['incremental_linked_bytes']
        require(type(size) is int and 0 <= size <= entry['linked_bytes'], module + ': linked-bytes budget exceeded')
        # A module the base commit did not budget has nothing to regress against.
        previous = (baseline or {}).get('modules', {}).get(module)
        if previous is not None:
            require(size <= previous['incremental_linked_bytes'] * ratio, module + ': linked-bytes regression')

