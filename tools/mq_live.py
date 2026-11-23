#!/usr/bin/env python3
"""Run flint:mq's live scenarios against real, pinned brokers (policy/peer-lock.json).

Starts a single-node KRaft Apache Kafka on the pinned JRE and NATS JetStream, plain and with TLS
from a throwaway CA. Builds the scenario programs in packages/mq/fixtures, the D ones with DUB
against flint:mq and the C ones against native/ffi/flint_mq.c and the pinned librdkafka. Then runs:

  kafka          receipts, local redelivery with a fresh token, processing and confirmed drain
  kafka_state    a real rebalance revokes a held delivery; the stale acknowledgement is rejected
  receipts       provider rejection and native delivery timeout each retire one token
  drain          caller deadlines keep ambiguous native ownership until the worker joins
  outage         a full producer stays capped while the broker is unreachable (--outage-seconds)
  jetstream      deduplication, lost-ack redelivery, idempotent dispatch, AckSync and dead letters,
                 verified broker-side by check_jetstream.py, over loopback and verified TLS

Prints one line per scenario and a JSON summary; exits nonzero when any scenario fails.
"""
import argparse
import contextlib
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'packages' / 'mq' / 'fixtures'
TOPICS = ('flint-live', 'flint-rebalance', 'flint-orders')
# Darwin has no librt; its static OpenSSL needs the Security and CoreFoundation frameworks (ADR-024).
SYSTEM_LIBRARIES = (('-lpthread', '-lm', '-framework', 'Security', '-framework', 'CoreFoundation')
                    if sys.platform == 'darwin' else ('-lpthread', '-ldl', '-lm', '-lrt'))


def free_port():
    with contextlib.closing(socket.socket()) as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


def wait_port(port, process, seconds, what):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise SystemExit(what + ' exited before it listened')
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    raise SystemExit(what + ' did not listen within ' + str(seconds) + ' s')


def stop(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def build_d(args, work, name, files, versions=(), lflags=()):
    project = work / ('build-' + name)
    project.mkdir()
    recipe = ['name "mq-' + name + '"', 'targetType "executable"', 'targetPath "."',
              'importPaths "' + str(FIXTURES) + '"', 'dflags "-preview=dip1000"',
              'dependency "flint:mq" path="' + str(ROOT) + '"']
    recipe += ['sourceFiles "' + str(FIXTURES / file) + '"' for file in files]
    recipe += ['versions "' + version + '"' for version in versions]
    recipe += ['lflags "' + flag + '"' for flag in lflags]
    (project / 'dub.sdl').write_text('\n'.join(recipe) + '\n')
    env = dict(os.environ, DUB_HOME=str(ROOT / '.flint' / 'dub' / 'dmd'))
    env.pop('DFLAGS', None)
    if sys.platform == 'darwin':
        # DUB treats ldmd2 as DMD; its pipeline's archives are ELF-style until the Darwin archiver lands (ADR-024).
        env['FLINT_DUB_PIPELINE'] = '0'
    subprocess.run([args.dub, 'build', '--root=' + str(project), '--compiler=' + args.dmd, '--build=debug',
                    '--skip-registry=all'], env=env, check=True, stdout=subprocess.DEVNULL)
    return project / ('mq-' + name)


def build_c(args, work, name):
    prefix = Path(args.prefix)
    output = work / ('mq-' + name)
    source = FIXTURES / (name + '.c')
    # Scenarios that include flint_mq.c compile the shim themselves; the others link the installed one.
    shim = [] if '#include "flint_mq.c"' in source.read_text() else ['libflint_ffi.a']
    libraries = [str(prefix / 'lib' / library) for library in
                 (*shim, 'librdkafka.a', 'libzstd.a', 'libz.a', 'libssl.a', 'libcrypto.a')]
    darwin = ['-D_DARWIN_C_SOURCE'] if sys.platform == 'darwin' else []  # as native/ffi/CMakeLists.txt
    subprocess.run([args.cc, '-std=c11', '-g', '-O1', '-D_GNU_SOURCE', *darwin, '-DFLINT_HAS_LIBRDKAFKA', '-I' + str(ROOT / 'native' / 'ffi'),
                    '-I' + str(prefix / 'include'), str(source), '-o', str(output), *libraries,
                    *SYSTEM_LIBRARIES], check=True)
    return output


def start_kafka(args, work):
    home, java = Path(args.kafka), Path(args.java_home)
    directory = work / 'kafka'
    directory.mkdir()
    port, controller = free_port(), free_port()
    properties = directory / 'server.properties'
    properties.write_text('\n'.join([
        'process.roles=broker,controller', 'node.id=1', f'controller.quorum.voters=1@127.0.0.1:{controller}',
        f'listeners=PLAINTEXT://127.0.0.1:{port},CONTROLLER://127.0.0.1:{controller}',
        f'advertised.listeners=PLAINTEXT://127.0.0.1:{port}', 'controller.listener.names=CONTROLLER',
        'listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT',
        'inter.broker.listener.name=PLAINTEXT', f'log.dirs={directory / "data"}', 'num.partitions=1',
        'offsets.topic.replication.factor=1', 'transaction.state.log.replication.factor=1',
        'transaction.state.log.min.isr=1', 'min.insync.replicas=1', 'group.initial.rebalance.delay.ms=0',
        'auto.create.topics.enable=true']) + '\n')
    env = dict(os.environ, JAVA_HOME=str(java), PATH=str(java / 'bin') + os.pathsep + os.environ.get('PATH', ''),
               KAFKA_HEAP_OPTS='-Xms512m -Xmx512m', LOG_DIR=str(directory / 'logs'))
    cluster = str(uuid.UUID(bytes=os.urandom(16))).replace('-', '')[:22]
    cluster = subprocess.check_output([str(home / 'bin' / 'kafka-storage.sh'), 'random-uuid'], env=env,
                                      text=True).strip() or cluster
    subprocess.run([str(home / 'bin' / 'kafka-storage.sh'), 'format', '-t', cluster, '-c', str(properties)],
                   env=env, check=True, stdout=subprocess.DEVNULL)
    log = (directory / 'server.out').open('w')
    process = subprocess.Popen([str(home / 'bin' / 'kafka-server-start.sh'), str(properties)], env=env,
                               stdout=log, stderr=subprocess.STDOUT)
    wait_port(port, process, 120, 'Kafka')
    bootstrap = f'127.0.0.1:{port}'
    deadline = time.monotonic() + 120
    for topic in TOPICS:
        while True:
            created = subprocess.run([str(home / 'bin' / 'kafka-topics.sh'), '--bootstrap-server', bootstrap,
                                      '--create', '--if-not-exists', '--topic', topic, '--partitions', '1',
                                      '--replication-factor', '1'], env=env, capture_output=True, text=True)
            if created.returncode == 0:
                break
            if time.monotonic() > deadline:
                raise SystemExit('Kafka topic creation failed: ' + created.stderr[-2000:])
            time.sleep(1)
    return process, bootstrap


def certificates(work):
    directory = work / 'tls'
    directory.mkdir()
    ca, ca_key = directory / 'ca.pem', directory / 'ca.key'
    key, request, certificate = directory / 'server.key', directory / 'server.csr', directory / 'server.pem'
    extensions = directory / 'server.ext'
    extensions.write_text('subjectAltName=IP:127.0.0.1\nbasicConstraints=CA:FALSE\n'
                          'keyUsage=digitalSignature\nextendedKeyUsage=serverAuth\n')
    quiet = {'stdout': subprocess.DEVNULL, 'stderr': subprocess.DEVNULL, 'check': True}
    # Explicit CA extensions: LibreSSL's openssl (macOS) adds none by default, and Python's strict X.509
    # verification requires keyUsage on a CA (ADR-024). OpenSSL 3 already adds basicConstraints.
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256', '-nodes',
                    '-keyout', str(ca_key), '-out', str(ca), '-days', '1', '-subj', '/CN=flint-mq-test-ca',
                    '-addext', 'basicConstraints=critical,CA:TRUE', '-addext', 'keyUsage=critical,keyCertSign,cRLSign'],
                   **quiet)
    subprocess.run(['openssl', 'req', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256', '-nodes',
                    '-keyout', str(key), '-out', str(request), '-subj', '/CN=127.0.0.1'], **quiet)
    subprocess.run(['openssl', 'x509', '-req', '-in', str(request), '-CA', str(ca), '-CAkey', str(ca_key),
                    '-CAcreateserial', '-out', str(certificate), '-days', '1', '-extfile', str(extensions)], **quiet)
    return ca, certificate, key


def start_nats(args, work, name, tls=None):
    port = free_port()
    command = [args.nats, '-js', '-sd', str(work / ('nats-' + name)), '-a', '127.0.0.1', '-p', str(port)]
    if tls:
        command += ['--tls', '--tlscert', str(tls[1]), '--tlskey', str(tls[2])]
    log = (work / ('nats-' + name + '.out')).open('w')
    process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
    wait_port(port, process, 30, 'nats-server')
    return process, port


def scenario(results, name, command, timeout):
    started = time.monotonic()
    result = subprocess.run([str(part) for part in command], capture_output=True, text=True, timeout=timeout)
    seconds = round(time.monotonic() - started, 1)
    output = (result.stdout + result.stderr).strip()
    ok = result.returncode == 0
    results.append({'scenario': name, 'ok': ok, 'exit_code': result.returncode, 'seconds': seconds,
                    'output': output.splitlines()[-1] if output else ''})
    print(('passed ' if ok else 'FAILED ') + name + f' ({seconds} s): ' + (output.splitlines()[-1] if output else ''),
          flush=True)
    if not ok:
        print(output[-4000:], file=sys.stderr)


def main():
    cli = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    cli.add_argument('--kafka', required=True, help='pinned Kafka home')
    cli.add_argument('--java-home', required=True, help='pinned JRE')
    cli.add_argument('--nats', required=True, help='pinned nats-server')
    cli.add_argument('--dub', required=True)
    cli.add_argument('--dmd', required=True)
    cli.add_argument('--prefix', required=True, help='native provider install prefix')
    cli.add_argument('--cc', default='cc')
    cli.add_argument('--outage-seconds', type=int, default=30)
    args = cli.parse_args()
    results = []
    with tempfile.TemporaryDirectory(prefix='flint-mq-live-') as temporary, contextlib.ExitStack() as cleanup:
        work = Path(temporary)
        binaries = {
            'kafka': build_d(args, work, 'kafka', ['kafka.d']),
            'drain': build_d(args, work, 'drain', ['drain.d']),
            'jetstream': build_d(args, work, 'jetstream', ['jetstream.d', 'sqlite_effect.d'],
                                 versions=['FlintMqFixtureSqlite'], lflags=[str(Path(args.prefix) / 'lib' / 'libsqlite3.a')]),
            'kafka_state': build_c(args, work, 'kafka_state'),
            'receipts': build_c(args, work, 'receipts'),
            'outage': build_c(args, work, 'outage'),
        }
        unreachable = f'127.0.0.1:{free_port()}'
        kafka, bootstrap = start_kafka(args, work)
        cleanup.callback(stop, kafka)
        scenario(results, 'kafka', [binaries['kafka'], bootstrap, 'flint-live-group', 'flint-live'], 120)
        scenario(results, 'kafka_state', [binaries['kafka_state'], bootstrap, 'flint-rebalance', 'flint-rebalance-group'],
                 120)
        scenario(results, 'receipts', [binaries['receipts'], bootstrap, unreachable], 120)
        scenario(results, 'drain', [binaries['drain'], unreachable], 60)
        scenario(results, 'outage', [binaries['outage'], unreachable, str(args.outage_seconds)],
                 args.outage_seconds + 120)
        plain, port = start_nats(args, work, 'plain')
        cleanup.callback(stop, plain)
        scenario(results, 'jetstream', [sys.executable, FIXTURES / 'check_jetstream.py', binaries['jetstream'], port], 120)
        tls = certificates(work)
        secure, secure_port = start_nats(args, work, 'tls', tls)
        cleanup.callback(stop, secure)
        scenario(results, 'jetstream_tls', [sys.executable, FIXTURES / 'check_jetstream.py', binaries['jetstream'],
                                            secure_port, tls[0]], 120)
    passed = sum(1 for result in results if result['ok'])
    print(json.dumps({'schema': 'flint.mq-live/1', 'passed': passed, 'failed': len(results) - passed,
                      'outage_seconds': args.outage_seconds, 'scenarios': results}))
    return 0 if passed == len(results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
