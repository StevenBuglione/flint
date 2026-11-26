"""tools/jdk_coverage.py: matching flint.java* declarations to the OpenJDK manifest."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import jdk_coverage  # noqa: E402


def member(signature, parameters=(), type_='void', kind='method'):
    return {'kind': kind, 'name': signature.split('(')[0], 'signature': signature, 'parameters': list(parameters),
            'type': type_, 'visibility': 'public'}


class JdkCoverageTest(unittest.TestCase):
    def test_r19_names_and_modules(self):
        self.assertEqual(jdk_coverage.d_module('java.util.function'), 'flint.java.util.function_')
        self.assertEqual(jdk_coverage.d_name('version'), 'version_')
        self.assertEqual(jdk_coverage.d_name('get'), 'get')

    def test_parameters_must_fit_and_file_line_defaults_do_not_count(self):
        ctor = {'kind': 'constructor', 'parameters': [
            {'name': 'message', 'deco': 'Aya'}, {'name': 'cause', 'deco': 'C6object9Throwable', 'default': 'null'},
            {'name': 'file', 'deco': 'Aya', 'default': '__FILE__'},
            {'name': 'line', 'deco': 'm', 'default': 'cast(ulong)__LINE__'}]}
        self.assertTrue(jdk_coverage.accepts(ctor, member('<init>(String)', ['String message'], kind='constructor')))
        self.assertTrue(jdk_coverage.accepts(ctor, member('<init>(String,Throwable)', ['String m', 'Throwable c'])))
        # Three Java arguments don't fit two real parameters, even though file and line make four D ones.
        self.assertFalse(jdk_coverage.accepts(ctor, member('<init>(String,Throwable,boolean)',
                                                           ['String m', 'Throwable c', 'boolean b'])))
        get = {'kind': 'function', 'parameters': [{'name': 'index', 'deco': 'i'}]}
        self.assertTrue(jdk_coverage.accepts(get, member('get(int)', ['int index'])))
        self.assertFalse(jdk_coverage.accepts(get, member('get(Object)', ['Object key'])))
        self.assertFalse(jdk_coverage.accepts(get, member('get(long)', ['long index'])))
        # Java's UTF-16 char[] is not the const(char)[] CharSequence overload (sol-jdk-math-regex, HexFormat).
        utf8 = {'kind': 'function', 'parameters': [{'name': 's', 'deco': 'xAa'}, {'name': 'a', 'deco': 'i'},
                                                   {'name': 'b', 'deco': 'i'}]}
        self.assertFalse(jdk_coverage.accepts(utf8, member('parseHex(char[],int,int)', ['char[] c', 'int a', 'int b'])))
        utf16 = {'kind': 'function', 'parameters': [{'name': 's', 'deco': 'xAu'}, {'name': 'a', 'deco': 'i'},
                                                    {'name': 'b', 'deco': 'i'}]}
        self.assertTrue(jdk_coverage.accepts(utf16, member('parseHex(char[],int,int)', ['char[] c', 'int a', 'int b'])))
        self.assertFalse(jdk_coverage.accepts(get, member('get(int[])', ['int[] index'])))
        templated = {'kind': 'function', 'parameters': [{'name': 'value', 'type': 'T'}]}
        self.assertTrue(jdk_coverage.accepts(templated, member('of(E)', ['E value'])))

    def test_rules_come_from_mapped_types_but_not_the_owner(self):
        self.assertEqual(jdk_coverage.member_rules(member('indexOf(Object)', ['Object o'], 'int'), False, 'List'),
                         ['R23'])
        self.assertEqual(jdk_coverage.member_rules(member('map(Function)', ['Function f'], 'Optional<U>'), False,
                                                   'Optional'), [])
        self.assertEqual(jdk_coverage.member_rules(member('of(E...)', ['E... es'], 'List<E>'), False, 'List'), ['R7'])
        self.assertEqual(jdk_coverage.member_rules(member('equals(Object)', ['Object o'], 'boolean'), False, 'X'), [])
        self.assertEqual(jdk_coverage.member_rules(member('version()', [], 'int'), True, 'UUID'), ['R19'])


if __name__ == '__main__':
    unittest.main()
