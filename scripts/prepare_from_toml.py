"""Validate a case TOML and reuse the existing 3D generator. Python >= 3.11."""
import argparse
import copy
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib

REPO = Path(__file__).resolve().parents[1]
# Each entry: environment name, default, validation rule.
FIELDS = {
    'physics': {
        'mach': ('MACH', 0.1, 'nonnegative'), 'gamma': ('GAMMA', 1.6666, 'gamma'),
        'mass': ('MP', 1.0, 'positive'), 'density': ('RHO0', 1.0, 'positive'),
        'sound_speed': ('CS0', 1.0, 'positive')},
    'softening': {'a_soft': ('A_SOFT', None, 'positive'),
                  'rsoft_frac': ('RSOFT_FRAC', None, 'positive')},
    'grid': {'cells_per_rbhl': ('CELLS_PER_RBHL', 2.0, 'positive'),
             'margin_up': ('MARGIN_UP', 1.2, 'positive'),
             'margin_down': ('MARGIN_DOWN', 1.3, 'positive'),
             'margin_y': ('MARGIN_Y', 1.3, 'positive'),
             'upstream_min': ('UPSTREAM_MIN', 5.0, 'positive')},
    'time': {'log_lambda_max': ('LOG_LAMBDA_MAX', 2.0, 'finite'),
             'cfl': ('CFL', 0.333, 'cfl')},
    'output': {'count': ('N_OUTPUT', 20, 'integer'),
               'runs_dir': ('RUNS_DIR', '../../runs_3d', 'path'),
               'subdir': ('EXPORT_SUBDIR', 'export', 'subdir')},
    'limits': {'warn_cells': ('WARN_CELLS', 2000000, 'integer'),
               'hard_cells': ('HARD_CELLS', 8000000, 'integer'),
               'min_cells_per_rsoft': ('MIN_CELLS_PER_RSOFT', 2.0, 'positive'),
               'min_boundary_over_rsoft': ('MIN_BOUNDARY_OVER_RSOFT', 4.0, 'positive')},
    'diagnostics': {'sound_speed_threshold': ('CS_ALERT_THRESHOLD', 1e-6, 'nonnegative'),
                    'sound_speed_every_steps': ('CS_ALERT_EVERY_STEPS', 1, 'integer'),
                    'mach_threshold': ('MACH_ALERT_THRESHOLD', 0.0, 'nonnegative'),
                    'mach_every_steps': ('MACH_ALERT_EVERY_STEPS', 1, 'integer')},
}


def validate(name, value, rule):
    if rule in ('path', 'subdir'):
        if not isinstance(value, str) or not value or any(c in value for c in '\x00\r\n'):
            raise ValueError(f'{name} must be a nonempty path string without control characters')
        if rule == 'subdir' and (not re.fullmatch(r'[A-Za-z0-9_./-]+', value)
                                or Path(value).is_absolute() or '..' in Path(value).parts
                                or value in ('.', './')):
            raise ValueError(f'{name} must be a relative subdirectory without .. or whitespace')
        return
    if type(value) not in (int, float) or not math.isfinite(value):
        raise ValueError(f'{name} must be a finite number')
    if rule == 'integer' and (type(value) is not int or value <= 0):
        raise ValueError(f'{name} must be a positive integer')
    if rule == 'positive' and value <= 0 or rule == 'nonnegative' and value < 0:
        raise ValueError(f'{name} is out of range')
    if rule == 'gamma' and value <= 1:
        raise ValueError(f'{name} must exceed 1 for the ideal-gas EOS')
    if rule == 'cfl' and not 0 < value < 1/3:
        raise ValueError(f'{name} must satisfy 0 < CFL < 1/3 for this 3D setup')


def resolve(raw, base):
    if type(raw.get('schema_version')) is not int or raw['schema_version'] != 1:
        raise ValueError('schema_version must be integer 1')
    unknown = raw.keys() - (FIELDS.keys() | {'schema_version', 'sweep'})
    if unknown:
        raise ValueError(f'Unknown top-level keys: {sorted(unknown)}')
    resolved = {'schema_version': 1}
    for table, fields in FIELDS.items():
        supplied = raw.get(table, {})
        if not isinstance(supplied, dict) or supplied.keys() - fields.keys():
            raise ValueError(f'Invalid or unknown keys in {table}')
        resolved[table] = {}
        for key, (_, default, rule) in fields.items():
            value = supplied.get(key, default)
            if value is not None:
                validate(f'{table}.{key}', value, rule)
                resolved[table][key] = value
    sweep = raw.get('sweep')
    parameter, values = None, [None]
    if sweep is not None:
        if not isinstance(sweep, dict) or set(sweep) != {'parameter', 'values'}:
            raise ValueError('sweep requires exactly parameter and values')
        parameter, values = sweep['parameter'], sweep['values']
        if not isinstance(parameter, str) or parameter not in ('physics.mach', 'softening.a_soft'):
            raise ValueError('Unsupported sweep parameter')
        if not isinstance(values, list) or not values:
            raise ValueError('sweep.values must be a nonempty list')
        table, key = parameter.split('.')
        if key in raw.get(table, {}):
            raise ValueError(f'{parameter} cannot be both fixed and swept')
        for value in values:
            validate(parameter, value, FIELDS[table][key][2])
        if len(set(values)) != len(values):
            raise ValueError('Duplicate sweep values')
    cases = []
    for value in values:
        case = copy.deepcopy(resolved)
        if parameter:
            table, key = parameter.split('.')
            case[table][key] = value
        soft = case['softening']
        if len(soft) > 1:
            raise ValueError('Specify a_soft or rsoft_frac, not both')
        if not soft:
            soft['rsoft_frac'] = 0.25
        path = Path(case['output']['runs_dir']).expanduser()
        case['output']['runs_dir'] = str((base / path).resolve())
        cases.append(case)
    return cases


def literal(value):
    # JSON string syntax is also valid TOML basic-string syntax here.
    import json
    return json.dumps(value, ensure_ascii=False, allow_nan=False)


def write_effective(path, case, summary, source, revision, dirty):
    with path.open('w') as out:
        out.write('schema_version = 1\n')
        for table in FIELDS:
            out.write(f'\n[{table}]\n')
            for key, value in case[table].items():
                out.write(f'{key} = {literal(value)}\n')
        out.write('\n[provenance]\n')
        for key, value in dict(source=str(source), revision=revision, dirty=dirty).items():
            out.write(f'{key} = {literal(value)}\n')
        out.write('\n[derived]\n')
        for key, value in summary.items():
            out.write(f'{key} = {literal(value)}\n')


def prepare(source):
    source = source.resolve()
    original = source.read_bytes()
    cases = resolve(tomllib.loads(original.decode('utf-8')), source.parent)
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip()
    dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=REPO, text=True))
    # Retain tool/runtime environment, but remove every supported simulation
    # setting (and historical sink controls) before passing resolved values.
    excluded = {field[0] for fields in FIELDS.values() for field in fields.values()}
    env_base = {k: v for k, v in os.environ.items() if k not in excluded and not k.startswith('SINK_')}
    published = []
    with tempfile.TemporaryDirectory(prefix='pluto-toml-') as tmp:
        staged = []
        destinations = set()
        for index, case in enumerate(cases):
            env = dict(env_base)
            for table, fields in FIELDS.items():
                for key, (variable, _, _) in fields.items():
                    if key in case[table]:
                        env[variable] = str(case[table][key])
            env['RUNS_DIR'] = str(Path(tmp) / str(index))
            proc = subprocess.run(['bash', str(REPO/'scripts/prepare_one_case_3d.sh')],
                                  env=env, text=True, capture_output=True)
            if proc.stderr:
                print(proc.stderr, end='', file=sys.stderr)
            if proc.returncode:
                raise ValueError('Case generation failed; no cases published')
            stage = Path(next(line.removeprefix('Prepared ') for line in proc.stdout.splitlines()
                              if line.startswith('Prepared ')))
            destination = Path(case['output']['runs_dir']) / stage.name
            if destination in destinations or destination.exists() or destination.is_symlink():
                raise ValueError(f'Refusing to overwrite or duplicate case: {destination}')
            destinations.add(destination)
            summary = dict(line.split(' = ', 1) for line in (stage/'run_summary.txt').read_text().splitlines())
            # The generated summary is authoritative for derived values; retain
            # its existing string precision in the effective TOML.
            (stage/'setup.original.toml').write_bytes(original)
            write_effective(stage/'setup.effective.toml', case, summary, source, revision, dirty)
            staged.append((stage, destination))
        runs_dir = Path(cases[0]['output']['runs_dir'])
        runs_dir.mkdir(parents=True, exist_ok=True)
        manifest = None
        if len(cases) > 1 or 'sweep' in tomllib.loads(original.decode('utf-8')):
            (runs_dir/'manifests').mkdir(exist_ok=True)
            fd, manifest = tempfile.mkstemp(prefix='toml_', suffix='.txt', dir=runs_dir/'manifests')
            os.close(fd)
        for stage, destination in staged:
            # Exclusive mkdir also protects against a concurrent generator.
            destination.mkdir()
            shutil.copytree(stage, destination, dirs_exist_ok=True)
            published.append(destination)
            if manifest:
                with open(manifest, 'a') as out:
                    out.write(str(destination)+'\n')
            print(f'Prepared {destination}')
        if manifest:
            print(f'Wrote manifest {manifest}')
    return published


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('setup', type=Path)
    args = parser.parse_args()
    try:
        prepare(args.setup)
    except (ValueError, OSError, subprocess.SubprocessError, StopIteration) as exc:
        parser.exit(1, f'Invalid setup: {exc}\n')


if __name__ == '__main__':
    main()
