#!/usr/bin/env python3
"""What Flint's TLS negotiates with each OpenSSL build, probe by probe (ADR-031).

AGENTS.md forbids changing the TLS profile to win a measurement. This tool shows that a smaller OpenSSL
build negotiates exactly what the full one did. tools/tls_matrix/tls_matrix.c is compiled against each
OpenSSL install named with --openssl LABEL=PREFIX, and against the --reference install. Two matrices
are recorded:

server   Flint's TLS server profile (native/ffi/flint_web_tls.c, unmodified), linked with each build,
         with an RSA and an ECDSA certificate. A reference client probes it one setting at a time:
         each protocol version, every TLS 1.2 cipher the reference knows, each TLS 1.3 suite, each
         group and each signature algorithm, under TLS 1.2 and TLS 1.3, and ALPN.
client   Each build as a client with OpenSSL's defaults, which is how curl, libpq and librdkafka use it,
         restricted one setting at a time against a reference server that accepts everything.

Each probe records the outcome and the negotiated version, cipher, group, peer signature and ALPN.
The tool prints every probe whose result differs between the first two builds, and exits 1 if any
does. The JSON output keeps every row.

    python3 tools/tls_profile_matrix.py --reference /path/full --openssl full=/path/full \\
        --openssl tls-only=.native/install/linux-x86_64-glibc --output tls-matrix.json
"""
from __future__ import annotations

import argparse
import json
import socket
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tools/tls_matrix/tls_matrix.c'
VERSIONS = ['TLSv1', 'TLSv1.1', 'TLSv1.2', 'TLSv1.3']
SUITES = ['TLS_AES_256_GCM_SHA384', 'TLS_CHACHA20_POLY1305_SHA256', 'TLS_AES_128_GCM_SHA256',
          'TLS_AES_128_CCM_SHA256', 'TLS_AES_128_CCM_8_SHA256']
GROUPS = ['X25519MLKEM768', 'SecP256r1MLKEM768', 'SecP384r1MLKEM1024', 'X25519', 'X448', 'secp256r1',
          'secp384r1', 'secp521r1', 'brainpoolP256r1tls13', 'brainpoolP384r1tls13', 'brainpoolP512r1tls13',
          'ffdhe2048', 'ffdhe3072', 'ffdhe4096', 'ffdhe6144', 'ffdhe8192', 'MLKEM512', 'MLKEM768', 'MLKEM1024',
          'brainpoolP256r1', 'brainpoolP384r1', 'brainpoolP512r1']
SIGALGS = ['rsa_pss_rsae_sha256', 'rsa_pss_rsae_sha384', 'rsa_pss_rsae_sha512', 'rsa_pss_pss_sha256',
           'rsa_pss_pss_sha384', 'rsa_pss_pss_sha512', 'rsa_pkcs1_sha256', 'rsa_pkcs1_sha384', 'rsa_pkcs1_sha512',
           'rsa_pkcs1_sha1', 'ecdsa_secp256r1_sha256', 'ecdsa_secp384r1_sha384', 'ecdsa_secp521r1_sha512',
           'ecdsa_sha1', 'ed25519', 'ed448', 'ecdsa_brainpoolP256r1tls13_sha256',
           'ecdsa_brainpoolP384r1tls13_sha384', 'ecdsa_brainpoolP512r1tls13_sha512', 'mldsa44', 'mldsa65',
           'mldsa87', 'RSA+SHA224', 'ECDSA+SHA224', 'DSA+SHA256', 'DSA+SHA1']
ALPN = ['h2', 'http/1.1', 'h2,http/1.1', 'spdy/3']


def build(prefix, output, clang):
    prefix = Path(prefix)
    command = [clang, '-O1', '-std=c17', '-DFLINT_HAS_OPENSSL', '-I' + str(prefix / 'include'),
               '-I' + str(ROOT / 'native/ffi'), str(SOURCE), str(ROOT / 'native/ffi/flint_web_tls.c'),
               str(prefix / 'lib/libssl.a'), str(prefix / 'lib/libcrypto.a'), '-lpthread', '-ldl', '-o', str(output)]
    subprocess.run(command, check=True)
    return output


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def serve(command):
    process = subprocess.Popen(command, stdout=subprocess.PIPE, text=True)
    if process.stdout.readline().strip() != 'ready':
        process.kill()
        raise SystemExit('server did not start: ' + ' '.join(map(str, command)))
    return process


def probe(binary, port, probes):
    result = subprocess.run([str(binary), 'probe', str(port), str(probes)], capture_output=True, text=True, check=True)
    return [json.loads(line) for line in result.stdout.splitlines()]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--reference', required=True, help='full OpenSSL install: the probing client and accept-all server')
    parser.add_argument('--openssl', action='append', required=True, help='LABEL=PREFIX of an OpenSSL install to compare')
    parser.add_argument('--clang', default=str(ROOT.parent / '.tools/LLVM-22.1.8-Linux-X64/bin/clang'))
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    builds = dict(item.split('=', 1) for item in args.openssl)
    with tempfile.TemporaryDirectory(prefix='flint-tls-matrix-') as temporary:
        directory = Path(temporary)
        reference = build(args.reference, directory / 'reference', args.clang)
        binaries = {label: build(prefix, directory / ('build-' + label), args.clang) for label, prefix in builds.items()}
        certificates = directory / 'certificates'
        certificates.mkdir()
        subprocess.run([str(reference), 'gencert', str(certificates)], check=True)
        ciphers = subprocess.run([str(reference), 'ciphers'], capture_output=True, text=True, check=True).stdout.split()
        lines = ['default -'] + ['version ' + v for v in VERSIONS] + ['cipher12 ' + c for c in ciphers]
        lines += ['suite13 ' + s for s in SUITES]
        lines += [kind + ' ' + g for kind in ('group12', 'group13') for g in GROUPS]
        lines += [kind + ' ' + a for kind in ('sigalg12', 'sigalg13') for a in SIGALGS]
        lines += ['alpn ' + a for a in ALPN]
        probes = directory / 'probes.txt'
        probes.write_text('\n'.join(lines) + '\n')
        result = {'schema': 1, 'producer': 'tools/tls_profile_matrix.py', 'reference': str(args.reference),
                  'builds': builds, 'probes': len(lines), 'server': {}, 'client': {}}
        for label, binary in binaries.items():
            result['server'][label] = {}
            for name in ('rsa', 'ec'):
                port = free_port()
                server = serve([str(binary), 'serve-flint', str(port), str(certificates / (name + '.pem')),
                                str(certificates / (name + '.key'))])
                try:
                    result['server'][label][name] = probe(reference, port, probes)
                finally:
                    server.kill()
        port = free_port()
        server = serve([str(reference), 'serve-all', str(port), str(certificates)])
        try:
            for label, binary in binaries.items():
                result['client'][label] = probe(binary, port, probes)
        finally:
            server.kill()
    labels = list(builds)
    differences = []
    if len(labels) >= 2:
        first, second = labels[:2]
        pairs = [('server ' + name, result['server'][first][name], result['server'][second][name]) for name in ('rsa', 'ec')]
        pairs.append(('client', result['client'][first], result['client'][second]))
        for where, left, right in pairs:
            for a, b in zip(left, right):
                if a != b:
                    differences.append({'matrix': where, 'probe': a['kind'] + ' ' + a['value'], first: a, second: b})
    result['differences'] = differences
    summary = {where: sum(1 for row in rows if row['outcome'] == 'ok')
               for where, rows in [('server rsa', result['server'][labels[0]]['rsa']),
                                   ('server ec', result['server'][labels[0]]['ec']),
                                   ('client', result['client'][labels[0]])]}
    result['negotiated_' + labels[0]] = summary
    args.output.write_text(json.dumps(result, indent=1) + '\n')
    print(json.dumps({'probes': len(lines), 'negotiated_' + labels[0]: summary, 'differences': len(differences)}))
    for difference in differences:
        print(difference['matrix'], difference['probe'], ':',
              {k: v for k, v in difference[labels[0]].items() if k not in ('kind', 'value')}, '->',
              {k: v for k, v in difference[labels[1]].items() if k not in ('kind', 'value')})
    return 1 if differences else 0


if __name__ == '__main__':
    sys.exit(main())
