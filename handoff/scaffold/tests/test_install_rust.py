import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

TOOLS=Path(__file__).resolve().parents[1]/'tools'
spec=importlib.util.spec_from_file_location('install_rust',TOOLS/'install_rust.py')
rust=importlib.util.module_from_spec(spec);spec.loader.exec_module(rust)

class RustProvisioningTests(unittest.TestCase):
    def test_six_native_hosts_have_immutable_bootstrap_and_manifest_pins(self):
        lock=json.loads((TOOLS.parent/'policy/toolchains.json').read_text())
        self.assertEqual(len(rust.TRIPLES),6)
        self.assertRegex(lock['rust']['manifest_sha256'],r'^[a-f0-9]{64}$')
        for triple in rust.TRIPLES.values():
            asset=lock['rust']['bootstrap'][triple]
            self.assertTrue(asset['url'].startswith('https://static.rust-lang.org/rustup/archive/'+lock['versions']['rustup']+'/'+triple+'/'))
            self.assertRegex(asset['sha256'],r'^[a-f0-9]{64}$')
            self.assertTrue(lock['rust']['hosts'][triple]['available'])

    def test_build_environment_replaces_toolchain_overrides_without_changing_home(self):
        with tempfile.TemporaryDirectory() as temporary,patch.dict(os.environ,{
            'HOME':'/unchanged','RUSTUP_TOOLCHAIN':'nightly','CARGO_HOME':'/external',
            'RUSTC_WRAPPER':'unreviewed-wrapper','RUSTFLAGS':'--cfg unexpected','PATH':'/usr/bin'},clear=True):
            env=rust.environment(Path(temporary),'1.97.0')
            self.assertEqual(env['HOME'],'/unchanged')
            self.assertEqual(env['RUSTUP_TOOLCHAIN'],'1.97.0')
            self.assertEqual(env['CARGO_HOME'],str(Path(temporary).resolve()/'cargo'))
            self.assertNotIn('RUSTC_WRAPPER',env);self.assertNotIn('RUSTFLAGS',env)
            self.assertEqual(os.environ['RUSTUP_TOOLCHAIN'],'nightly')

    def test_checksum_failure_never_installs_downloaded_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination=Path(temporary)/'rustup-init'
            with patch.object(rust.urllib.request,'urlopen',return_value=io.BytesIO(b'corrupt bootstrap')):
                with self.assertRaisesRegex(ValueError,'checksum mismatch'):
                    rust.download('https://static.rust-lang.org/rustup/archive/test','0'*64,destination)
            self.assertFalse(destination.exists());self.assertFalse(destination.with_suffix('.part').exists())
            valid=b'verified bytes';expected=hashlib.sha256(valid).hexdigest()
            with patch.object(rust.urllib.request,'urlopen',return_value=io.BytesIO(valid)):
                rust.download('https://static.rust-lang.org/rustup/archive/test',expected,destination)
            self.assertEqual(destination.read_bytes(),valid)

    def test_unapproved_origin_is_rejected_before_network_access(self):
        with tempfile.TemporaryDirectory() as temporary,patch.object(rust.urllib.request,'urlopen',side_effect=AssertionError('network access')):
            with self.assertRaisesRegex(ValueError,'official distribution origin'):
                rust.download('https://unapproved.invalid/rustup-init','0'*64,Path(temporary)/'rustup-init')

if __name__=='__main__':unittest.main()
