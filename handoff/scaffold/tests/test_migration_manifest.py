import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "migration_manifest", Path(__file__).resolve().parents[1]/"tools/migration_manifest.py")
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)

class MigrationManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root/"migrations"
        self.source.mkdir()
        self.sql = self.source/"V000001__create_users.sql"
        self.sql.write_bytes(b"CREATE TABLE users(id INTEGER PRIMARY KEY);\n")
        self.output = self.root/"generated"/"migrations.d"

    def args(self):
        return ["--input",str(self.source),"--output",str(self.output),"--module","app.migrations"]

    def run_main(self, args):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return m.main(args)

    def test_roundtrip_and_check_detects_drift(self):
        self.assertEqual(self.run_main(self.args()),0)
        self.assertEqual(self.run_main(self.args()+["--check"]),0)
        old=self.output.read_bytes()
        self.sql.write_bytes(self.sql.read_bytes()+b"-- drift\n")
        self.assertEqual(self.run_main(self.args()+["--check"]),1)
        self.assertEqual(self.output.read_bytes(),old)

    def test_numeric_version_collision_is_rejected(self):
        (self.source/"V0000001__duplicate.sql").write_bytes(b"SELECT 1;")
        with self.assertRaisesRegex(m.ManifestError,"duplicate numeric version"):
            m.collect(self.source,set())

    def test_symlink_escape_is_rejected(self):
        outside=self.root/"outside.sql"
        outside.write_bytes(b"SELECT 1;")
        (self.source/"V000002__link.sql").symlink_to(outside)
        with self.assertRaisesRegex(m.ManifestError,"non-symlink"):
            m.collect(self.source,set())

    def test_module_injection_and_keyword_rejected(self):
        rows=m.collect(self.source,set())
        for value in ["app; import evil", "flint.template", "../app", "app..migrations"]:
            with self.assertRaises(m.ManifestError):
                m.render(rows,value)

    def test_output_cannot_overwrite_sql(self):
        with self.assertRaisesRegex(m.ManifestError,"overwrite"):
            m.outputs(self.source,self.sql,"app.migrations",set())

    def test_checksum_covers_raw_line_endings(self):
        unix=m.collect(self.source,set())[0]["sha256"]
        self.sql.write_bytes(b"CREATE TABLE users(id INTEGER PRIMARY KEY);\r\n")
        windows=m.collect(self.source,set())[0]["sha256"]
        self.assertNotEqual(unix,windows)

    def test_nontransactional_requires_existing_version(self):
        with self.assertRaisesRegex(m.ManifestError,"absent"):
            m.collect(self.source,{2})
        self.assertFalse(m.collect(self.source,{1})[0]["transactional"])

    def test_deterministic_and_ordered_output(self):
        (self.source/"V000010__ten.sql").write_bytes(b"SELECT 10;")
        (self.source/"V000002__two.sql").write_bytes(b"SELECT 2;")
        rows=m.collect(self.source,set())
        self.assertEqual([x["version"] for x in rows],[1,2,10])
        self.assertEqual(m.render(rows,"app.migrations"),m.render(rows,"app.migrations"))

if __name__=="__main__":
    unittest.main()
