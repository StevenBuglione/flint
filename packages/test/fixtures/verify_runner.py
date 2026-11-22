#!/usr/bin/env python3
"""Link and exercise the explicit test runner using a pinned D compiler."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as xml


PACKAGE = Path(__file__).resolve().parents[1]
FIXTURES = PACKAGE / 'fixtures'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix='flint-test-runner-') as temporary:
        directory = Path(temporary)
        binary = directory / 'runner'
        subprocess.run([
            args.compiler, '-unittest', '-preview=dip1000', '-i=flint', '-I' + str(PACKAGE / 'source'),
            *(str(FIXTURES / name) for name in ('alpha.d', 'beta.d', 'run.d')), '-of=' + str(binary),
        ], check=True)

        def run(filter_text='', report='', mode='all', empty='deny-empty'):
            return subprocess.run(
                [str(binary), filter_text, str(report), mode, empty],
                capture_output=True, text=True, timeout=15,
            )

        report = directory / 'results.xml'
        result = run(report=report)
        assert result.returncode == 1, result
        assert 'seed=479' in result.stdout, result
        root = xml.parse(report).getroot()
        assert (root.attrib['tests'], root.attrib['failures'], root.attrib['errors']) == ('4', '1', '1')
        cases = root.findall('testcase')
        assert [case.attrib['classname'] for case in cases] == ['flint_runner_alpha'] * 3 + ['flint_runner_beta']
        assert cases[0].attrib['name'] == 'A&B <check> "quoted"'
        failure = cases[1].find('failure').text
        assert 'alpha.d:18: ' in failure and failure.endswith('(seed 479)'), failure
        assert 'expected "<actual>", received "x&y\\x01"' in failure, failure
        assert '(seed 479)' in cases[2].find('error').text
        assert root.find('properties/property').attrib == {'name': 'seed', 'value': '479'}
        assert 'broken & interrupted\uFFFD\tend' in cases[2].find('error').text

        original = report.read_bytes()
        assert run(filter_text='last', report=report).returncode == 3
        assert report.read_bytes() == original
        assert run(filter_text='selects nothing').returncode == 2
        assert run(filter_text='selects nothing', empty='allow-empty').returncode == 0
        assert 'tests=2 failures=1 errors=0' in run(mode='fast').stdout

        with ThreadPoolExecutor(max_workers=2) as workers:
            same = directory / 'racing.xml'
            exits = workers.map(lambda _: run(filter_text='last', report=same).returncode, range(2))
            assert sorted(exits) == [0, 3]
            assert xml.parse(same).getroot().attrib['tests'] == '1'

        with ThreadPoolExecutor(max_workers=2) as workers:
            shards = [(directory / 'shard-a.xml', 'last'), (directory / 'shard-b.xml', 'A&B')]
            exits = list(workers.map(lambda shard: run(filter_text=shard[1], report=shard[0]).returncode, shards))
            assert exits == [0, 0], exits
            names = [xml.parse(path).getroot().find('testcase').attrib['name'] for path, _ in shards]
            assert names == ['last', 'A&B <check> "quoted"'], names

        print('Runner ordering, assertion/error reporting, XML, filters, fail-fast and shard isolation passed.')


if __name__ == '__main__':
    main()
