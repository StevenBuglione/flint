#!/usr/bin/env python3
"""Pinned native dependency preparation. Plans are not verification receipts.

Python >=3.12. Run on the target OS/architecture/libc. CMake cross files are
supported for CMake-only closures; other cross-host recipes fail explicitly.
No command is executed through a shell. Native source/build/cache directories
are disposable; this script never resets the Flint repository.
"""
from __future__ import annotations
import argparse, hashlib, json, os, platform, re, shlex, shutil, subprocess, sys, tarfile, tempfile, tomllib, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from workspace import Workspace  # noqa: E402

# The checkouts of each repo (plan section 7): the monorepo unless --workspace names a flint.workspace/1 file.
WORKSPACE = Workspace()

# The Flint C shims split by repo (plan section 7): native/ffi builds the flint repo's flint_ffi_base, and
# native/framework the engines' flint_ffi_framework from their packages' native/ffi. The flint repo's
# closure links only flint_ffi_base; framework and portfolio packages link flint_ffi_framework first, then base.
BASE_SHIMS = ('flint_abi_probe.c', 'flint_utf8proc.c', 'flint_yaml.c')
FFI_ARCHIVES = {'base': ('libflint_ffi_base.a', 'flint_ffi_base.lib'),
                'framework': ('libflint_ffi_framework.a', 'flint_ffi_framework.lib')}

def ffi_archives_for(repo):
    """The shim archives a package of `repo` links, in link order."""
    return ['base'] if repo == 'flint' else ['framework', 'base']

def package_path(package):
    """A package's directory: in its repo's checkout with --workspace, else under ROOT."""
    return WORKSPACE.package_dir(package, ROOT) if WORKSPACE.file else ROOT/'packages'/package

def flint_checkout():
    """The flint repo's checkout, which holds native/ffi and the Conan recipe index."""
    return WORKSPACE.checkout('flint') if WORKSPACE.file else ROOT

def framework_shims():
    """The engines' shim project (flint_ffi_framework): native/framework here, native/ in flint-framework."""
    return WORKSPACE.locate('framework','native/framework',ROOT) if WORKSPACE.file else ROOT/'native/framework'

TARGETS = ('linux-x86_64-glibc','linux-aarch64-glibc','linux-x86_64-musl','linux-aarch64-musl','macos-arm64','windows-x86_64')
PROFILES = {
    'rest': ['openssl','libsodium','llhttp','nghttp2','curl'],
    'http': ['curl'], 'mail': ['curl'], 'sql':['sqlite','libpq'], 'mq':['librdkafka'],
    'codec':['zstd','zlib','brotli','libarchive'], 'desktop':['webkitgtk'], 'desktop-canvas':['sdl3'],
    'wasm-host':['wasmtime'], 'tui':['utf8proc'], 'yaml':['libyaml'],
    # C-provider closure; all-package CI adds --library wasmtime explicitly.
    'ci':['openssl','libsodium','llhttp','nghttp2','curl','sqlite','libpq','librdkafka','zstd','zlib','brotli','libarchive','utf8proc','libyaml','sdl3','protobuf-c','hiredis','crypt-blowfish'],
}
# UBSan checks disabled per vendored provider in sanitizer builds. Every other
# requested check stays on, and Flint's own shims (native/ffi) keep full UBSan.
# -fsanitize=function rejects calls through a function pointer whose type differs
# from the callee's definition. Both providers below dispatch typed callbacks
# through generic pointer types by design; the findings sit in upstream code and
# are reproducible without Flint calling them incorrectly:
#  - openssl 3.5.9: OPENSSL_sk_pop_free (crypto/stack/stack.c) calls typed free
#    functions as void (*)(void *); ossl_sa_doall_arg (crypto/sparse_array.c) calls
#    typed leaf callbacks; EVP_DigestUpdate (crypto/evp/digest.c) calls provider
#    update functions as int (*)(void *, const unsigned char *, size_t).
#  - protobuf-c 1.5.2: protobuf_c_message_init calls each message's generated
#    foo__init(Foo *) through ProtobufCMessageInit, void (*)(ProtobufCMessage *).
VENDOR_UBSAN_EXCLUSIONS = {'openssl': ('function',), 'protobuf-c': ('function',)}
# ADR-031: OpenSSL is built for TLS 1.2 and 1.3 only. Every switch removes an algorithm, protocol or
# subsystem that neither Flint's TLS profile (native/ffi/flint_web_tls.c and the clients' OpenSSL defaults)
# nor a consumer (curl, libpq, librdkafka, the Flint shims) uses. tools/tls_profile_matrix.py shows that
# every handshake negotiates the same version, cipher, group and signature as the full build. dh, ecx
# (X25519 and X448 together), ML-KEM and ML-DSA stay, because the profile negotiates or advertises them.
OPENSSL_TLS_ONLY = ['no-legacy', 'no-des', 'no-rc2', 'no-rc4', 'no-bf', 'no-cast', 'no-idea', 'no-seed',
                    'no-camellia', 'no-aria', 'no-sm2', 'no-sm3', 'no-sm4', 'no-whirlpool', 'no-mdc2', 'no-rmd160',
                    'no-md4', 'no-gost', 'no-srp', 'no-psk', 'no-ssl3', 'no-tls1', 'no-tls1_1', 'no-dtls',
                    'no-sctp', 'no-srtp', 'no-nextprotoneg', 'no-ec2m', 'no-dsa', 'no-cms', 'no-ts', 'no-cmp',
                    'no-ct', 'no-engine', 'no-dynamic-engine', 'no-quic', 'no-comp', 'no-argon2', 'no-scrypt',
                    'no-siv', 'no-ocb', 'no-siphash', 'no-slh-dsa', 'no-ssl-trace']
CMAKE = {
 'llhttp': ('.', ['LLHTTP_BUILD_SHARED_LIBS=OFF','LLHTTP_BUILD_STATIC_LIBS=ON']),
 'nghttp2': ('.', ['ENABLE_LIB_ONLY=ON','BUILD_STATIC_LIBS=ON','BUILD_SHARED_LIBS=OFF','BUILD_TESTING=OFF']),
 'curl': ('.', ['BUILD_CURL_EXE=OFF','BUILD_SHARED_LIBS=OFF','BUILD_STATIC_LIBS=ON','BUILD_TESTING=OFF','HTTP_ONLY=ON','CURL_USE_OPENSSL=ON','CURL_USE_LIBPSL=OFF','CURL_USE_LIBSSH2=OFF','CURL_USE_GSSAPI=OFF','USE_NGHTTP2=ON','USE_LIBIDN2=OFF','CURL_ZLIB=ON','CURL_BROTLI=OFF','CURL_ZSTD=OFF','ENABLE_THREADED_RESOLVER=ON']),
 'librdkafka': ('.', ['RDKAFKA_BUILD_STATIC=ON','RDKAFKA_BUILD_EXAMPLES=OFF','RDKAFKA_BUILD_TESTS=OFF','WITH_SSL=ON','WITH_SASL=OFF','WITH_CURL=OFF','WITH_ZLIB=ON','WITH_ZSTD=ON','WITH_PLUGINS=OFF','ENABLE_LZ4_EXT=OFF']),
 'zstd': ('build/cmake', ['ZSTD_BUILD_STATIC=ON','ZSTD_BUILD_SHARED=OFF','ZSTD_BUILD_PROGRAMS=OFF','ZSTD_BUILD_TESTS=OFF']),
 'zlib': ('.', ['ZLIB_BUILD_SHARED=OFF','ZLIB_BUILD_STATIC=ON','ZLIB_BUILD_TESTING=OFF']),
 'brotli': ('.', ['BUILD_SHARED_LIBS=OFF','BUILD_TESTING=OFF']),
 'hiredis': ('.', ['BUILD_SHARED_LIBS=OFF','ENABLE_SSL=ON','DISABLE_TESTS=ON']),
 'utf8proc': ('.', ['BUILD_SHARED_LIBS=OFF','UTF8PROC_ENABLE_TESTING=OFF']),
 'libyaml': ('.', ['BUILD_SHARED_LIBS=OFF','BUILD_TESTING=OFF','CMAKE_POLICY_VERSION_MINIMUM=3.5']),
 'protobuf-c': ('build-cmake', ['BUILD_SHARED_LIBS=OFF','BUILD_TESTS=OFF']),
 'protoc': ('.', ['protobuf_BUILD_SHARED_LIBS=OFF','protobuf_BUILD_TESTS=OFF','protobuf_BUILD_EXAMPLES=OFF','protobuf_BUILD_PROTOC_BINARIES=ON','protobuf_BUILD_LIBPROTOC=ON','protobuf_WITH_ZLIB=ON','protobuf_ABSL_PROVIDER=module','protobuf_MSVC_STATIC_RUNTIME=OFF']),
 'sdl3': ('.', ['SDL_SHARED=OFF','SDL_STATIC=ON','SDL_TESTS=OFF','SDL_TEST_LIBRARY=OFF','SDL_EXAMPLES=OFF','SDL_LIBUDEV=OFF','SDL_DBUS=OFF','SDL_IBUS=OFF','SDL_FCITX=OFF','SDL_LIBICONV=OFF','SDL_HIDAPI_LIBUSB=OFF','SDL_FRIBIDI=OFF','SDL_LIBTHAI=OFF','SDL_LIBURING=OFF']),
 'webview': ('.', ['WEBVIEW_BUILD_SHARED_LIBRARY=OFF','WEBVIEW_BUILD_STATIC_LIBRARY=ON','WEBVIEW_BUILD_TESTS=OFF','WEBVIEW_BUILD_EXAMPLES=OFF','WEBVIEW_BUILD_DOCS=OFF','WEBVIEW_INSTALL_DOCS=OFF','WEBVIEW_ENABLE_PACKAGING=OFF','WEBVIEW_ENABLE_CHECKS=OFF','WEBVIEW_USE_COMPAT_MINGW=OFF','WEBVIEW_BUILD=ON','WEBVIEW_INSTALL_TARGETS=ON']),
 'libarchive': ('.', ['BUILD_SHARED_LIBS=OFF','ENABLE_TEST=OFF','ENABLE_TAR=OFF','ENABLE_CPIO=OFF','ENABLE_CAT=OFF','ENABLE_UNZIP=OFF','ENABLE_OPENSSL=OFF','ENABLE_MBEDTLS=OFF','ENABLE_NETTLE=OFF','ENABLE_ICONV=OFF','ENABLE_ACL=OFF','ENABLE_XATTR=OFF','ENABLE_LIBXML2=OFF','ENABLE_EXPAT=OFF','ENABLE_LZMA=OFF','ENABLE_LZ4=OFF','ENABLE_BZip2=OFF','ENABLE_ZSTD=ON','ENABLE_ZLIB=ON']),
}
ALIASES = {
 'openssl': [('ssl','libssl'),('crypto','libcrypto')], 'libsodium':[('sodium','libsodium')],
 'llhttp':[('llhttp','llhttp_static')], 'nghttp2':[('nghttp2','nghttp2_static')], 'curl':[('curl','libcurl','libcurl_a')],
 'librdkafka':[('rdkafka','rdkafka_static')], 'zstd':[('zstd','zstd_static')], 'zlib':[('z','zlibstatic','zlib','zs')],
 'brotli':[('brotlienc','brotlienc-static'),('brotlidec','brotlidec-static'),('brotlicommon','brotlicommon-static')],
 'hiredis':[('hiredis_ssl','hiredis_ssl_static'),('hiredis','hiredis_static')], 'liburing':[('uring-ffi',),('uring',)],
 'utf8proc':[('utf8proc','utf8proc_static')], 'libyaml':[('yaml','yaml_static')], 'protobuf-c':[('protobuf-c',)],
 'protoc':[], 'sqlite':[('sqlite3',)], 'libpq':[('pq','libpq'),('pgcommon_shlib',),('pgport_shlib',)],
 'wasmtime':[('wasmtime',)], 'wamr':[('vmlib',)], 'sdl3':[('SDL3','SDL3-static')],
 'wgpu-native':[('wgpu_native',)], 'webview':[('webview','webview_core','webview_static')], 'stb':[('flint_stb',)], 'libarchive':[('archive','archive_static')],
 'webkitgtk':[], 'wkwebview':[], 'crypt-blowfish':[('crypt_blowfish',)],
}
# Dynamic system providers, never downloaded or linked statically: resolved through pkg-config on Linux,
# and from the macOS SDK's framework stubs on macOS (ADR-024).
SYSTEM = {'webkitgtk','wkwebview'}
STANDARD_LIBRARY_DIRS = {'/lib','/lib64','/usr/lib','/usr/lib64','/usr/lib/x86_64-linux-gnu','/usr/lib/aarch64-linux-gnu'}

def digest(path: Path) -> str:
    with path.open('rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()

def host_target() -> str:
    machine = platform.machine().lower()
    arch = 'aarch64' if machine in ('aarch64','arm64') else 'x86_64' if machine in ('x86_64','amd64') else machine
    if sys.platform == 'win32': return 'windows-'+arch
    if sys.platform == 'darwin': return 'macos-'+('arm64' if arch=='aarch64' else arch)
    musl = bool(list(Path('/lib').glob('ld-musl-*.so.1')))
    return 'linux-'+arch+('-musl' if musl else '-glibc')

class Builder:
    def __init__(self, args, lock):
        self.a=args; self.rows={x['name']:x for x in lock['libraries']}; self.plan=[]; self.link_metadata={}; self.toolchain_metadata={}
        self.work=Path(args.work_dir).resolve(); self.prefix=Path(args.prefix).resolve() if args.prefix else self.work/'install'/args.target
        self.sources=self.work/'sources'; self.cache=self.work/'cache'; self.env=os.environ.copy()
        self.env['CMAKE_PREFIX_PATH']=str(self.prefix)
        self.env['PKG_CONFIG_PATH']=os.pathsep.join(str(self.prefix/x) for x in ['lib/pkgconfig','lib64/pkgconfig','share/pkgconfig'])
        self.env['PKG_CONFIG_LIBDIR']=self.env['PKG_CONFIG_PATH']
        self.env['PATH']=str(self.prefix/'bin')+os.pathsep+self.env.get('PATH','')
        # MSVC hardening for every provider (ADR-026): Control Flow Guard metadata, buffer security checks and the SDL
        # checks. /O2 is explicit because OpenSSL's Configure replaces its default flags with CFLAGS from the environment.
        # /sdl also turns some vendor warnings into errors. In third-party code these stay off: C4703 (a possibly
        # uninitialized pointer, a false positive in libpq's fe-connect.c), C4996 (CRT and Winsock functions Microsoft
        # deprecates in favour of its _s variants, used by librdkafka) and C4700 (an uninitialized local: librdkafka's
        # rd_kafka_cgrp_rejoin passes its va_list to the KIP-848 consumer path before va_start, a real upstream bug on a
        # path Flint never takes, since it keeps the default classic group protocol) and C4146 (unary minus on an
        # unsigned value: protobuf-c's zigzag encoding, well defined in C). Flint's own C keeps every error.
        windows_flags=' /MD /O2 /guard:cf /GS /sdl /wd4703 /wd4996 /wd4700 /wd4146'
        self.env['CFLAGS']=self.env.get('CFLAGS','')+(windows_flags if args.target.startswith('windows') else ' -O2 -fPIC')
        if args.target.startswith('windows'):self.env['CXXFLAGS']=self.env.get('CXXFLAGS','')+windows_flags
        self.env['CPPFLAGS']=self.env.get('CPPFLAGS','')+(' /I' if args.target.startswith('windows') else ' -I')+str(self.prefix/'include')
        self.env['LDFLAGS']=self.env.get('LDFLAGS','')+(' /LIBPATH:' if args.target.startswith('windows') else ' -L')+str(self.prefix/'lib')
        if args.cc: self.env['CC']=args.cc
        if args.cxx: self.env['CXX']=args.cxx
        if args.sanitize:
            if args.target.startswith('windows'):raise ValueError('--sanitize uses GCC/Clang instrumentation; use a POSIX sanitizer lane')
            flags=' -fsanitize='+args.sanitize+' -fno-omit-frame-pointer'
            self.env['CFLAGS']+=flags
            self.env['CXXFLAGS']=self.env.get('CXXFLAGS','')+flags
            self.env['LDFLAGS']+=' -fsanitize='+args.sanitize
        self.receipt_path=self.prefix/'flint-native-install.json'
        self.receipt=json.loads(self.receipt_path.read_text()) if self.receipt_path.exists() else {'schema':1,'target':args.target,'libraries':{}}
        if self.receipt['target']!=args.target: raise ValueError('Prefix belongs to another target')

    def command(self, argv, cwd):
        argv=[str(x) for x in argv]; cwd=Path(cwd)
        self.plan.append({'argv':argv,'cwd':str(cwd)})
        if self.a.phase!='build': return
        cwd.mkdir(parents=True,exist_ok=True)
        print('native:',Path(argv[0]).name,' '.join(argv[1:4]),flush=True)
        result=subprocess.run(argv,cwd=cwd,env=self.env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        logs=self.work/'logs'/self.a.target; logs.mkdir(parents=True,exist_ok=True)
        (logs/f'{len(self.plan):04d}-{Path(argv[0]).name}.log').write_text(result.stdout)
        if result.returncode: raise RuntimeError('Command failed: '+repr(argv)+'\n'+result.stdout[-12000:])
        return result.stdout

    def write(self,path,text):
        self.plan.append({'write':str(path),'sha256':hashlib.sha256(text.encode()).hexdigest()})
        if self.a.phase=='build': path.parent.mkdir(parents=True,exist_ok=True); path.write_text(text)

    def fetch(self,name):
        row=self.rows[name]; revision=row.get('commit',row.get('source_id'))
        if not revision or not re.fullmatch('[a-f0-9]{40}|[a-f0-9]{64}',revision): raise ValueError('Missing immutable revision: '+name)
        archive=self.cache/(row['archive_sha256']+'.tar.gz'); src=self.sources/(name+'-'+revision[:12])
        self.plan.append({'download':row['archive_url'],'sha256':row['archive_sha256'],'destination':str(archive)})
        if self.a.phase=='plan': return src
        self.cache.mkdir(parents=True,exist_ok=True); self.sources.mkdir(parents=True,exist_ok=True)
        if not archive.exists():
            temporary=archive.with_suffix('.part')
            request=urllib.request.Request(row['archive_url'],headers={'User-Agent':'flint-native-build/1'})
            with urllib.request.urlopen(request,timeout=120) as response, temporary.open('wb') as output: shutil.copyfileobj(response,output)
            if digest(temporary)!=row['archive_sha256']: temporary.unlink(); raise RuntimeError('Source hash mismatch: '+name)
            temporary.replace(archive)
        if digest(archive)!=row['archive_sha256']: raise RuntimeError('Cached source hash mismatch: '+name)
        if not src.exists():
            with tempfile.TemporaryDirectory(dir=self.sources,prefix='unpack-') as tmp:
                with tarfile.open(archive,'r:gz') as bundle: bundle.extractall(tmp,filter='data')
                entries=list(Path(tmp).iterdir())
                if len(entries)!=1 or not entries[0].is_dir(): raise RuntimeError('Unexpected source archive layout: '+name)
                entries[0].rename(src)
        if name=='sqlite':
            actual=hashlib.sha3_256((src/'sqlite3.c').read_bytes()).hexdigest()
            if actual!=row['amalgamation_sha3_256']: raise RuntimeError('SQLite amalgamation hash mismatch')
        return src

    def submodules(self,name,src):
        # Root source hash is pinned above. Every submodule revision is a gitlink
        # from that immutable commit; never follow a submodule remote branch.
        if name not in ('protoc','wasmtime','wgpu-native'): return
        row=self.rows[name]
        self.command(['git','init','--quiet'],src)
        self.command(['git','config','remote.origin.url','https://github.com/'+row['repo']+'.git'],src)
        self.command(['git','fetch','--depth=1','origin',row['commit']],src)
        self.command(['git','checkout','--force','--detach',row['commit']],src)
        self.command(['git','-c','protocol.file.allow=never','submodule','update','--init','--recursive','--depth=1'],src)

    def cmake(self,name,src,build,relative,options,install=True,target=None):
        options=list(options)
        # macOS (ADR-024) and Windows (ADR-026) get the Linux protocol set; macOS's curl also needs SystemConfiguration
        # (dub_blocks).
        if name == 'curl' and (self.a.target.startswith('linux') or self.a.target in ('macos-arm64', 'windows-x86_64')):
            options.remove('HTTP_ONLY=ON')  # The pinned CMake removed this option.
            smtp = self.a.profile in ('mail', 'ci', 'all')
            options += ['CURL_DISABLE_SMTP=' + ('OFF' if smtp else 'ON'), 'CURL_USE_LIBSSH=OFF']
            disabled = ('DICT', 'FILE', 'FTP', 'GOPHER', 'IMAP', 'LDAP', 'LDAPS', 'MQTT',
                        'POP3', 'RTSP', 'TELNET', 'TFTP', 'IPFS')
            options += ['CURL_DISABLE_' + protocol + '=ON' for protocol in disabled]
            # Windows builds LDAP through wldap32 unless told otherwise; the closure speaks HTTP and SMTP only.
            if self.a.target.startswith('windows'): options += ['USE_WIN32_LDAP=OFF']
        if name=='protobuf-c': options += ['BUILD_PROTOC='+('ON' if self.a.with_codegen else 'OFF')]
        if name=='sdl3' and self.a.target.startswith('linux'): options += ['SDL_WAYLAND=OFF','SDL_X11=ON','SDL_X11_SHARED=ON','SDL_DEPS_SHARED=ON','SDL_KMSDRM=OFF','SDL_ALSA=OFF','SDL_PULSEAUDIO=OFF','SDL_PIPEWIRE=OFF','SDL_JACK=OFF','SDL_SNDIO=OFF','SDL_RPI=OFF','SDL_ROCKCHIP=OFF']
        argv=['cmake','-S',src/relative,'-B',build,'-G','Ninja','-DCMAKE_BUILD_TYPE=Release',
              '-DCMAKE_INSTALL_PREFIX='+str(self.prefix),'-DCMAKE_PREFIX_PATH='+str(self.prefix),
              '-DCMAKE_POSITION_INDEPENDENT_CODE=ON','-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF',
              '-DOPENSSL_ROOT_DIR='+str(self.prefix),'-DOPENSSL_USE_STATIC_LIBS=TRUE']
        if self.a.target.startswith('windows'): argv += ['-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL']
        if self.a.target.startswith('windows') and name != 'zlib':
            # zlib's MSVC build installs libzs.lib, a name CMake's FindZLIB does not search (ADR-026).
            zlib=[p for p in (self.prefix/'lib').glob('*.lib') if p.stem in ('libzs','zs','zlibstatic','zlib')]
            if zlib: argv += ['-DZLIB_LIBRARY='+sorted(zlib)[0].as_posix(),'-DZLIB_INCLUDE_DIR='+(self.prefix/'include').as_posix()]
        if self.a.target=='macos-arm64': argv += ['-DCMAKE_OSX_ARCHITECTURES=arm64','-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0']
        if self.a.cc: argv += ['-DCMAKE_C_COMPILER='+self.a.cc]
        if self.a.cxx: argv += ['-DCMAKE_CXX_COMPILER='+self.a.cxx]
        if self.a.cmake_toolchain: argv += ['-DCMAKE_TOOLCHAIN_FILE='+str(Path(self.a.cmake_toolchain).resolve())]
        self.command(argv+['-D'+x for x in options],ROOT)
        command=['cmake','--build',build,'--config','Release','--parallel',str(self.a.jobs)]
        if target:command+=['--target',target]
        self.command(command,ROOT)
        if install:self.command(['cmake','--install',build,'--config','Release'],ROOT)

    def copy(self,source,dest):
        self.plan.append({'copy':str(source),'destination':str(dest)})
        if self.a.phase=='build':
            if not source.exists():raise RuntimeError('Expected output missing: '+str(source))
            dest.parent.mkdir(parents=True,exist_ok=True)
            if source.is_dir():shutil.copytree(source,dest,dirs_exist_ok=True)
            else:shutil.copy2(source,dest)

    def build(self,name):
        row=self.rows[name]
        if self.a.target not in row['targets']:raise ValueError(name+' does not support '+self.a.target)
        if self.a.sanitize and name in ('wasmtime','wgpu-native'):raise ValueError('Rust engine sanitizer builds require their own pinned sanitizer lane')
        if name=='webview' and not self.a.allow_webview:raise ValueError('webview needs --allow-webview; Linux runtime is outside strict permissive profile')
        if name=='webview' and self.a.phase!='fetch' and self.a.target!='macos-arm64':raise ValueError('webview source fetch only on this target: Windows needs a separately pinned WebView2 SDK; Linux needs a separate LGPL runtime inventory/linker profile')
        if self.a.phase=='build' and host_target()!=self.a.target and name not in CMAKE:raise ValueError(name+' requires a native target runner; refusing an unverified cross recipe')
        if name in SYSTEM:
            if self.a.phase!='fetch':self.system_provider(name)
            return
        src=self.fetch(name); build=self.work/'build'/self.a.target/name
        if self.a.phase=='fetch': return
        exclusions=self.sanitizer_exclusions(name)
        if not exclusions:return self.build_source(name,src,build)
        saved={key:self.env.get(key) for key in ('CFLAGS','CXXFLAGS')}
        flag=' -fno-sanitize='+','.join(exclusions)
        self.env['CFLAGS']+=flag;self.env['CXXFLAGS']=self.env.get('CXXFLAGS','')+flag
        try:self.build_source(name,src,build)
        finally:
            for key,value in saved.items():
                if value is None:self.env.pop(key,None)
                else:self.env[key]=value

    def sanitizer_exclusions(self,name):
        if not self.a.sanitize or 'undefined' not in self.a.sanitize.split(','):return ()
        return VENDOR_UBSAN_EXCLUSIONS.get(name,())

    def build_source(self,name,src,build):
        self.submodules(name,src)
        if name=='protobuf-c' and not self.a.with_codegen:
            runtime=src/'protobuf-c'
            project='''cmake_minimum_required(VERSION 3.20)
project(flint_protobuf_c_runtime C)
include(TestBigEndian)
test_big_endian(PROTOBUF_C_BIG_ENDIAN)
add_library(protobuf-c STATIC "{runtime}/protobuf-c.c")
if(PROTOBUF_C_BIG_ENDIAN)
    target_compile_definitions(protobuf-c PRIVATE WORDS_BIGENDIAN)
endif()
install(TARGETS protobuf-c ARCHIVE DESTINATION lib)
install(FILES "{runtime}/protobuf-c.h" DESTINATION include/protobuf-c)
'''.format(runtime=runtime.as_posix())
            # The upstream runtime is standalone C. Its CMake generator recipe requires C++ Protobuf even when disabled.
            self.write(build/'runtime-project/CMakeLists.txt',project)
            self.cmake(name,build/'runtime-project',build/'runtime', '.',[])
        elif name in CMAKE:
            relative,options=CMAKE[name];self.cmake(name,src,build,relative,options)
        elif name=='openssl':
            target={'linux-x86_64-glibc':'linux-x86_64','linux-x86_64-musl':'linux-x86_64','linux-aarch64-glibc':'linux-aarch64','linux-aarch64-musl':'linux-aarch64','macos-arm64':'darwin64-arm64-cc','windows-x86_64':'VC-WIN64A'}[self.a.target]
            configure = ['perl', src/'Configure', target, 'no-shared', 'no-module', 'no-tests', *OPENSSL_TLS_ONLY,
                         '--prefix=' + str(self.prefix), '--libdir=lib']
            if self.a.target == 'linux-x86_64-glibc' and not self.a.sanitize:
                configure.append('CFLAGS=' + self.env['CFLAGS'] + ' -Os -ffunction-sections -fdata-sections')
            self.command(configure, build)
            make='nmake' if self.a.target.startswith('windows') else 'make'
            jobs=[] if make=='nmake' else ['-j',str(self.a.jobs)]
            self.command([make,*jobs,'build_libs'],build);self.command([make,'install_dev'],build)
        elif name=='libsodium':
            if self.a.target.startswith('windows'):
                self.command(['msbuild',src/'builds/msvc/vs2022/libsodium.sln','/m','/p:Configuration=StaticRelease','/p:Platform=x64'],src)
                self.copy(src/'bin/x64/Release/v143/static/libsodium.lib',self.prefix/'lib/libsodium.lib')
                self.copy(src/'src/libsodium/include/sodium.h',self.prefix/'include/sodium.h')
                self.copy(src/'src/libsodium/include/sodium',self.prefix/'include/sodium')
            else:
                self.command(['sh','autogen.sh'],src)
                self.command([src/'configure','--disable-shared','--enable-static','--prefix='+str(self.prefix)],build)
                self.command(['make','-j',str(self.a.jobs)],build);self.command(['make','install'],build)
        elif name=='liburing':
            if self.a.phase=='build':self.prefix.mkdir(parents=True,exist_ok=True)
            configure=['sh','configure','--use-libc','--prefix='+str(self.prefix),'--libdir='+str(self.prefix/'lib')]
            if self.a.sanitize=='address,undefined':configure.append('--enable-sanitizer')
            if self.a.phase=='plan' or (src/'config-host.mak').exists():self.command(['make','-C','src','clean'],src)
            self.command(configure,src)
            self.command(['make','-C','src','-j',str(self.a.jobs)],src);self.command(['make','-C','src','install'],src)
        elif name in ('sqlite','stb'):
            if name=='sqlite':
                files='"'+(src/'sqlite3.c').as_posix()+'"';library='sqlite3'
                extra='target_compile_definitions(sqlite3 PRIVATE SQLITE_THREADSAFE=1 SQLITE_OMIT_LOAD_EXTENSION SQLITE_DEFAULT_MEMSTATUS=0)\n'
                headers='"'+(src/'sqlite3.h').as_posix()+'" "'+(src/'sqlite3ext.h').as_posix()+'"'
            else:
                library='flint_stb';unit=build/'project/flint_stb.c'
                self.write(unit,'#define STB_IMAGE_IMPLEMENTATION\n#define STBI_NO_STDIO\n#define STBI_MAX_DIMENSIONS 16384\n#include "stb_image.h"\n')
                files='"'+unit.as_posix()+'"';extra='target_include_directories(flint_stb PRIVATE "'+src.as_posix()+'")\n';headers='"'+(src/'stb_image.h').as_posix()+'"'
            project='cmake_minimum_required(VERSION 3.20)\nproject(flint_native C)\nadd_library('+library+' STATIC '+files+')\n'+extra+'\ninstall(TARGETS '+library+' ARCHIVE DESTINATION lib)\ninstall(FILES '+headers+' DESTINATION include)\n'
            self.write(build/'project/CMakeLists.txt',project);self.cmake(name,build/'project',build/'cmake','.',[])
        elif name=='crypt-blowfish':
            # Openwall ships a Makefile only. crypt_blowfish.c holds bcrypt and its salt encoder; wrapper.c is left out
            # because it defines crypt, crypt_r and crypt_gensalt, the C library's names, and x86.S is i386-only.
            source=(src/'crypt_blowfish.c').as_posix();header=(src/'crypt_blowfish.h').as_posix()
            flags=' '.join(json.dumps(flag) for flag in self.provider_hardening())
            project=('cmake_minimum_required(VERSION 3.20)\nproject(flint_native C)\n'
                     'add_library(crypt_blowfish STATIC "'+source+'")\n'
                     +('target_compile_options(crypt_blowfish PRIVATE '+flags+')\n' if flags else '')
                     +'install(TARGETS crypt_blowfish ARCHIVE DESTINATION lib)\ninstall(FILES "'+header+'" DESTINATION include)\n')
            self.write(build/'project/CMakeLists.txt',project);self.cmake(name,build/'project',build/'cmake','.',[])
        elif name=='libpq':
            options=['docs','gssapi','icu','ldap','libcurl','libnuma','liburing','libxml','libxslt','llvm','lz4','nls','pam','plperl','plpython','pltcl','readline','selinux','systemd','tap_tests','zstd']
            reconfigure=['--reconfigure'] if (build/'meson-private/coredata.dat').is_file() and self.a.phase=='build' else []
            include_flag=('/I' if self.a.target.startswith('windows') else '-I')+str(self.prefix/'include')
            frontend_flags=shlex.split(self.env.get('CFLAGS',''))+shlex.split(os.environ.get('CPPFLAGS',''))+[include_flag]
            # Static libcrypto on Windows needs Winsock and the Crypto API in every link, Meson's checks included.
            # libpq itself links no zlib (the server tools do); Windows has no pkg-config for Meson to find it with.
            zlib_feature='disabled' if self.a.target.startswith('windows') else 'enabled'
            link_args=['-Dc_link_args='+repr(['ws2_32.lib','crypt32.lib','advapi32.lib','user32.lib'])] if self.a.target.startswith('windows') else []
            self.command(['meson','setup',*reconfigure,build,src,'--prefix='+str(self.prefix),'--buildtype=release','-Dssl=openssl','-Dzlib='+zlib_feature,'-Dc_args='+repr(frontend_flags),*link_args,*['-D'+x+'=disabled' for x in options]],ROOT)
            # PostgreSQL's libpq Makefile links these static support variants for the public encoding ABI.
            client_targets=('libpq','libpgcommon_shlib','libpgport_shlib')
            self.command(['meson','compile','-C',build,'-j',str(self.a.jobs),*[target+':static_library' for target in client_targets]],ROOT)
            if self.a.phase=='build':
                targets=json.loads(subprocess.check_output(['meson','introspect','--targets',str(build)],text=True))
                for target in targets:
                    if target['type']=='static library' and target['name'] in client_targets:
                        for filename in target['filename']:self.copy(Path(filename),self.prefix/'lib'/Path(filename).name)
            else:self.plan.append({'install_meson_static_targets':list(client_targets)})
            for header in ['libpq-fe.h','libpq-events.h']:self.copy(src/'src/interfaces/libpq'/header,self.prefix/'include'/header)
            self.copy(src/'src/include/postgres_ext.h',self.prefix/'include/postgres_ext.h')
        elif name in ('wasmtime','wgpu-native'):
            triple={'linux-x86_64-glibc':'x86_64-unknown-linux-gnu','linux-aarch64-glibc':'aarch64-unknown-linux-gnu','linux-x86_64-musl':'x86_64-unknown-linux-musl','linux-aarch64-musl':'aarch64-unknown-linux-musl','macos-arm64':'aarch64-apple-darwin','windows-x86_64':'x86_64-pc-windows-msvc'}[self.a.target]
            if self.a.phase=='build' and not (src/'Cargo.lock').exists():raise RuntimeError('Rust dependency lockfile missing')
            rust_version=self.command(['rustc','--version','--verbose'],src)
            cargo_version=self.command(['cargo','--version'],src)
            if self.a.phase=='build':self.toolchain_metadata[name]={'rustc_verbose':rust_version,'cargo_version':cargo_version,'requested_rustup_toolchain':self.env.get('RUSTUP_TOOLCHAIN')}
            self.env['CARGO_TARGET_DIR']=str(src/'target')
            self.env['CARGO_PROFILE_RELEASE_PANIC']='abort'
            args=['cargo','rustc','--lib','--crate-type','staticlib','--release','--locked','--jobs',str(self.a.jobs),'--target',triple]
            if name=='wasmtime':args+=['-p','wasmtime-c-api','--no-default-features','--features','cranelift,wasi,component-model,component-model-async']
            # The extension is portable Rust over the C API; macOS (ADR-024) and Windows (ADR-026) build it too.
            flint_extensions=name=='wasmtime'
            if flint_extensions:
                extension=package_path('engine-wasi')/'native/install_extensions.py'
                self.command([sys.executable,extension,src],src)
                args[-1]+=',flint-wasi-extensions'
            output=self.command(args+['--','--print','native-static-libs'],src)
            if self.a.phase=='build':
                matches=re.findall(r'native-static-libs:\s*(.+)',output)
                if not matches:raise RuntimeError('Rust did not report its native static link closure')
                flags=self.normalize_link_flags(shlex.split(matches[-1]))
                metadata=build/'native-static-link.json'
                self.write(metadata,json.dumps({'flags':flags},indent=2)+'\n')
                self.link_metadata[name]={'path':str(metadata),'sha256':digest(metadata),'flags':flags}
            basename='wasmtime' if name=='wasmtime' else 'wgpu_native';file=basename+'.lib' if self.a.target.startswith('windows') else 'lib'+basename+'.a'
            self.copy(src/'target'/triple/'release'/file,self.prefix/'lib'/file)
            if name=='wasmtime':
                features=['CRANELIFT','WASI','COMPONENT_MODEL','COMPONENT_MODEL_ASYNC','ASYNC']
                self.command(['cmake','-DWASMTIME_DISABLE_ALL_FEATURES=ON','-DCMAKE_INSTALL_PREFIX='+str(self.prefix),*['-DWASMTIME_FEATURE_'+f+'=ON' for f in features],'-P','cmake/install-headers.cmake'],src/'crates/c-api')
                if flint_extensions:
                    overlay=self.command([sys.executable,extension,src,'--install-prefix',self.prefix],src)
                    if self.a.phase=='build':
                        self.toolchain_metadata[name]['flint_extensions']=json.loads(overlay)
            else:
                self.copy(src/'ffi/wgpu.h',self.prefix/'include/wgpu.h')
                self.copy(src/'ffi/webgpu-headers/webgpu.h',self.prefix/'include/webgpu.h')
        elif name=='wamr':
            osdir='windows' if self.a.target.startswith('windows') else 'darwin' if self.a.target.startswith('macos') else 'linux'
            options=['BUILD_SHARED_LIBS=OFF','WAMR_BUILD_INTERP=1','WAMR_BUILD_AOT=0','WAMR_BUILD_JIT=0','WAMR_BUILD_FAST_JIT=0','WAMR_BUILD_LIBC_WASI=1','WAMR_BUILD_LIBC_BUILTIN=1','WAMR_BUILD_TARGET='+('AARCH64' if 'aarch64' in self.a.target or 'arm64' in self.a.target else 'X86_64')]
            self.cmake(name,src,build,'product-mini/platforms/'+osdir,options,install=False,target='vmlib')
            filename='vmlib.lib' if self.a.target.startswith('windows') else 'libvmlib.a'
            self.copy(build/filename,self.prefix/'lib'/filename);self.copy(src/'core/iwasm/include',self.prefix/'include')
        else:raise ValueError('No build recipe for '+name)
        if self.a.phase=='build':self.record(name)

    def provider_hardening(self):
        """The hardening set of policy/native-c.toml for a provider built from a project Flint writes: [c] on Linux,
        [macos] on macOS, and nothing more on Windows, whose MSVC set is already in CFLAGS. Only the protector and
        _FORTIFY_SOURCE flags are taken: -O2 is in CFLAGS, and every provider archive is built -fPIC rather than -fPIE.
        A sanitizer build takes the sanitize set's flags, without _FORTIFY_SOURCE, which ASan does not combine with.
        -U first, because a compiler may predefine _FORTIFY_SOURCE at another level."""
        if self.a.target.startswith('windows'):return []
        policy=tomllib.loads((ROOT/'policy/native-c.toml').read_text(encoding='utf-8'))
        table=policy['macos'] if self.a.target.startswith('macos') else policy['c']
        flags=[f for f in table['sanitize' if self.a.sanitize else 'hardening'] if f.startswith(('-fstack-','-ftrivial-','-D_FORTIFY_SOURCE'))]
        fortify=['-U_FORTIFY_SOURCE'] if any(f.startswith('-D_FORTIFY_SOURCE') for f in flags) else []
        return fortify+flags+['-ffunction-sections','-fdata-sections']

    def system_provider(self,name):
        if 'frameworks' in self.rows[name]:return self.sdk_provider(name)
        row=self.rows[name];modules=row['pkg_config_modules'];tool=self.a.pkg_config
        # The system SDK, not the Flint prefix, provides these libraries.
        env=dict(self.env)
        for key in ('PKG_CONFIG_PATH','PKG_CONFIG_LIBDIR'):
            if key in os.environ:env[key]=os.environ[key]
            else:env.pop(key,None)
        def query(*args):
            self.plan.append({'argv':[tool,*args],'cwd':str(ROOT)})
            if self.a.phase!='build':return ''
            result=subprocess.run([tool,*args],env=env,text=True,capture_output=True)
            if result.returncode:raise RuntimeError(name+' system SDK query failed: '+' '.join(args)+'\n'+result.stderr[-4000:])
            return result.stdout.strip()
        versions={module:query('--modversion',module) for module in modules}
        libs=query('--libs',*modules)
        if self.a.phase!='build':return
        for module,minimum in modules.items():
            if version_key(versions[module])<version_key(minimum):raise RuntimeError(module+' '+versions[module]+' is older than the locked minimum '+minimum)
        pc_files=[]
        for module in modules:
            path=Path(query('--variable=pcfiledir',module))/(module+'.pc')
            pc_files.append({'module':module,'path':str(path),'sha256':digest(path)})
        flags=[];directories=[]
        for token in shlex.split(libs):
            if token=='-pthread':token='-lpthread'
            if token.startswith('-L'):directories.append(token[2:])
            if token.endswith('.a') or token=='-static':raise RuntimeError(name+' must link dynamically; pkg-config selected '+token)
            if token not in flags:flags.append(token)
        for directory in directories:
            if directory not in STANDARD_LIBRARY_DIRS:flags.append('-rpath='+directory)
        metadata=self.work/'build'/self.a.target/name/'system-link.json'
        self.write(metadata,json.dumps({'modules':versions,'flags':flags},indent=2)+'\n')
        self.link_metadata[name]={'path':str(metadata),'sha256':digest(metadata),'flags':flags}
        self.receipt['libraries'][name]={'kind':'system','license':row['license_selected'],'linking':row['linking'],
            'modules':versions,'pkg_config_files':pc_files,'archives':[],'requested_sanitizers':self.a.sanitize,
            'system_link_metadata':self.link_metadata[name]}
        self.prefix.mkdir(parents=True,exist_ok=True);self.receipt_path.write_text(json.dumps(self.receipt,indent=2)+'\n')

    def sdk_provider(self,name):
        """Record an Apple framework provider: the SDK and the SHA256 of each framework's linker stub."""
        row=self.rows[name];argv=['xcrun','--show-sdk-path']
        self.plan.append({'argv':argv,'cwd':str(ROOT)})
        if self.a.phase!='build':return
        sdk=Path(subprocess.run(argv,check=True,text=True,capture_output=True).stdout.strip())
        stubs=[];flags=[]
        for framework in row['frameworks']:
            stub=sdk/'System/Library/Frameworks'/(framework+'.framework')/(framework+'.tbd')
            if not stub.is_file():raise RuntimeError(name+' needs '+framework+'.framework in the macOS SDK: '+str(stub))
            stubs.append({'framework':framework,'path':str(stub),'sha256':digest(stub)})
            flags.append('-Wl,-framework,'+framework)
        flags+=row.get('system_libraries',[])
        metadata=self.work/'build'/self.a.target/name/'system-link.json'
        self.write(metadata,json.dumps({'sdk':str(sdk),'frameworks':row['frameworks'],'flags':flags},indent=2)+'\n')
        self.link_metadata[name]={'path':str(metadata),'sha256':digest(metadata),'flags':flags}
        self.receipt['libraries'][name]={'kind':'system','license':row['license_selected'],'linking':row['linking'],
            'sdk':str(sdk),'sdk_files':stubs,'archives':[],'requested_sanitizers':self.a.sanitize,
            'system_link_metadata':self.link_metadata[name]}
        self.prefix.mkdir(parents=True,exist_ok=True);self.receipt_path.write_text(json.dumps(self.receipt,indent=2)+'\n')

    def archive_paths(self,name):
        files=[p for p in self.prefix.rglob('*') if p.suffix in ('.a','.lib') and not p.name.endswith('.dll.a')]
        found=[]
        for aliases in ALIASES[name]:
            matches=[p for p in files if p.stem in aliases or (p.stem.startswith('lib') and p.stem[3:] in aliases)]
            if not matches:raise RuntimeError('Missing static archive for '+name+': '+repr(aliases))
            hashes={digest(p) for p in matches}
            if len(hashes)>1:raise RuntimeError('Ambiguous different static archives for '+name+': '+repr(matches))
            found.append(sorted(matches,key=lambda p:(len(p.parts),str(p)))[0])
        return found

    def normalize_link_flags(self,tokens):
        result=[];index=0
        while index<len(tokens):
            token=tokens[index];index+=1
            if token in ('-framework','-weak_framework'):
                if index==len(tokens):raise ValueError('Missing framework name')
                result.append('-Wl,'+token+','+tokens[index]);index+=1
            elif self.a.target.startswith('windows') and token.startswith('-l'):
                result.append(token[2:]+'.lib')
            elif token not in result:result.append(token)
        return result

    def sdl_link_metadata(self):
        paths=list(self.prefix.rglob('sdl3.pc'))
        if len(paths)!=1:raise RuntimeError('Expected exactly one installed sdl3.pc')
        path=paths[0];variables={};fields={}
        for line in path.read_text().replace('\\\n',' ').splitlines():
            line=line.strip()
            if not line or line.startswith('#'):continue
            if re.match(r'[A-Za-z_][A-Za-z_0-9]*=',line):
                key,value=line.split('=',1);variables[key]=value
            elif ':' in line:
                key,value=line.split(':',1);fields[key]=value.strip()
        for key in ('Requires','Requires.private'):
            if fields.get(key):raise RuntimeError('SDL selected an unmanaged external dependency: '+fields[key])
        text=fields.get('Libs','')+' '+fields.get('Libs.private','')
        text=text.replace('-L${libdir}','')
        for _ in range(16):
            expanded=re.sub(r'\$\{([^}]+)\}',lambda m:variables.get(m[1],m[0]),text)
            if expanded==text:break
            text=expanded
        if '${' in text:raise RuntimeError('Unexpanded SDL pkg-config variable')
        tokens=shlex.split(text);flags=[]
        for token in tokens:
            if token.startswith('-L') or token in ('-lSDL3','-lSDL3-static'):continue
            flags.append(token)
        flags=self.normalize_link_flags(flags)
        return {'path':str(path),'sha256':digest(path),'flags':flags}

    def record(self,name):
        row=self.rows[name];paths=self.archive_paths(name)
        self.receipt['libraries'][name]={'source_sha256':row['archive_sha256'],'revision':row.get('commit',row.get('source_id')),'license':row['license_selected'],'requested_sanitizers':self.a.sanitize,'archives':[{'path':str(p),'sha256':digest(p)} for p in paths]}
        if self.sanitizer_exclusions(name):self.receipt['libraries'][name]['sanitizer_exclusions']=list(self.sanitizer_exclusions(name))
        if name=='openssl':self.receipt['libraries'][name]['configure_disabled']=list(OPENSSL_TLS_ONLY)
        if name=='sdl3':self.link_metadata[name]=self.sdl_link_metadata()
        if name == 'curl' and (self.a.target.startswith('linux') or self.a.target == 'macos-arm64'):
            config = self.prefix / 'bin/curl-config'
            protocols = sorted(self.command([config, '--protocols'], ROOT).split())
            smtp = self.a.profile in ('mail', 'ci', 'all')
            expected = {'HTTP', 'HTTPS', 'WS', 'WSS'} | ({'SMTP', 'SMTPS'} if smtp else set())
            if set(protocols) != expected:
                raise RuntimeError('Unexpected pinned curl protocol set: ' + repr(protocols))
            self.receipt['libraries'][name].update(
                protocols=protocols, provider_profile='smtp-http' if smtp else 'http-only',
                curl_config_sha256=digest(config))
        if name in self.link_metadata:self.receipt['libraries'][name]['system_link_metadata']=self.link_metadata[name]
        if name in self.toolchain_metadata:self.receipt['libraries'][name]['toolchain']=self.toolchain_metadata[name]
        self.prefix.mkdir(parents=True,exist_ok=True);self.receipt_path.write_text(json.dumps(self.receipt,indent=2)+'\n')

    def shims(self):
        # flint_ffi_base first: the engines' project links its tests against the installed archive.
        for name,source in (('flint-ffi',flint_checkout()/'native/ffi'),('flint-ffi-framework',framework_shims())):
            build=self.work/'build'/self.a.target/name
            self.cmake(name,source,build,'.',[])
            if host_target()==self.a.target:self.command(['ctest','--test-dir',build,'--output-on-failure'],ROOT)
        if self.a.phase=='build':
            self.receipt['native_ctest_executed']=host_target()==self.a.target
            self.receipt['sanitizers']=self.a.sanitize
            self.receipt['sanitizer_scope']='Flint C shims and libraries whose requested_sanitizers field is non-null, minus each library\'s sanitizer_exclusions. Flint C shims have no exclusions. Separately prepared Rust archives are not instrumented by this helper.'
            if self.a.sanitize:self.receipt['vendor_ubsan_exclusions']={k:list(v) for k,v in VENDOR_UBSAN_EXCLUSIONS.items() if k in self.receipt['libraries']}
            else:self.receipt.pop('vendor_ubsan_exclusions',None)
            self.receipt['sanitizer_environment']={k:self.env[k] for k in ('ASAN_OPTIONS','UBSAN_OPTIONS','LSAN_OPTIONS') if k in self.env}
            self.receipt.pop('ffi_archive',None)
            self.receipt['ffi_archives']={}
            for part,names in FFI_ARCHIVES.items():
                paths=[p for p in self.prefix.rglob('*') if p.name in names]
                if len(paths)!=1:raise RuntimeError('Expected exactly one Flint FFI archive '+names[0])
                self.receipt['ffi_archives'][part]={'path':str(paths[0]),'sha256':digest(paths[0])}
            if 'protobuf-c' in self.receipt['libraries']:
                self.receipt['rpc_test_archive'] = self.rpc_test_archive_receipt()
            if (self.a.target.startswith('linux') or self.a.target == 'macos-arm64') and 'wasmtime' in self.receipt['libraries']:
                self.receipt['wasi_reference_archive'] = self.wasi_reference_archive_receipt()
            else:
                self.receipt.pop('wasi_reference_archive', None)
            curl = self.receipt['libraries'].get('curl', {})
            if curl.get('provider_profile') == 'smtp-http':
                reference = self.prefix / 'lib/libflint_mail_reference.a'
                self.receipt['mail_reference_archive'] = {'path': str(reference), 'sha256': digest(reference)}
            else:
                self.receipt.pop('mail_reference_archive', None)
            self.receipt_path.write_text(json.dumps(self.receipt,indent=2)+'\n')

    def wasi_reference_archive_receipt(self):
        path = self.prefix / 'lib/libflint_wasi_reference.a'
        if not path.is_file():
            raise RuntimeError('Missing installed WASI reference archive; rebuild the native shims')
        return {'path': str(path), 'sha256': digest(path)}

    def rpc_test_archive_receipt(self):
        names = ('libflint_rpc_fixture.a', 'flint_rpc_fixture.lib')
        paths = [self.prefix / 'lib' / name for name in names if (self.prefix / 'lib' / name).is_file()]
        if len(paths) != 1:
            raise RuntimeError('Expected exactly one installed RPC test fixture archive')
        return {'path': str(paths[0]), 'sha256': digest(paths[0])}

    def rpc_fixture_flag(self):
        fixture = self.receipt.get('rpc_test_archive')
        if not fixture or fixture != self.rpc_test_archive_receipt():
            raise RuntimeError('Installed RPC test fixture archive changed')
        return self.link_line(fixture['path'])

    def link_line(self, item):
        """One DUB link input. On Windows an archive is `libs`: DUB concatenates the lflags of every path through a
        dependency graph and keeps the repeats, which outgrew link.exe's 128 KiB response-file line (LNK1170) for an
        application with dozens of packages. DUB keeps `libs` unique (ADR-026)."""
        platform = ' platform=' + json.dumps(self.dub_platform()) + '\n'
        if self.a.target.startswith('windows') and item.lower().endswith('.lib'):
            return 'libs ' + json.dumps(item[:-len('.lib')]) + platform
        return 'lflags ' + json.dumps(item) + platform

    def emit_rpc_test_archive(self, text):
        begin = '    // BEGIN FLINT RPC TEST NATIVE\n'
        end = '    // END FLINT RPC TEST NATIVE\n'
        cleaned = re.sub(re.escape(begin) + r'.*?' + re.escape(end), '', text, flags=re.S)
        if 'protobuf-c' not in self.receipt['libraries']:
            return cleaned
        anchor = 'configuration "unittest" {\n'
        if cleaned.count(anchor) != 1:
            raise RuntimeError('Expected exactly one RPC unittest configuration')
        flag = '    ' + self.rpc_fixture_flag()
        return cleaned.replace(anchor, anchor + begin + flag + end)

    def dub_platform(self):
        return {
            'linux-x86_64-glibc': 'linux-x86_64', 'linux-x86_64-musl': 'linux-x86_64',
            'linux-aarch64-glibc': 'linux-aarch64', 'linux-aarch64-musl': 'linux-aarch64',
            'macos-arm64': 'osx-aarch64', 'windows-x86_64': 'windows-x86_64',
        }[self.a.target]

    def dub_blocks(self):
        """Return deterministic, verified provider/linker blocks without mutating files."""
        blocks={}
        packages=json.loads((ROOT/'policy/packages.json').read_text())['packages'];available=set(self.receipt['libraries'])
        tag=self.dub_platform()
        for package in packages:
            direct=sorted(n for n in available if package in self.rows[n]['consumers'])
            if not direct:continue
            closure=dependency_order(direct,self.rows,False);flags=[]
            if package == 'engine-mail':
                reference = self.receipt.get('mail_reference_archive')
                if reference:
                    if digest(Path(reference['path'])) != reference['sha256']:
                        raise RuntimeError('Installed mail reference archive changed')
                    flags.append(reference['path'])
            for part in ffi_archives_for(packages[package].get('repo','flint')):
                ffi=self.receipt['ffi_archives'][part]
                if digest(Path(ffi['path']))!=ffi['sha256']:raise RuntimeError('Installed Flint FFI archive changed: '+ffi['path'])
                flags.append(ffi['path'])
            for name in reversed(closure):
                for item in self.receipt['libraries'][name]['archives']:
                    if digest(Path(item['path']))!=item['sha256']:raise RuntimeError('Installed archive changed: '+item['path'])
                    flags.append(item['path'])
            for name in reversed(closure):
                metadata=self.receipt['libraries'][name].get('system_link_metadata')
                if name in ('sdl3','wasmtime','wgpu-native','webkitgtk','wkwebview') and not metadata:raise RuntimeError('Rebuild '+name+' to capture configured static system linker dependencies')
                if name in SYSTEM:
                    recorded=self.receipt['libraries'][name]
                    for item in recorded.get('pkg_config_files',[])+recorded.get('sdk_files',[]):
                        if digest(Path(item['path']))!=item['sha256']:raise RuntimeError('System SDK changed since it was recorded: '+item['path'])
                if metadata:
                    if digest(Path(metadata['path']))!=metadata['sha256']:raise RuntimeError('Installed system linker metadata changed')
                    flags+=metadata['flags']
            if self.a.target.startswith('linux'):
                # DUB passes lflags to the linker. -pthread is a compiler-driver option.
                flags=['-lpthread' if flag=='-pthread' else flag for flag in flags]
                flags+=['-lpthread','-ldl','-lm']
            # secur32: libpq's SSPI; xmllite: libarchive's XAR writer; iphlpapi: curl's interface lookups; user32: static
            # libcrypto's MessageBoxW and GetProcessWindowStation, which LDC links by default and DMD does not (ADR-026).
            elif self.a.target.startswith('windows'):flags+=['ws2_32.lib','advapi32.lib','crypt32.lib','bcrypt.lib','userenv.lib','ntdll.lib','shell32.lib','ole32.lib','secur32.lib','xmllite.lib','iphlpapi.lib','user32.lib']
            else:
                flags+=['-Wl,-framework,Security','-Wl,-framework,CoreFoundation']
                if 'curl' in closure:flags+=['-Wl,-framework,SystemConfiguration']  # proxy settings (curl macos.c)
                if 'webview' in closure:flags+=['-Wl,-framework,WebKit','-lc++','-lobjc']
            # SDL double-quoted string escapes are JSON-compatible for these paths.
            versions=['FlintNative'+''.join(part[:1].upper()+part[1:] for part in n.split('-')) for n in sorted(direct)]
            block='\n// BEGIN FLINT NATIVE\n'+'\n'.join('versions '+json.dumps(v)+' platform='+json.dumps(tag) for v in versions)+'\n'+'\n'.join(self.link_line(x).rstrip('\n') for x in flags)+'\n// END FLINT NATIVE\n'
            blocks[package]=block
        return blocks

    def dub_recipe_blocks(self):
        """Return exact generated blocks by repository-relative recipe path."""
        recipes = {}
        for package, block in self.dub_blocks().items():
            root = 'packages/' + package
            recipes[root + '/dub.sdl'] = block
            if package == 'engine-rpc':
                # Both executables call fixture symbols. Place the fixture before
                # the provider archives for single-pass static linkers.
                block = before_first_link_line(block, self.rpc_fixture_flag())
                recipes[root + '/bench/dub.sdl'] = block
            if package == 'engine-wasi' and (self.a.target.startswith('linux') or self.a.target == 'macos-arm64') and 'wasmtime' in self.receipt['libraries']:
                reference = self.receipt.get('wasi_reference_archive')
                if not reference or reference != self.wasi_reference_archive_receipt():
                    raise RuntimeError('Installed WASI reference archive changed; rebuild the native shims')
                block = before_first_link_line(block, self.link_line(reference['path']))
            recipes[root + '/bench/baseline/dub.sdl'] = block
        return recipes

    def emit_dub(self):
        if self.a.phase != 'build':
            self.plan.append({'emit_dub': 'verified installed archives only'})
            return
        for relative, block in self.dub_recipe_blocks().items():
            # packages/<name>/... lives in the checkout of the package's repo.
            package = relative.split('/')[1]
            path = package_path(package) / '/'.join(relative.split('/')[2:])
            text = re.sub(r'\n// BEGIN FLINT NATIVE\n.*?// END FLINT NATIVE\n', '\n', path.read_text(), flags=re.S)
            if relative == 'packages/engine-rpc/dub.sdl':
                text = self.emit_rpc_test_archive(text)
            path.write_text(text.rstrip() + '\n' + block)

def before_first_link_line(block, line):
    """`line` inserted before the block's first link input, where a single-pass static linker needs it."""
    found = re.search(r'\n(?:lflags|libs) ', block)
    return block if found is None else block[:found.start() + 1] + line + block[found.start() + 1:]

def version_key(text):
    return tuple(int(part) for part in re.findall(r'[0-9]+',text)[:4])

def dependency_order(names,rows,codegen):
    result=[];visiting=set();done=set()
    def visit(name):
        if name in done:return
        if name in visiting:raise ValueError('Cycle in native lock')
        if name not in rows:raise ValueError('Unknown library: '+name)
        visiting.add(name)
        deps=list(rows[name]['dependencies'])
        if name=='protobuf-c' and codegen:deps.append('protoc')
        for dep in deps:visit(dep)
        visiting.remove(name);done.add(name);result.append(name)
    for name in names:visit(name)
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lock',default=str(ROOT/'policy/native-lock.json'));parser.add_argument('--profile',choices=list(PROFILES)+['all'])
    parser.add_argument('--library',action='append',default=[]);parser.add_argument('--target',choices=TARGETS,required=True)
    parser.add_argument('--phase',choices=('plan','fetch','build'),default='plan');parser.add_argument('--work-dir',default=str(ROOT/'.native'));parser.add_argument('--prefix')
    parser.add_argument('--jobs',type=int,default=min(os.cpu_count() or 2,8));parser.add_argument('--cc');parser.add_argument('--cxx');parser.add_argument('--cmake-toolchain')
    parser.add_argument('--sanitize',choices=('address','undefined','address,undefined'))
    # The Conan recipe index (native/conan-index, ADR-023) builds one library per Conan package with its
    # dependencies' packages already merged into --prefix, and the Flint shims once over the deployed closure.
    parser.add_argument('--no-dependencies',action='store_true',help='Build only the --library names; their dependencies are already in --prefix. --profile then only selects provider variants such as curl SMTP')
    parser.add_argument('--no-shims',action='store_true',help='Do not build the Flint C shims (native/ffi)')
    parser.add_argument('--shims-only',action='store_true',help='Build only the Flint C shims (and --emit-dub) over the libraries the prefix receipt records')
    parser.add_argument('--workspace',type=Path,help='flint.workspace/1 file pinning each repo\'s checkout (plan section 7): native/ffi comes from the flint checkout, and --emit-dub writes each package\'s recipe in its own checkout')
    parser.add_argument('--with-codegen',action='store_true');parser.add_argument('--emit-dub',action='store_true');parser.add_argument('--allow-webview',action='store_true');parser.add_argument('--pkg-config',default=os.environ.get('PKG_CONFIG','pkg-config'),help='pkg-config for dynamic system providers such as WebKitGTK')
    args=parser.parse_args()
    if args.jobs<1:parser.error('--jobs must be positive')
    global WORKSPACE
    WORKSPACE=Workspace(args.workspace)
    problems=WORKSPACE.verify()
    if problems:parser.error('workspace: '+'; '.join(problems))
    lock=json.loads(Path(args.lock).read_text());builder=Builder(args,lock)
    names=list(args.library)
    if args.shims_only or args.no_dependencies:
        if args.shims_only and names:parser.error('--shims-only builds no libraries')
        if args.no_dependencies and not names:parser.error('--no-dependencies needs --library')
        if args.phase=='build' and host_target()!=args.target and not args.cmake_toolchain:parser.error('Use a native target runner or an explicit CMake cross toolchain')
        for name in names:builder.build(name)
        if args.phase!='fetch' and not args.no_shims:
            builder.shims()
            if args.emit_dub:builder.emit_dub()
        print(json.dumps({'phase':args.phase,'target':args.target,'prefix':str(builder.prefix),'receipt':str(builder.receipt_path) if args.phase=='build' else None}))
        return
    if args.profile=='all':names += [n for n in builder.rows if n not in ('webview','protoc') and (n not in ('liburing','webkitgtk') or args.target.startswith('linux')) and (n!='wkwebview' or args.target=='macos-arm64')]
    elif args.profile:names += PROFILES[args.profile]
    # The desktop profile's system webview is WKWebView on macOS (ADR-020, ADR-024).
    if args.target=='macos-arm64':names=['wkwebview' if n=='webkitgtk' else n for n in names]
    if args.profile in ('rest','http','sql','mq') and args.target.startswith('linux'):names.append('liburing')
    if not names:parser.error('Select --profile or --library')
    if args.target.startswith('linux'):
        packages=json.loads((ROOT/'policy/packages.json').read_text())['packages']
        def needs_reactor(package, seen=None):
            seen=set() if seen is None else seen
            if package=='engine-reactor':return True
            if package in seen or package not in packages:return False
            seen.add(package)
            return any(needs_reactor(dep,seen) for dep in packages[package]['dependencies'])
        if any(needs_reactor(consumer) for name in names if name in builder.rows for consumer in builder.rows[name]['consumers']):
            names.append('liburing')
    if args.phase=='build' and host_target()!=args.target and not args.cmake_toolchain:parser.error('Use a native target runner or an explicit CMake cross toolchain')
    for name in dependency_order(names,builder.rows,args.with_codegen):builder.build(name)
    if args.phase!='fetch' and not args.no_shims:
        builder.shims()
        if args.emit_dub:builder.emit_dub()
    if args.phase=='plan':print(json.dumps({'target':args.target,'host':host_target(),'phase':'plan-only','prefix':str(builder.prefix),'steps':builder.plan},indent=2))
    else:print(json.dumps({'phase':args.phase,'target':args.target,'prefix':str(builder.prefix),'receipt':str(builder.receipt_path) if args.phase=='build' else None}))

if __name__=='__main__':
    try:main()
    except (ValueError,RuntimeError,OSError) as error:print(str(error),file=sys.stderr);sys.exit(1)
