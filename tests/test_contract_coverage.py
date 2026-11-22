import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from contract_coverage import satisfies, scope_strengthened  # noqa: E402

BASE = 'R=Error P=(ref Request, string) S=AliasSeq!(ParameterStorageClass.ref_, ParameterStorageClass.none)'


class SignatureRules(unittest.TestCase):
    def test_identical_signature_matches(self):
        self.assertTrue(satisfies(BASE + ' A=nothrow,safe,', BASE + ' A=nothrow,safe,'))

    def test_implementation_may_add_attributes(self):
        self.assertTrue(satisfies(BASE + ' A=nothrow,nogc,safe,', BASE + ' A=safe,'))

    def test_implementation_may_not_drop_attributes(self):
        self.assertFalse(satisfies(BASE + ' A=safe,', BASE + ' A=nothrow,safe,'))

    def test_different_parameter_type_fails(self):
        other = BASE.replace('string', 'int')
        self.assertFalse(satisfies(other + ' A=safe,', BASE + ' A=safe,'))
        self.assertFalse(scope_strengthened(other + ' A=safe,', BASE + ' A=safe,'))

    def test_added_scope_is_classified_not_hidden(self):
        strengthened = ('R=Error P=(ref scope Request, string) '
                        'S=AliasSeq!(cast(ParameterStorageClass)18u, ParameterStorageClass.none) A=safe,')
        self.assertFalse(satisfies(strengthened, BASE + ' A=safe,'))
        self.assertTrue(scope_strengthened(strengthened, BASE + ' A=safe,'))

    def test_delegate_parameter_names_are_ignored(self):
        contract = 'R=Error P=(Error delegate(ref Request request) @safe) S=AliasSeq!(ParameterStorageClass.none) A=safe,'
        implementation = 'R=Error P=(Error delegate(ref scope Request) @safe) S=AliasSeq!(ParameterStorageClass.none) A=safe,'
        self.assertTrue(scope_strengthened(implementation, contract))


if __name__ == '__main__':
    unittest.main()
