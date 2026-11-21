#!/usr/bin/env python3
"""Exercise generated completion scripts using inert local marker fixtures."""

import argparse
import base64
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile


ROOT = "completion fixture"
CHILD = "child ' space"
QUOTED = "--quoted ' `touch FLINT_CLI_BACKTICK` $(touch FLINT_CLI_SUBSHELL) ’"
MARKERS = ("FLINT_CLI_BACKTICK", "FLINT_CLI_SUBSHELL")

BASH_DRIVER = '''
set -eu
source "$1"
name=$2
function_name=$3
complete -p -- "$name" | grep -F "$function_name" >/dev/null
shift 3
COMP_WORDS=("$@")
COMP_CWORD=$(( $# - 1 ))
"$function_name"
if (( ${#COMPREPLY[@]} != 0 )); then
    printf '%s\\0' "${COMPREPLY[@]}"
fi
'''

ZSH_DRIVER = '''
set -eu
_arguments() { state=flint_candidates }
compdef() { [[ $# == 2 ]] }
compadd() { [[ $1 == -- ]]; shift; printf '%s\\0' "$@" }
source "$1"
function_name=$2
shift 2
words=("$@")
CURRENT=$#
"$function_name"
'''


def function_name(script):
    return re.search(r"(?m)^(_flint_cli_[0-9a-f]{16})\(\) \{", script)[1]


def run(args, folder):
    return subprocess.check_output(args, cwd=folder, timeout=5).decode()


def split_nul(data):
    return data.rstrip("\0").split("\0") if data else []


def test_bash(bash, script, folder):
    ident = function_name(script.read_text())
    command = [bash, "--noprofile", "--norc", "-c", BASH_DRIVER, "probe", str(script), ROOT, ident]
    replies = split_nul(run(command + [ROOT, "--quo"], folder))
    assert len(replies) == 1, replies
    assert shlex.split(replies[0]) == [QUOTED], replies
    # Reparse the emitted shell word as Bash would upon command submission.
    # The fixture's two substitutions can only touch markers in this temp dir.
    reread = run([bash, "--noprofile", "--norc", "-c", "printf '%s' " + replies[0]], folder)
    assert reread == QUOTED
    assert split_nul(run(command + [ROOT, CHILD, "--l"], folder)) == ["--leaf"]
    assert "--text" in split_nul(run(command + [ROOT, "--text", CHILD, "--"], folder))
    assert not split_nul(run(command + [ROOT, "--", ""], folder))
    print("bash: literal metadata, escaping on insertion, and selected child context")


def test_zsh(zsh, script, folder):
    ident = function_name(script.read_text())
    command = [zsh, "-f", "-c", ZSH_DRIVER, "probe", str(script), ident]
    assert QUOTED in split_nul(run(command + [ROOT, ""], folder))
    leaf = split_nul(run(command + [ROOT, CHILD, ""], folder))
    assert "--leaf" in leaf and "--text" not in leaf
    print("zsh: registered literal candidates and selected child context")


def inspect_powershell(script):
    content = script.read_text()
    values = {base64.b64decode(item).decode()
              for item in re.findall(r"FromBase64String\('([^']*)'\)", content)}
    assert ROOT in values and QUOTED in values and CHILD in values
    assert all(marker not in content for marker in MARKERS)
    assert "Register-ArgumentCompleter -Native" in content
    assert "CompletionResult" in content
    print("PowerShell: generated metadata round-trips as literal UTF-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scripts", type=Path)
    parser.add_argument("--shell", choices=("all", "bash", "zsh"), default="all")
    args = parser.parse_args()
    scripts = args.scripts.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="flint-cli-shell-") as work:
        if args.shell in ("all", "bash"):
            test_bash(shutil.which("bash"), scripts / "complete.bash", work)
        if args.shell in ("all", "zsh"):
            zsh = shutil.which("zsh")
            if zsh:
                test_zsh(zsh, scripts / "complete.zsh", work)
            elif args.shell == "zsh":
                raise SystemExit("zsh is required for this test")
        if args.shell == "all":
            inspect_powershell(scripts / "complete.ps1")
            expected = Path(__file__).with_name("help.snapshot.txt")
            assert (scripts / "help-completion-fixture.txt").read_bytes() == expected.read_bytes()
            print("Help: output matches the fixed snapshot")
        assert all(not (Path(work) / marker).exists() for marker in MARKERS)


if __name__ == "__main__":
    main()
