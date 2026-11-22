"""flint package and flint deps audit (Milestone 8, ADR-023): static executables, the scratch OCI image, SBOMs."""
import json
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

from test_flint_cli import ROOT, codes, environment, flint_json, setUpModule  # noqa: F401
from test_flint_native_c import CLANG, CRC, FFI, HEADER

MUSL = (ROOT / '.tools' / 'musl-sysroot-alpine-3.22-x86_64' / 'flint-musl-sysroot.json').is_file() and \
    (ROOT / '.tools' / 'ldc2-1.43.0-alpine-x86_64' / 'lib' / 'libdruntime-ldc.a').is_file()


def docker_available():
    return shutil.which('docker') is not None and subprocess.run(['docker', 'info'], capture_output=True).returncode == 0


def elf_facts(path):
    headers = subprocess.run(['readelf', '-lW', str(path)], capture_output=True, text=True).stdout
    dynamic = subprocess.run(['readelf', '-dW', str(path)], capture_output=True, text=True).stdout
    needed = [line.split('[')[1].rstrip(']') for line in dynamic.splitlines() if '(NEEDED)' in line]
    return headers, needed


@unittest.skipUnless(CLANG.is_file(), 'pinned clang not installed (flint toolchain install)')
class PackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='flint-package-')
        base = Path(cls.temporary.name)
        cls.env = environment(SOURCE_DATE_EPOCH='1700000000')
        status, document = flint_json('new', 'demo', cwd=base, env=cls.env)
        assert status == 0, document
        cls.project = base / 'demo'
        manifest = cls.project / 'flint.toml'
        # flint:os brings ImportC C of its own, which the musl cross build must preprocess against the sysroot.
        manifest.write_text(manifest.read_text().replace('version = "0.1.0"\n', 'version = "0.1.0"\nlicense = "MIT"\n')
                            .replace('"flint:log" = {}\n', '"flint:log" = {}\n"flint:os" = {}\n'))
        (cls.project / 'native').mkdir()
        (cls.project / 'native' / 'crc.c').write_text(CRC)
        (cls.project / 'native' / 'crc.h').write_text(HEADER)
        (cls.project / 'src' / 'demo' / 'ffi').mkdir()
        (cls.project / 'src' / 'demo' / 'ffi' / 'crc.d').write_text(FFI)
        app = cls.project / 'src' / 'demo' / 'app.d'
        app.write_text(app.read_text().replace(
            'import demo.greeting : greet;\n', 'import demo.ffi.crc : crc32;\nimport demo.greeting : greet;\n').replace(
            '    writeln(greet(settings.value.greeting, parsed.options.name));\n',
            '    writeln(greet(settings.value.greeting, parsed.options.name), " crc=", crc32(cast(const(ubyte)[]) "123456789"));\n'))
        status, document = flint_json('lock', cwd=cls.project, env=cls.env)
        assert status == 0, document
        cls.packages = cls.project / '.flint' / 'package'

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def run_flint(self, *arguments):
        return flint_json(*arguments, cwd=self.project, env=self.env)

    def outputs(self, document):
        return {item['kind']: self.project / item['path'] for item in document['outputs']}

    def run_staged(self, archive, top):
        with tempfile.TemporaryDirectory() as directory, tarfile.open(archive) as tar:
            tar.extractall(directory, filter='data')
            return subprocess.run([str(Path(directory) / top / 'bin' / 'demo'), '--name', 'pkg'], cwd=Path(directory) / top,
                                  capture_output=True, text=True)

    def test_1_host_package_links_only_the_c_library_dynamically(self):
        status, document = self.run_flint('package')
        self.assertEqual(status, 0, document['diagnostics'])
        self.assertEqual(document['target'], 'linux-x86_64-glibc')
        self.assertFalse(document['fully_static'])
        self.assertTrue(set(document['needed']) <= {'libc.so.6', 'libm.so.6', 'libpthread.so.0', 'libdl.so.2',
                                                    'librt.so.1', 'libgcc_s.so.1', 'ld-linux-x86-64.so.2'}, document['needed'])
        files = self.outputs(document)
        with tarfile.open(files['archive']) as tar:
            names = tar.getnames()
        self.assertIn('demo-0.1.0/bin/demo', names)
        self.assertIn('demo-0.1.0/config/application.toml', names)
        result = self.run_staged(files['archive'], 'demo-0.1.0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Hello, pkg! crc=3421780262', result.stdout)
        receipt = json.loads(files['receipt'].read_text())
        self.assertEqual(receipt['schema'], 'flint.package/1')

    @unittest.skipUnless(MUSL, 'musl toolchain not installed (flint toolchain install --musl)')
    def test_2_musl_container_and_sboms(self):
        status, document = self.run_flint('package', '--container', '--sbom')
        self.assertEqual(status, 0, document['diagnostics'])
        self.assertEqual(document['target'], 'linux-x86_64-musl')
        self.assertTrue(document['fully_static'])
        files = self.outputs(document)
        headers, needed = elf_facts(files['executable'])
        self.assertNotIn('INTERP', headers)
        self.assertEqual(needed, [])
        self.assertIn('Position-Independent Executable', headers)
        self.assertIn('Hello, pkg! crc=3421780262', self.run_staged(files['archive'], 'demo-0.1.0').stdout)
        spdx = json.loads(files['spdx'].read_text())
        self.assertEqual(spdx['spdxVersion'], 'SPDX-2.3')
        names = {p['name']: p for p in spdx['packages']}
        for name in ('demo', 'flint:os', 'druntime', 'phobos', 'musl', 'native/crc.c'):
            self.assertIn(name, names)
        self.assertEqual(names['demo']['licenseDeclared'], 'MIT')
        self.assertEqual(names['musl']['licenseDeclared'], 'MIT')
        executable_sha = document['outputs'][0]['sha256']
        self.assertEqual(names['demo']['checksums'][0]['checksumValue'], executable_sha)
        described = [r for r in spdx['relationships'] if r['relationshipType'] == 'DESCRIBES']
        self.assertEqual(described[0]['relatedSpdxElement'], names['demo']['SPDXID'])
        cdx = json.loads(files['cyclonedx'].read_text())
        self.assertEqual((cdx['bomFormat'], cdx['specVersion']), ('CycloneDX', '1.6'))
        refs = {c['bom-ref'] for c in cdx['components']}
        for dependency in cdx['dependencies']:
            self.assertTrue(set(dependency['dependsOn']) <= refs, dependency)
        with tarfile.open(files['image']) as tar:
            index = json.loads(tar.extractfile('index.json').read())
            manifest_digest = index['manifests'][0]['digest']
            self.assertEqual(manifest_digest, document['image_digest'])
            manifest = json.loads(tar.extractfile('blobs/sha256/' + manifest_digest.split(':')[1]).read())
            config = json.loads(tar.extractfile('blobs/sha256/' + manifest['config']['digest'].split(':')[1]).read())
        self.assertEqual(config['config']['Entrypoint'], ['/app/demo'])
        self.assertEqual(config['config']['User'], '65532:65532')
        self.assertEqual(len(manifest['layers']), 1)

    @unittest.skipUnless(MUSL, 'musl toolchain not installed (flint toolchain install --musl)')
    def test_3_packages_are_reproducible(self):
        first = self.run_flint('package', '--container', '--sbom')[1]
        second = self.run_flint('package', '--container', '--sbom')[1]
        self.assertEqual([o['sha256'] for o in first['outputs']], [o['sha256'] for o in second['outputs']])

    @unittest.skipUnless(MUSL and docker_available(), 'needs the musl toolchain and a running docker')
    def test_4_the_scratch_image_runs(self):
        status, document = self.run_flint('package', '--container')
        self.assertEqual(status, 0, document['diagnostics'])
        image = self.outputs(document)['image']
        loaded = subprocess.run(['docker', 'load', '-i', str(image)], capture_output=True, text=True)
        self.assertEqual(loaded.returncode, 0, loaded.stderr)
        try:
            ran = subprocess.run(['docker', 'run', '--rm', 'demo:0.1.0', '--name', 'scratch'], capture_output=True,
                                 text=True, timeout=120)
            self.assertEqual(ran.returncode, 0, ran.stderr)
            self.assertIn('Hello, scratch! crc=3421780262', ran.stdout)
        finally:
            subprocess.run(['docker', 'image', 'rm', '-f', 'demo:0.1.0'], capture_output=True)

    def test_5_refusals(self):
        status, document = self.run_flint('package', '--container', '--target', 'linux-x86_64-glibc')
        self.assertEqual((status, codes(document)), (1, ['FLINT-E0710']))
        status, document = self.run_flint('package', '--target', 'windows-x86_64')
        self.assertEqual((status, codes(document)), (2, ['FLINT-E0817']))
        with tempfile.TemporaryDirectory() as directory:
            flint_json('new', 'lib', '--type', 'library', cwd=directory, env=self.env)
            status, document = flint_json('package', cwd=Path(directory) / 'lib', env=self.env)
            self.assertEqual((status, codes(document)), (1, ['FLINT-E0709']))

    def test_6_audit_lists_licences_and_obligations(self):
        status, document = self.run_flint('deps', 'audit')
        self.assertEqual(status, 0, document['diagnostics'])
        components = {c['name']: c for c in document['components']}
        self.assertEqual(components['flint:os']['license'], 'Apache-2.0')
        self.assertEqual(components['glibc']['linkage'], 'dynamic')
        self.assertEqual([o['component'] for o in document['obligations']], ['glibc'])
        self.assertIn('flint.lock matches', document['verified'][0])
        status, document = self.run_flint('deps', 'audit', '--target', 'linux-x86_64-musl')
        self.assertEqual(document['obligations'], [])
        self.assertIn('musl', {c['name'] for c in document['components']})


    @unittest.skipUnless(MUSL, 'musl toolchain not installed (flint toolchain install --musl)')
    def test_7_a_project_under_a_path_with_spaces_packages(self):
        with tempfile.TemporaryDirectory(prefix='flint package ') as directory:
            status, document = flint_json('new', 'spaced', cwd=directory, env=self.env)
            self.assertEqual(status, 0, document['diagnostics'])
            project = Path(directory) / 'spaced'
            # DUB splits DFLAGS at whitespace, so the musl target's ldc2.conf must not live under this path.
            status, document = flint_json('package', '--container', cwd=project, env=self.env)
            self.assertEqual(status, 0, document['diagnostics'])
            self.assertTrue(document['fully_static'])


if __name__ == '__main__':
    unittest.main()
