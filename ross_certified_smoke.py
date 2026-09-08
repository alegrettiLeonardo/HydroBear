from __future__ import annotations

import importlib.metadata as metadata
import json
import math
from pathlib import Path
import platform
import sys
import time

import numpy as np

ROSS_VERSION = "2.3.0"
ROSS_REVISION = "a26a66fe40e8b86aa5e5c203d18cca801e68ff8e"
PLAIN_FIXTURE_BLOB = "77f0029e6e98b05077b9de9fc2272b768593622f"
TILTING_FIXTURE_BLOB = "b6ffb58681cd054ad8af2879831e5b63f3a3ad5c"


def rel_error(actual: float, expected: float) -> float:
    return abs(actual - expected) / max(abs(expected), 1.0e-300)


def check_rel(name: str, actual: float, expected: float, rtol: float) -> dict:
    err = rel_error(float(actual), float(expected))
    if not math.isfinite(float(actual)) or err > rtol:
        raise AssertionError(
            f"{name}: actual={actual:.12g}, expected={expected:.12g}, "
            f"relative_error={err:.6g}, rtol={rtol:.6g}"
        )
    return {
        "actual": float(actual),
        "expected": float(expected),
        "relative_error": float(err),
        "rtol": float(rtol),
    }


def provider_provenance(rs) -> dict:
    dist = metadata.distribution("ross-rotordynamics")
    direct = None
    try:
        direct = json.loads(dist.read_text("direct_url.json") or "null")
    except Exception:
        direct = None
    revision = None
    if isinstance(direct, dict):
        vcs = direct.get("vcs_info") or {}
        revision = vcs.get("commit_id")
    if rs.__version__ != ROSS_VERSION:
        raise AssertionError(f"ROSS version {rs.__version__!r}; expected {ROSS_VERSION!r}")
    if revision != ROSS_REVISION:
        raise AssertionError(
            f"ROSS direct_url revision {revision!r}; expected immutable {ROSS_REVISION!r}"
        )
    return {
        "distribution": dist.metadata["Name"],
        "version": rs.__version__,
        "revision": revision,
        "direct_url": direct,
    }


def plain_journal_smoke(rs) -> dict:
    # Exact upstream ROSS 2.3 fixture: ross/tests/test_plain_journal.py
    # fixture plain_journal_perturbation / test_plain_journal_coefficients_perturbation.
    expected = {
        "kxx": 1080942844.8670897,
        "kxy": 339272299.0815782,
        "kyx": -1359171836.8799012,
        "kyy": 1108972345.8736706,
        "cxx": 15991501.488761209,
        "cxy": -16127663.630654775,
        "cyx": -18454827.71258994,
        "cyy": 43707428.16320889,
    }
    start = time.perf_counter()
    bearing = rs.PlainJournal(
        n=3,
        axial_length=rs.Q_(10.3600055944, "in"),
        journal_radius=0.2,
        radial_clearance=1.95e-4,
        elements_circumferential=11,
        elements_axial=3,
        n_pad=2,
        pad_arc_length=176,
        preload=0,
        geometry="circular",
        reference_temperature=50,
        frequency=rs.Q_([900], "RPM"),
        fxs_load=0,
        fys_load=-112814.91,
        groove_factor=[0.52, 0.48],
        lubricant="ISOVG32",
        sommerfeld_type=2,
        initial_guess=[0.1, -0.1],
        method="perturbation",
        operating_type="flooded",
        oil_supply_pressure=0,
        oil_flow_v=rs.Q_(37.86, "l/min"),
    )
    elapsed = time.perf_counter() - start

    actual = {
        "kxx": float(np.asarray(bearing.kxx).reshape(-1)[0]),
        "kxy": float(np.asarray(bearing.kxy).reshape(-1)[0]),
        "kyx": float(np.asarray(bearing.kyx).reshape(-1)[0]),
        "kyy": float(np.asarray(bearing.kyy).reshape(-1)[0]),
        "cxx": float(np.asarray(bearing.cxx).reshape(-1)[0]),
        "cxy": float(np.asarray(bearing.cxy).reshape(-1)[0]),
        "cyx": float(np.asarray(bearing.cyx).reshape(-1)[0]),
        "cyy": float(np.asarray(bearing.cyy).reshape(-1)[0]),
    }
    comparisons = {
        name: check_rel(f"PlainJournal.{name}", actual[name], expected[name], 1.0e-4)
        for name in expected
    }
    eq = np.asarray(bearing.equilibrium_pos, dtype=float).reshape(-1)
    equilibrium = {
        "eccentricity_ratio": check_rel("PlainJournal.eccentricity", eq[0], 0.68733194, 1.0e-2),
        "attitude_rad": check_rel("PlainJournal.attitude", eq[1], -0.79394211, 1.0e-2),
    }
    results = bearing._results
    pressure = np.asarray(results.pressure_fields[0], dtype=float)
    temperature = np.asarray(results.temperature_fields[0], dtype=float)
    if not np.all(np.isfinite(pressure)) or float(np.max(pressure)) <= 0.0:
        raise AssertionError("PlainJournal pressure field is not finite/positive")
    if not np.all(np.isfinite(temperature)):
        raise AssertionError("PlainJournal temperature field contains NaN/Inf")

    return {
        "status": "PASS",
        "fixture": "plain_journal_perturbation",
        "upstream_test": "test_plain_journal_coefficients_perturbation",
        "upstream_path": "ross/tests/test_plain_journal.py",
        "upstream_blob": PLAIN_FIXTURE_BLOB,
        "elapsed_s": elapsed,
        "coefficients": comparisons,
        "max_relative_error": max(item["relative_error"] for item in comparisons.values()),
        "equilibrium": equilibrium,
        "field_checks": {
            "pressure_shape": list(pressure.shape),
            "pressure_max_pa": float(np.max(pressure)),
            "temperature_shape": list(temperature.shape),
            "temperature_max_c": float(np.max(temperature)),
        },
    }


def tilting_pad_smoke(rs) -> dict:
    # Exact upstream ROSS 2.3 determine_eccentricity fixture.
    expected = {
        "kxx": 9.5254e07,
        "kxy": -4.7141e07,
        "kyx": -4.7141e07,
        "kyy": 1.2676e08,
        "cxx": 2.9184e05,
        "cxy": -4.0367e04,
        "cyx": -4.0367e04,
        "cyy": 3.5168e05,
    }
    start = time.perf_counter()
    bearing = rs.TiltingPad(
        n=1,
        frequency=rs.Q_([3000], "RPM"),
        journal_diameter=101.6e-3,
        radial_clearance=74.9e-6,
        pad_thickness=12.7e-3,
        pivot_angle=rs.Q_([18, 90, 162, 234, 306], "deg"),
        pad_arc=rs.Q_([60] * 5, "deg"),
        pad_axial_length=rs.Q_([50.8e-3] * 5, "m"),
        pre_load=[0.5] * 5,
        offset=[0.5] * 5,
        lubricant="ISOVG32",
        oil_supply_temperature=rs.Q_(40, "degC"),
        nx=30,
        nz=30,
        eccentricity=0.35,
        attitude_angle=rs.Q_(287.5, "deg"),
        load=[8.8405e02, -2.6704e03],
        thermal_type="full",
        equilibrium_type="determine_eccentricity",
        model_type="thermo_hydro_dynamic",
        initial_pads_angles=[
            1.0742e-03,
            7.2080e-04,
            2.9369e-04,
            3.4969e-04,
            8.1604e-04,
        ],
        solver_options={"xtol": 1e-2, "ftol": 1e-2, "maxiter": 1000},
    )
    elapsed = time.perf_counter() - start

    actual = {
        name: float(np.asarray(getattr(bearing, name)).reshape(-1)[0]) for name in expected
    }
    comparisons = {
        name: check_rel(f"TiltingPad.{name}", actual[name], expected[name], 1.0e-2)
        for name in expected
    }
    equilibrium = {
        "eccentricity_ratio": check_rel(
            "TiltingPad.eccentricity", float(bearing.eccentricity), 0.3722, 1.0e-2
        ),
        "attitude_rad": check_rel(
            "TiltingPad.attitude", float(bearing.attitude_angle), 5.064506361232241, 1.0e-2
        ),
    }
    # In ROSS 2.3, TiltingPad performance arrays live on _results; the bearing
    # itself delegates plotting but does not expose maxP/maxT as attributes.
    results = bearing._results
    max_p = float(np.asarray(results.maxP_list).reshape(-1)[0])
    max_t = float(np.asarray(results.maxT_list).reshape(-1)[0])
    if not math.isfinite(max_p) or max_p <= 0.0:
        raise AssertionError(f"TiltingPad maxP invalid: {max_p}")
    if not math.isfinite(max_t):
        raise AssertionError(f"TiltingPad maxT invalid: {max_t}")

    return {
        "status": "PASS",
        "fixture": "bearing_determine",
        "upstream_test": "TestTiltingPadDynamicCoefficients.test_coefficient",
        "upstream_path": "ross/tests/test_tilting_pad.py",
        "upstream_blob": TILTING_FIXTURE_BLOB,
        "elapsed_s": elapsed,
        "coefficients": comparisons,
        "max_relative_error": max(item["relative_error"] for item in comparisons.values()),
        "equilibrium": equilibrium,
        "performance_checks": {"max_pressure_pa": max_p, "max_temperature_c": max_t},
    }


def main() -> int:
    import ross as rs

    evidence = {
        "schema_version": 1,
        "status": "RUNNING",
        "python": sys.version,
        "platform": platform.platform(),
        "provider": provider_provenance(rs),
        "oracles": {
            "plain_journal": {
                "provider_commit": ROSS_REVISION,
                "fixture_blob": PLAIN_FIXTURE_BLOB,
            },
            "tilting_pad": {
                "provider_commit": ROSS_REVISION,
                "fixture_blob": TILTING_FIXTURE_BLOB,
            },
        },
    }
    try:
        evidence["plain_journal"] = plain_journal_smoke(rs)
        evidence["tilting_pad"] = tilting_pad_smoke(rs)
        evidence["status"] = "PASS"
    except Exception as exc:
        evidence["status"] = "FAIL"
        evidence["error"] = f"{type(exc).__name__}: {exc}"
        raise
    finally:
        Path("ross_certified_smoke_evidence.json").write_text(
            json.dumps(evidence, indent=2, sort_keys=True), encoding="utf-8"
        )
        print(json.dumps(evidence, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
