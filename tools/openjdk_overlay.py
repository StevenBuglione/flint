#!/usr/bin/env python3
"""Build the source tree that api/upstream/openjdk-21.0.13.json is extracted from.

Some public Java SE types are generated during the JDK build from templates (java/nio/X-Buffer.java.template,
Charset-X-Coder.java.template, the 'exceptions' files): ByteBuffer and the other buffers, CharsetEncoder and
CharsetDecoder, and the java.nio, java.nio.charset and java.nio.channels exceptions. The jdk21u tag archive (pin
'openjdk') has no .java for them, but a JDK build's lib/src.zip does (pin 'temurin-jdk', the same 21.0.13 release).

The overlay is the tag's java/ and javax/ roots of java.base and java.sql (hard links), plus every src.zip file of those
roots that the tag lacks, at its source-tree path. Then:

    python3 tools/openjdk_overlay.py <openjdk cache dir> <temurin-jdk cache dir> <overlay dir>
    flint api extract --source <overlay dir> --project openjdk --tag 21.0.13
"""
import shutil
import sys
import zipfile
from pathlib import Path

MODULES = ('java.base', 'java.sql')
ROOTS = ('java', 'javax')


def build(tag, jdk, overlay):
    tag, jdk, overlay = Path(tag), Path(jdk), Path(overlay)
    zips = sorted(jdk.rglob('lib/src.zip'))
    if not zips:
        raise SystemExit(f'{jdk}: no lib/src.zip; run flint api fetch temurin-jdk')
    if overlay.exists():
        shutil.rmtree(overlay)
    for module in MODULES:
        for root in ROOTS:
            source = tag / 'src' / module / 'share' / 'classes' / root
            if source.is_dir():
                shutil.copytree(source, overlay / 'src' / module / 'share' / 'classes' / root, copy_function=_link)
    added = []
    with zipfile.ZipFile(zips[0]) as archive:
        for name in sorted(archive.namelist()):
            module, _, rest = name.partition('/')
            if module not in MODULES or not rest.endswith('.java') or rest.split('/', 1)[0] not in ROOTS:
                continue
            if any((tag / 'src' / module / platform / 'classes' / rest).exists() for platform in ('share', 'unix')):
                continue
            target = overlay / 'src' / module / 'share' / 'classes' / rest
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(name))
            added.append(name)
    return added


def _link(source, target):
    try:
        Path(target).hardlink_to(source)
    except OSError:
        shutil.copy2(source, target)


if __name__ == '__main__':
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    added = build(*sys.argv[1:])
    print(f'{len(added)} generated sources added from src.zip')
