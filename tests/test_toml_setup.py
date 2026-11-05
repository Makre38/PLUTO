"""Exercise the real shell entry point; no PLUTO build required."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import sys
import tomllib
import unittest

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('setup', REPO/'scripts/prepare_from_toml.py')
setup = importlib.util.module_from_spec(spec)
sys.dont_write_bytecode = True
spec.loader.exec_module(setup)


class TomlSetup(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='pluto-toml-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def run_config(self, body, ok=True, extra_env=None):
        source = self.root/'input.toml'
        source.write_text(body)
        env = dict(os.environ)
        env.update(extra_env or {})
        proc = subprocess.run(['bash', str(REPO/'scripts/prepare_from_toml.sh'), str(source)],
                              cwd='/tmp', env=env, text=True, capture_output=True, timeout=30)
        self.assertEqual(proc.returncode == 0, ok, proc.stderr)
        cases = [Path(l.removeprefix('Prepared ')) for l in proc.stdout.splitlines() if l.startswith('Prepared ')]
        return proc, cases

    def base(self, extra=''):
        return 'schema_version = 1\n[output]\nruns_dir = "runs with spaces"\n' + extra

    def test_single_defaults_and_hostile_environment(self):
        body = self.base('[time]\nlog_lambda_max = 0.1\n')
        _, cases = self.run_config(body, extra_env={'MACH': 'wrong', 'A_SOFT': 'wrong',
            'SINK_RADIUS': '9', 'CFL': '9', 'RUNS_DIR': '/not/used', 'RSOFT_FRAC': 'wrong'})
        case = cases[0]
        self.assertEqual(case.parent, self.root/'runs with spaces')
        self.assertEqual((case/'setup.original.toml').read_text(), body)
        effective = tomllib.loads((case/'setup.effective.toml').read_text())
        self.assertEqual(effective['physics']['mach'], 0.1)
        self.assertEqual(effective['softening'], {'rsoft_frac': 0.25})
        self.assertEqual(effective['time']['cfl'], 0.333)
        self.assertEqual(effective['diagnostics']['mach_threshold'], 0.0)
        self.assertEqual(len(effective['provenance']['revision']), 40)
        self.assertIn('rbhl', effective['derived'])
        self.assertNotIn('sink_radius', effective['derived'])
        env = {k: os.environ[k] for k in ('PATH','HOME') if k in os.environ}
        env.update(RUNS_DIR=str(self.root/'legacy'), LOG_LAMBDA_MAX='0.1')
        proc = subprocess.run(['bash', str(REPO/'scripts/prepare_one_case_3d.sh')], env=env,
                              text=True, capture_output=True, check=True)
        legacy = Path(proc.stdout.strip().removeprefix('Prepared '))
        def normalized(path):
            def token(value):
                try:
                    return float(value)
                except ValueError:
                    return value
            return [[token(v) for v in line.split()] for line in path.read_text().splitlines()]
        self.assertEqual(normalized(case/'pluto.ini'), normalized(legacy/'pluto.ini'))

    def test_sweeps_and_diagnostics(self):
        for index, (parameter, values, table) in enumerate([
                ('physics.mach', '[0.1, 0.5]', '[softening]\na_soft = 1.0\n'),
                ('softening.a_soft', '[2.0, 1.0]', '[physics]\nmach = 0.5\n')]):
            body = f'''schema_version = 1
[output]
runs_dir = "sweep{index}"
count = 3
{table}
[time]
log_lambda_max = 0.1
cfl = 0.2
[diagnostics]
sound_speed_threshold = 2.0
sound_speed_every_steps = 3
mach_threshold = 0.1
mach_every_steps = 5
[sweep]
parameter = "{parameter}"
values = {values}
'''
            proc, cases = self.run_config(body)
            self.assertEqual(len(cases), 2)
            manifest = Path(next(l.removeprefix('Wrote manifest ') for l in proc.stdout.splitlines() if l.startswith('Wrote manifest ')))
            self.assertEqual(manifest.read_text().splitlines(), list(map(str, cases)))
            for case in cases:
                ini = (case/'pluto.ini').read_text()
                self.assertIn('CFL              0.2', ini)
                self.assertIn('MACH_ALERT_EVERY_STEPS      5', ini)
                self.assertIn('CS_ALERT_THRESHOLD          2.0', ini)
            if index == 1:
                clean = lambda p: [l for l in (p/'pluto.ini').read_text().splitlines() if not l.startswith('RSOFT ')]
                self.assertEqual(clean(cases[0]), clean(cases[1]))

    def test_invalid_schema_and_values(self):
        invalid = [
            'schema_version = true', 'schema_version = 2', 'schema_version = 1\nunknown = 2',
            self.base('[physics]\nunknown = 2'), self.base('[physics]\nmach = true'),
            self.base('[physics]\ngamma = 1.0'), self.base('[physics]\nmass = inf'),
            self.base('[time]\ncfl = 0.4'), self.base('[time]\ncfl = 0.0'),
            self.base('[diagnostics]\nmach_every_steps = 1.5'),
            self.base('[diagnostics]\nsound_speed_threshold = -1.0'),
            self.base('[softening]\na_soft = 1.0\nrsoft_frac = 0.25'),
            self.base('[sink]\nradius = 0.0'),
            self.base('[sweep]\nparameter = "physics.mach"\nvalues = []'),
            self.base('[sweep]\nparameter = "physics.mach"\nvalues = [0.5, 0.5]'),
            self.base('[sweep]\nparameter = "physics.mass"\nvalues = [1,2]'),
            self.base('[physics]\nmach = 0.5\n[sweep]\nparameter = "physics.mach"\nvalues = [0.1]'),
        ]
        for body in invalid:
            with self.subTest(body=body):
                self.run_config(body, ok=False)
                self.assertFalse((self.root/'runs with spaces').exists())
        for subdir in ('../escape', '/tmp/escape', '.', 'with spaces'):
            self.run_config(f'schema_version = 1\n[output]\nruns_dir = "runs with spaces"\nsubdir = "{subdir}"', ok=False)
            self.assertFalse((self.root/'runs with spaces').exists())

    def test_failed_later_case_publishes_nothing(self):
        self.run_config(self.base('[time]\nlog_lambda_max = 0.1\n[sweep]\nparameter = "physics.mach"\nvalues = [0.1, 1000000.0]'), ok=False)
        self.assertFalse((self.root/'runs with spaces').exists())

    def test_overwrite_and_name_collisions(self):
        body = self.base('[time]\nlog_lambda_max = 0.1\n')
        _, cases = self.run_config(body)
        saved = (cases[0]/'setup.original.toml').read_bytes()
        proc, _ = self.run_config(body, ok=False)
        self.assertIn('Refusing to overwrite', proc.stderr)
        self.assertEqual((cases[0]/'setup.original.toml').read_bytes(), saved)
        self.run_config('schema_version = 1\n[output]\nruns_dir = "collision"\n[time]\nlog_lambda_max = 0.1\n[sweep]\nparameter = "physics.mach"\nvalues = [0.10001, 0.10002]', ok=False)
        self.assertFalse((self.root/'collision').exists())

    def test_examples_parse_and_resolve(self):
        for source in (REPO/'configs/examples').glob('*.toml'):
            cases = setup.resolve(tomllib.loads(source.read_text()), source.parent)
            self.assertTrue(cases)


if __name__ == '__main__':
    unittest.main()
