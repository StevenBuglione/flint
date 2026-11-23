import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

TOOLS=Path(__file__).resolve().parents[1]/'tools'
def load(name):
    spec=importlib.util.spec_from_file_location(name,TOOLS/(name+'.py'))
    module=importlib.util.module_from_spec(spec)
    with patch.object(sys,'path',[str(TOOLS),*sys.path]):spec.loader.exec_module(module)
    return module
ci=load('ci')
configure=load('configure_github')
native_build=load('native_build')

class CiBoundaryTests(unittest.TestCase):
    def event(self,kind,payload,**environment):
        with tempfile.TemporaryDirectory() as temporary:
            path=Path(temporary)/'event.json';path.write_text(json.dumps(payload), encoding='utf-8', newline='\n')
            env={'GITHUB_EVENT_PATH':str(path),'GITHUB_EVENT_NAME':kind,**environment}
            with patch.dict(os.environ,env,clear=True),contextlib.redirect_stdout(io.StringIO()) as output:
                ci.refs(None)
                return json.loads(output.getvalue())

    def test_pr_uses_the_tested_merge_tree(self):
        base='1'*40;head='2'*40;merge='3'*40
        result=self.event('pull_request',{'pull_request':{'base':{'sha':base},'head':{'sha':head}}},GITHUB_SHA=merge)
        self.assertEqual(result['candidate'],merge)
        self.assertEqual(result['roles'],['base','candidate'])

    def test_first_push_does_not_invent_a_baseline(self):
        with self.assertRaisesRegex(ValueError,'initial baseline'):
            self.event('push',{'before':'0'*40,'after':'1'*40})

    def test_same_commit_cannot_be_its_regression_baseline(self):
        with self.assertRaisesRegex(ValueError,'must differ'):
            self.event('push',{'before':'1'*40,'after':'1'*40})

    def test_baseline_dispatch_requires_protection_and_default_branch(self):
        event={'inputs':{'mode':'baseline'},'repository':{'default_branch':'main'}}
        with patch.object(ci,'baseline_environment') as protection:
            result=self.event('workflow_dispatch',event,GITHUB_SHA='3'*40,GITHUB_REF='refs/heads/main')
            protection.assert_called_once()
            self.assertEqual((result['base'],result['roles']),('', ['candidate']))
        with self.assertRaisesRegex(ValueError,'default branch'):
            self.event('workflow_dispatch',event,GITHUB_SHA='3'*40,GITHUB_REF='refs/heads/feature')

    def test_missing_sources_fail_before_any_runtime_claim(self):
        with tempfile.TemporaryDirectory() as temporary,patch.object(ci,'ROOT',Path(temporary)):
            with self.assertRaisesRegex(ValueError,'implementation milestone incomplete'):
                ci.implementation_required()

    def test_plain_sanitizer_build_explicitly_enables_unittests(self):
        calls=[]
        class Recorder:
            plan=True
            def run(self,command,**kwargs):calls.append((command,kwargs))
        ci.run_tests(Recorder(),'ldc2',sanitize=True)
        self.assertEqual(len(calls),37)
        for command,kwargs in calls:
            self.assertIn('--build=plain',command)
            self.assertIn('-unittest',kwargs['env']['DFLAGS'].split())
            self.assertIn('sanitized',kwargs['env']['DUB_HOME'])

    def test_sanitizer_tests_link_the_fake_stack_runtime_only_in_that_lane(self):
        calls=[]
        class Recorder:
            plan=True
            def run(self,command,**kwargs):calls.append((command,kwargs))
        with patch.dict(os.environ,{'LIBRARY_PATH':'/opt/x11/lib'}):
            ci.run_tests(Recorder(),'ldc2',sanitize=True)
            sanitized=calls[0][1]['env'];calls.clear()
            ci.run_tests(Recorder(),'ldc2')
            normal=calls[0][1]['env']
        flags=sanitized['DFLAGS'].split()
        self.assertIn('-defaultlib=phobos2-ldc-sanitizers,druntime-ldc-sanitizers',flags)
        self.assertNotIn('-L-L',sanitized['DFLAGS'])
        self.assertEqual(sanitized['LIBRARY_PATH'].split(os.pathsep),
                         [str(ci.ROOT/'.tools/ldc-1.43.0-sanitizer-runtime/lib'),'/opt/x11/lib'])
        self.assertIn('detect_stack_use_after_return=1',sanitized['ASAN_OPTIONS'])
        self.assertNotIn('DFLAGS',normal)
        self.assertEqual(normal['LIBRARY_PATH'],'/opt/x11/lib')

    def test_sanitizer_gate_prepares_runtime_before_any_build(self):
        calls=[]
        class Recorder:
            plan=True
            def run(self,command,**kwargs):calls.append([str(x) for x in command])
        with patch.object(ci,'probe',return_value='clang version 22.1.8 (x)'),patch.object(ci,'preserve_native'):
            ci.check(Recorder(),'sanitizers')
        self.assertEqual(calls[0][1:],['tools/install_toolchains.py','--compiler','ldc-sanitizer-runtime'])
        self.assertFalse(any(command[-2:]==['--compiler','clang'] for command in calls))
        calls.clear()
        with patch.dict(os.environ,{}),patch.object(ci,'probe',return_value='clang version 18.1.3'),patch.object(ci,'preserve_native'):
            ci.check(Recorder(),'sanitizers')
            self.assertTrue(os.environ['PATH'].startswith(str(ci.ROOT/'.tools/LLVM-22.1.8-Linux-X64/bin')))
        self.assertEqual(calls[0][1:],['tools/install_toolchains.py','--compiler','clang'])

    def test_vendor_ubsan_exclusions_are_scoped_to_one_provider_build(self):
        with tempfile.TemporaryDirectory() as temporary:
            args=SimpleNamespace(target='linux-x86_64-glibc',work_dir=temporary,prefix=None,cc='clang',cxx='clang++',
                                 sanitize='address,undefined',phase='plan',cmake_toolchain=None,jobs=1,
                                 profile='ci',with_codegen=False,allow_webview=False)
            builder=native_build.Builder(args,json.loads((TOOLS.parent/'policy/native-lock.json').read_text(encoding='utf-8')))
            seen={}
            def build_source(name,src,build):seen[name]=builder.env['CFLAGS'].split()
            with patch.object(builder,'build_source',side_effect=build_source):
                for name in ('openssl','protobuf-c','curl'):builder.build(name)
            for name in ('openssl','protobuf-c'):
                self.assertEqual(seen[name][-1],'-fno-sanitize=function')
                self.assertIn('-fsanitize=address,undefined',seen[name])
            self.assertNotIn('-fno-sanitize=function',seen['curl'])
            self.assertNotIn('-fno-sanitize=function',builder.env['CFLAGS'])
            self.assertEqual(native_build.VENDOR_UBSAN_EXCLUSIONS.keys(),{'openssl','protobuf-c'})
            args.sanitize='address'
            self.assertEqual(builder.sanitizer_exclusions('openssl'),())

    def test_ruleset_preparation_never_calls_github(self):
        with tempfile.TemporaryDirectory() as temporary,patch.object(configure,'api',side_effect=AssertionError('network mutation')):
            output=Path(temporary)/'ruleset.json'
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(configure.main(['--repo','example/flint','--output',str(output)]),0)
            rules=json.loads(output.read_text(encoding='utf-8'))
            required=rules['rules'][0]['parameters']
            self.assertEqual(required['required_status_checks'],[{'context':'Flint / all six gates'}])
            self.assertTrue(required['strict_required_status_checks_policy'])
            self.assertEqual(rules['bypass_actors'],[])

    def test_wasm_lane_includes_all_five_betterc_packages(self):
        calls=[]
        class Recorder:
            plan=True
            def run(self,command,**kwargs):calls.append([str(x).replace(os.sep,'/') for x in command])
        ci.wasm_betterc(Recorder())
        compiles=[command for command in calls if command[0]=='ldc2']
        self.assertEqual(len(compiles),5)
        paths=[next(x for x in command if x.endswith('/tests/betterc.d')) for command in compiles]
        for package in ['arena','serde','validate','engine-wasm-bridge','engine-ui-signals']:
            # packages/<name> before the cutover; an engine's engine/<name> in flint-framework after it.
            spellings=['/'+package+'/tests/betterc.d','/'+package.replace('engine-','engine/',1)+'/tests/betterc.d']
            self.assertTrue(any(spelling in path for path in paths for spelling in spellings),package)
        for command in compiles:
            self.assertIn('-L--export=flint_test',command)
            self.assertIn('-boundscheck=on',command)

    def test_all_native_targets_prepare_the_default_wasi_provider(self):
        for target in ci.PLATFORMS:
            if target=='wasm32':continue
            calls=[]
            class Recorder:
                plan=True
                def run(self,command,**kwargs):calls.append(([str(x) for x in command],kwargs))
            ci.native(Recorder(),target)
            install,build=calls
            self.assertEqual(install[0][1],'tools/install_rust.py')
            self.assertIn(target,install[0])
            self.assertIn('--library',build[0]);self.assertIn('wasmtime',build[0])
            self.assertEqual(build[1]['env']['RUSTUP_TOOLCHAIN'],'1.97.0')
            self.assertTrue(build[1]['env']['CARGO_HOME'].endswith('/.tools/rust/cargo') or
                            build[1]['env']['CARGO_HOME'].endswith('\\.tools\\rust\\cargo'))

    def test_sanitizers_prepare_uninstrumented_engine_in_shared_prefix(self):
        calls=[]
        class Recorder:
            plan=True
            def run(self,command,**kwargs):calls.append(([str(x) for x in command],kwargs))
        target='linux-x86_64-glibc';ci.native(Recorder(),target,sanitize=True)
        install,engine,c_providers=calls
        self.assertIn('tools/install_rust.py',install[0])
        self.assertIn('wasm-host',engine[0]);self.assertNotIn('--sanitize',engine[0])
        self.assertNotIn('--emit-dub',engine[0])
        self.assertIn('.native-sanitized/engine-build',engine[0])
        self.assertIn('.native-sanitized/install/'+target,engine[0])
        self.assertIn('address,undefined',c_providers[0]);self.assertIn('--emit-dub',c_providers[0])
        self.assertNotIn('--library',c_providers[0])
        self.assertEqual(engine[1]['env']['RUSTUP_TOOLCHAIN'],c_providers[1]['env']['RUSTUP_TOOLCHAIN'])

    def test_native_evidence_retains_engine_logs_and_rust_identity(self):
        with tempfile.TemporaryDirectory() as temporary,patch.object(ci,'ROOT',Path(temporary)):
            target='linux-x86_64-glibc';root=Path(temporary)
            for relative,content in [
                ('.native-sanitized/engine-build/logs/'+target+'/wasmtime.log','engine output'),
                ('.native-sanitized/logs/'+target+'/shims.log','instrumented output'),
                ('.native-sanitized/install/'+target+'/flint-native-install.json','{}'),
                ('.tools/rust/flint-rust-install.json','{"rust_version":"1.97.0"}')]:
                path=root/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(content, encoding='utf-8', newline='\n')
            ci.preserve_native(target,sanitize=True)
            output=root/'artifacts/native-sanitizers'
            self.assertEqual((output/'engine-logs/wasmtime.log').read_text(encoding='utf-8'),'engine output')
            self.assertTrue((output/'logs/shims.log').is_file())
            self.assertTrue((output/(target+'-install.json')).is_file())
            self.assertEqual(json.loads((output/'rust-toolchain-install.json').read_text(encoding='utf-8'))['rust_version'],'1.97.0')

if __name__=='__main__':unittest.main()
