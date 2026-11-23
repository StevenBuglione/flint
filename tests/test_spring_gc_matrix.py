"""spring_bench gc-matrix's A/B arms: `--gcopt` and `--runs` make an `ab` record, never the Phase 1 matrix."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import spring_gc_matrix  # noqa: E402

MATRIX = {'conservative': 'gc:conservative', 'precise': 'gc:precise'}


class GcMatrixArms(unittest.TestCase):
    def test_the_matrix_alone_is_a_production_record(self):
        self.assertEqual(spring_gc_matrix.arms(MATRIX, None, None, None), (['conservative', 'precise'], MATRIX, False))

    def test_an_extra_arm_or_a_trial_count_makes_an_ab_record(self):
        settings, options, ab = spring_gc_matrix.arms(
            MATRIX, ['conservative'], ['small-pools=gc:conservative minPoolSize:1 incPoolSize:0 parallel:1'], 4)
        self.assertEqual(settings, ['conservative', 'small-pools'])
        self.assertEqual(options['small-pools'], 'gc:conservative minPoolSize:1 incPoolSize:0 parallel:1')
        self.assertTrue(ab)
        self.assertEqual(spring_gc_matrix.arms(MATRIX, None, ['a=minPoolSize:1'], None)[0], ['a'])
        self.assertTrue(spring_gc_matrix.arms(MATRIX, ['precise'], None, 3)[2])

    def test_an_arm_must_be_new_and_named(self):
        for gcopts, runs, message in ((['conservative=gc:precise'], None, '--gcopt needs a new'),
                                      (['small-pools'], None, '--gcopt needs a new'),
                                      (['a=minPoolSize:1', 'a=minPoolSize:2'], None, '--gcopt needs a new'),
                                      (None, 0, '--runs must be at least 1')):
            with self.assertRaises(SystemExit) as raised:
                spring_gc_matrix.arms(MATRIX, None, gcopts, runs)
            self.assertIn(message, str(raised.exception))
        with self.assertRaises(SystemExit):
            spring_gc_matrix.arms(MATRIX, ['nonesuch'], None, None)


if __name__ == '__main__':
    unittest.main()
