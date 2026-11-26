"""Test package licence files, source boundaries and the migration ratchet."""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

import jdk_package_licences as licences


class JdkPackageLicenceTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)

    def write(self, path, text):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text, encoding='utf-8')

    def test_migrated_package_requires_full_licence_and_notice(self):
        check = lambda: licences.package_files('java-math', self.root, licences.GPL_CLASSPATH, True, False)
        with self.assertRaisesRegex(ValueError, 'own LICENSE'):
            check()
        self.write('LICENSE', 'GNU General Public License\nVersion 2, June 1991\n')
        with self.assertRaisesRegex(ValueError, 'Classpath Exception'):
            check()
        with (self.root / 'LICENSE').open('a', encoding='utf-8') as stream:
            stream.write('permission to link this library with independent modules')
        with self.assertRaisesRegex(ValueError, 'must carry NOTICE'):
            check()
        self.write('NOTICE', 'Flint Java Math\n')
        check()
        with self.assertRaisesRegex(ValueError, 'remove the migrated package'):
            licences.package_files('java-math', self.root, licences.GPL_CLASSPATH, True, True)
        with self.assertRaisesRegex(ValueError, 'requires a gpl-ce-module upstream'):
            licences.package_files('other', self.root, licences.GPL_CLASSPATH, False, False)

    def test_only_pending_packages_can_keep_their_existing_licence(self):
        licences.package_files('java', self.root, 'Apache-2.0', True, True)
        with self.assertRaisesRegex(ValueError, 'DUB licence must be'):
            licences.package_files('java', self.root, 'Apache-2.0', True, False)
        with self.assertRaisesRegex(ValueError, 'own LICENSE'):
            licences.package_files('jakarta-annotation', self.root, 'EPL-2.0', False, False)
        self.write('LICENSE', 'EPL terms')
        licences.package_files('jakarta-annotation', self.root, 'EPL-2.0', False, False)
        with self.assertRaisesRegex(ValueError, 'own LICENSE'):
            licences.package_files('other', self.root, 'Apache-2.0', False, False)

    def test_header_checks_include_tests_and_exclude_string_literals_and_builds(self):
        self.write('tests/example.d', f'// SPDX-License-Identifier: {licences.GPL_CLASSPATH}\nmodule example;\n')
        self.write('.flint/build/scratch.d', '// Licensed to the Apache Software Foundation\n')
        self.write('source/literal.d', 'module literal;\nenum text = "Licensed under the Apache License";\n')
        licences.check_headers(self.root, licences.GPL_CLASSPATH)
        with self.assertRaisesRegex(ValueError, r'example\.d.*matching package licence'):
            licences.check_headers(self.root, 'Apache-2.0')
        self.write('tests/older.d', '/*\n * Licensed to the Apache Software Foundation (ASF)\n */\n')
        with self.assertRaisesRegex(ValueError, r'older\.d.*Apache-licensed source'):
            licences.check_headers(self.root, licences.GPL_CLASSPATH)

    def test_epl_package_uses_the_epl_option_of_dual_licensed_source(self):
        self.write('source/annotation.d',
                   '// SPDX-License-Identifier: EPL-2.0 OR GPL-2.0 WITH Classpath-exception-2.0\n')
        licences.check_headers(self.root, 'EPL-2.0')
        with self.assertRaisesRegex(ValueError, 'matching package licence'):
            licences.check_headers(self.root, 'Apache-2.0')

    def test_pending_names_cannot_be_readded_after_licence_migration(self):
        subprocess.run(['git', 'init', '-q', self.root], check=True)

        def commit(names):
            self.write(licences.PENDING, json.dumps({'schema': 1, 'pending': names}))
            licences.git(self.root, 'add', licences.PENDING)
            licences.git(self.root, '-c', 'user.name=Test', '-c', 'user.email=test@example.test',
                         'commit', '-qm', 'Update pending list')

        eligible = {'java-math', 'java-regex'}
        commit(['java-math', 'java-regex'])
        self.assertEqual(licences.pending_at(self.root, eligible), eligible)
        commit(['java-regex'])
        self.assertEqual(licences.pending_at(self.root, eligible), {'java-regex'})
        self.write(licences.PENDING, json.dumps({'schema': 1, 'pending': sorted(eligible)}))
        with self.assertRaisesRegex(ValueError, 'working tree: java-math'):
            licences.pending_at(self.root, eligible)

    def test_policy_covers_all_java_packages_and_gpl_ce_upstreams(self):
        self.assertTrue(licences.requires_gpl('java', {}, {'openjdk'}))
        self.assertTrue(licences.requires_gpl('java-math', {'upstream': 'harmony@6.0M3'}, {'openjdk'}))
        self.assertTrue(licences.requires_gpl('other-api', {'upstream': 'example@2.0'}, {'example'}))
        self.assertFalse(licences.requires_gpl('spring-core', {'upstream': 'spring@7'}, {'openjdk'}))
