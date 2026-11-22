#!/usr/bin/env python3
"""Create a new implementation checkout from this handoff without overwriting files."""
import argparse,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--destination',type=Path,required=True);a=ap.parse_args();dest=a.destination.resolve()
    if dest.exists():raise SystemExit('destination must not already exist: '+str(dest))
    if dest.is_relative_to(ROOT):raise SystemExit('choose a destination outside the handoff tree')
    ignore=shutil.ignore_patterns('__pycache__','*.pyc','.dub','.git','.venv','.tools','.native','.native-sanitized','.ci-dub-home','build','artifacts','*.zip')
    shutil.copytree(ROOT/'scaffold',dest,ignore=ignore)
    shutil.copytree(ROOT/'templates',dest/'examples',ignore=ignore)
    for recipe in (dest/'examples').rglob('dub.sdl'):
        recipe.write_text(recipe.read_text().replace('path="../../scaffold"','path="../.."'))
    shutil.copytree(ROOT,dest/'handoff',ignore=ignore)
    (dest/'AGENTS.md').write_text((ROOT/'AGENTS.md').read_text())
    (dest/'README.md').write_text('# Flint implementation checkout\n\nRead `AGENTS.md` and `handoff/MILESTONES_EXECUTION_PLAN.md`. The initial checkout contains recipes and build policies, not fake implementations. Complete the assigned package before its tests/build can pass. Handoff contracts are documentation/typechecking references and are not on the production import path.\n')
    print(dest)
if __name__=='__main__':main()
