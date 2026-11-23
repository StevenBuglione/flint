"""Where a test finds Flint, in the monorepo and in an extracted repo (ADR-030 repo split; coordinator's decision 3).

A repo's suites live in its own `tests/` (`tests/<repo>/` in the monorepo). The tooling stays in the flint repo, so
`tools/ci.py` runs every repo's suites with two variables:

- `FLINT_ROOT`: the flint checkout, which holds the flint CLI, `tools/` and these helpers;
- `FLINT_WORKSPACE`: the flint.workspace/1 file that pins every repo's checkout.

In the monorepo both default to this checkout. A test then imports these helpers and finds its directories by
package or repo, never by a path relative to its own file:

    sys.path.insert(0, str(Path(os.environ.get('FLINT_ROOT') or Path(__file__).resolve().parents[2]) / 'tests'))
    from flint_testing import FLINT_ROOT, package_dir, repo_dir
"""
import os
import sys
from pathlib import Path

FLINT_ROOT = Path(os.environ.get('FLINT_ROOT') or Path(__file__).resolve().parents[1]).resolve()
sys.path.insert(0, str(FLINT_ROOT / 'tools'))
import workspace as _workspace  # noqa: E402


def _workspace_file():
    named = os.environ.get('FLINT_WORKSPACE')
    if named:
        return named
    fetched = FLINT_ROOT / '.flint' / 'platform' / 'workspace.json'  # a home after the cutover (platform_modules)
    return str(fetched) if fetched.is_file() else None


WORKSPACE = _workspace.Workspace(_workspace_file())


def _renamed():
    import json
    path = FLINT_ROOT / 'policy' / 'renamed-packages.json'
    return json.loads(path.read_text())['renamed'] if path.is_file() else {}


def package_dir(name):
    """A package's, Boot library's, starter's or framework module's directory, in its repo's checkout. A name the
    cutover renamed (policy/renamed-packages.json: starter-web is legacy-starter-web) resolves to its new name."""
    if name not in _workspace.package_repos(FLINT_ROOT):
        name = _renamed().get(name, name)
    return WORKSPACE.package_dir(name, FLINT_ROOT)


def repo_dir(repo, directory):
    """`directory`, a monorepo path such as `tests/framework/integration`, in `repo`'s checkout."""
    return WORKSPACE.locate(repo, directory, FLINT_ROOT)
