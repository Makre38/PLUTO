"""Small generated cases only; no PLUTO build or simulation is launched."""
import math
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


def summary(case):
    return dict(line.split(" = ", 1) for line in (case / "run_summary.txt").read_text().splitlines())


class SofteningGeneration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="pluto_softening_test_")
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def run_script(self, script="prepare_one_case_3d.sh", folder="runs", ok=True, **params):
        env = {key: os.environ[key] for key in ("PATH", "HOME") if key in os.environ}
        env.update(RUNS_DIR=str(self.root / folder), MACH="0.5", LOG_LAMBDA_MAX="0.1")
        env.update({key: str(value) for key, value in params.items()})
        proc = subprocess.run(["bash", str(REPO / "scripts" / script)], env=env,
                              text=True, capture_output=True, timeout=30)
        if ok:
            self.assertEqual(proc.returncode, 0, proc.stderr)
        else:
            self.assertNotEqual(proc.returncode, 0, proc.stdout)
        cases = [Path(line.removeprefix("Prepared ")) for line in proc.stdout.splitlines()
                 if line.startswith("Prepared ")]
        return proc, cases

    def test_legacy_default_scales_and_name(self):
        _, cases = self.run_script()
        s = summary(cases[0])
        self.assertEqual(cases[0].name, "mach0.500_mp1.000_ll0.100_rbhl2.0_3d")
        self.assertEqual(float(s["rbhl"]), 0.8)
        self.assertEqual(float(s["rsoft"]), 0.2)
        self.assertEqual(s["softening_mode"], "legacy")
        _, cases = self.run_script(folder="frac", RSOFT_FRAC="0.5")
        self.assertEqual(float(summary(cases[0])["rsoft"]), 0.4)

    def test_all_derived_scales(self):
        for a in (1, 0.3):
            _, cases = self.run_script(folder=str(a), A_SOFT=a, MP=2, CS0=2)
            s = summary(cases[0])
            rb, rbhl, rs = 0.5, 0.4, 0.5 / a
            for key, expected in (("r_bondi", rb), ("rbhl", rbhl), ("a_soft", a),
                                  ("rsoft", rs), ("rsoft_over_rbondi", 1/a),
                                  ("rsoft_over_rbhl", rs/rbhl)):
                self.assertAlmostEqual(float(s[key]), expected)
            for axis, spacing in zip("xyz", ("dx_actual", "dy_actual", "dz_actual")):
                for scale, value in (("rsoft", rs), ("rbondi", rb), ("rbhl", rbhl)):
                    self.assertAlmostEqual(float(s[f"cells_per_{scale}_{axis}"]), value/float(s[spacing]))
                for edge in ("min", "max"):
                    self.assertAlmostEqual(float(s[f"boundary_{axis}{edge}_over_rsoft"]),
                                           abs(float(s[f"{axis}{edge}"]))/rs)
            self.assertAlmostEqual(float(s["tmax"]), rbhl/2*math.exp(0.1))
            ini = (cases[0] / "pluto.ini").read_text()
            rsoft_line = next(line for line in ini.splitlines() if line.startswith("RSOFT "))
            self.assertAlmostEqual(float(rsoft_line.split()[1]), rs)
            self.assertNotIn("A_SOFT", ini)

    def test_asoft_independent_of_mach(self):
        soft = []
        for mach in (0.1, 2):
            _, cases = self.run_script(folder=str(mach), A_SOFT=3, MACH=mach)
            soft.append(float(summary(cases[0])["rsoft"]))
        self.assertEqual(soft[0], soft[1])

    def test_conflicts_and_invalid_values(self):
        proc, _ = self.run_script(A_SOFT=1, RSOFT_FRAC=0.25, ok=False)
        self.assertIn("not both", proc.stderr)
        for value in ("", "0", "-1", "nan", "inf", "1e999", "word"):
            with self.subTest(value=value):
                proc, _ = self.run_script(A_SOFT=value, ok=False)
                self.assertIn("A_SOFT", proc.stderr)
        self.assertFalse((self.root / "runs").exists())

    def test_warnings_and_cell_limit(self):
        proc, cases = self.run_script(A_SOFT=100)
        self.assertIn("MIN_CELLS_PER_RSOFT", proc.stderr)
        original_ncell = summary(cases[0])["ncell"]
        proc, cases = self.run_script(folder="large", A_SOFT=0.01)
        self.assertIn("MIN_BOUNDARY_OVER_RSOFT", proc.stderr)
        self.assertEqual(summary(cases[0])["ncell"], original_ncell)
        proc, _ = self.run_script(folder="limit", A_SOFT=1, HARD_CELLS=1, ok=False)
        self.assertIn("HARD_CELLS", proc.stderr)
        self.assertFalse((self.root / "limit").exists())
        proc, _ = self.run_script(folder="warn", A_SOFT=1, WARN_CELLS=1)
        self.assertIn("WARN_CELLS", proc.stderr)

    def test_existing_asoft_case_is_preserved(self):
        _, cases = self.run_script(A_SOFT=1)
        before = (cases[0] / "pluto.ini").read_bytes()
        proc, _ = self.run_script(A_SOFT=1, GAMMA=1.2, ok=False)
        self.assertIn("Refusing to overwrite", proc.stderr)
        self.assertEqual((cases[0] / "pluto.ini").read_bytes(), before)

    def test_matched_no_sink_sweep(self):
        proc, cases = self.run_script("prepare_softening_sweep_3d.sh", folder="with spaces",
                                      A_SOFT_VALUES="3 1\n0.3", GAMMA=1.4)
        self.assertEqual(len(cases), 3)
        manifest = Path(next(line.removeprefix("Wrote manifest ") for line in proc.stdout.splitlines()
                             if line.startswith("Wrote manifest ")))
        self.assertEqual(manifest.read_text().splitlines(), list(map(str, cases)))
        common_ini = []
        for case in cases:
            self.assertNotIn("sink_radius", summary(case))
            ini_lines = (case / "pluto.ini").read_text().splitlines()
            self.assertFalse(any(line.startswith("SINK_") for line in ini_lines))
            common_ini.append([line for line in ini_lines if not line.startswith("RSOFT ")])
        self.assertEqual(common_ini[0], common_ini[1])
        self.assertEqual(common_ini[1], common_ini[2])

    def test_removed_sink_options_fail_before_creating_cases(self):
        for script in ("prepare_one_case_3d.sh", "prepare_mach_sweep_3d.sh",
                       "prepare_softening_sweep_3d.sh"):
            for option in ("SINK_RADIUS", "SINK_TIMESCALE", "SINK_TAPER_POWER",
                           "SINK_RHO_FLOOR", "SINK_VELOCITY_FACTOR"):
                for value in ("", "0", "0.1"):
                    with self.subTest(script=script, option=option, value=value):
                        proc, _ = self.run_script(script, ok=False, **{option: value})
                        self.assertIn(option + " is no longer supported", proc.stderr)
                        self.assertFalse((self.root / "runs").exists())

    def test_sweep_rejects_invalid_or_ambiguous_list(self):
        for params in ({"A_SOFT_VALUES": ""}, {"A_SOFT_VALUES": "1 0"},
                       {"A_SOFT_VALUES": "1 1.0"}, {"A_SOFT": 1}, {"RSOFT_FRAC": 0.25}):
            self.run_script("prepare_softening_sweep_3d.sh", ok=False, **params)
        self.assertFalse((self.root / "runs").exists())

    def test_mach_sweep_forwards_only_selected_softening(self):
        for label, params in (("legacy", {}), ("asoft", {"A_SOFT": 1}),
                               ("frac", {"RSOFT_FRAC": 0.5})):
            _, cases = self.run_script("prepare_mach_sweep_3d.sh", folder=label,
                                      MACH_MIN=0.5, MACH_MAX=0.5, **params)
            self.assertEqual(len(cases), 1)
            self.assertEqual(float(summary(cases[0])["rsoft"]), {"legacy": 0.2, "asoft": 1, "frac": 0.4}[label])
        self.run_script("prepare_mach_sweep_3d.sh", A_SOFT=1, RSOFT_FRAC=0.25, ok=False)


if __name__ == "__main__":
    unittest.main()
