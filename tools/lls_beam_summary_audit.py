"""Independent reconciliation of P1 summaries against their persisted observations."""
from __future__ import annotations

import math

SCOPES = {
    "RunID": ("RunID",), "ExecutionID": ("ExecutionID",),
    "UEIndex": ("UEIndex", "UEID"),
    "ServingCell": ("ServingCell", "CellID", "BaseStationID"),
    "ComponentCarrier": ("ComponentCarrier", "ComponentCarrierId"),
    "BWPId": ("BWPId", "ActiveBWP", "BWPID"),
    "BurstID": ("BurstID", "SSBBurstID"), "Frame": ("Frame",), "Slot": ("Slot",),
    "PowerReferencePlane": ("PowerReferencePlane",),
}
QUALITY = ("PostEqSINR_dB", "MeasuredWidebandSINR_dB", "MeasuredTrialSINR_dB", "SINR_dB")
NORMALIZED_PLANE = "normalized_fixed_esn0_unit_occupied_re_es"
NORMALIZED_RSRP = "SS_RSRP_dB_re_UnitOccupiedRE_Es"


def number(value):
    try:
        return float(value)
    except (ValueError, TypeError):
        return math.nan


def present(value):
    return str(value).strip().lower() not in ("", "nan", "<missing>", "none")


def equal(left, right):
    a, b = number(left), number(right)
    if math.isfinite(a) and math.isfinite(b):
        return a == b
    return str(left) == str(right)


def reconcile_beam_summary(rows, sources):
    failures = []
    for index, row in enumerate(rows, 1):
        metric = row.get("Metric", "")
        if not metric.startswith("P1"):
            continue
        source = sources.get(row.get("TraceSource", ""), [])
        if not source:
            failures.append(f"row{index}:missing_observation_source")
            continue
        scoped = source
        for target, aliases in SCOPES.items():
            name = next((name for name in aliases if any(present(r.get(name, "")) for r in source)), None)
            if name:
                if not present(row.get(target, "")):
                    failures.append(f"row{index}:omitted_scope_{target}")
                else:
                    scoped = [r for r in scoped if equal(r.get(name, ""), row[target])]
        axis = "ConfiguredSNR_dB" if any("ConfiguredSNR_dB" in r for r in source) else "SNR_dB"
        expected_role = "configured_operating_point_metadata" if axis == "ConfiguredSNR_dB" else "source_defined_snr_axis"
        if any(math.isfinite(number(r.get(axis))) for r in source):
            if row.get("SNR_dBValueRole") != expected_role:
                failures.append(f"row{index}:incorrect_operating_point_role")
            scoped = [r for r in scoped if equal(r.get(axis), row.get("SNR_dB"))]
        if not scoped:
            failures.append(f"row{index}:no_exact_source_scope_or_operating_point")
            continue
        if metric in ("P1SelectedSSBBeamIndex", "P1SelectedSSBBeamScore", "P1SSBSweptBeamCount"):
            # The declared power domain, not whichever column is finite,
            # determines the measured score. Never compare dBm with unit Es.
            normalized = row.get("PowerReferencePlane") == NORMALIZED_PLANE
            score_axis = NORMALIZED_RSRP if normalized else "SS_RSRP_dBm"
            if (normalized or present(row.get("ScoreAxis", ""))) and row.get("ScoreAxis") != score_axis:
                failures.append(f"row{index}:score_axis_power_domain_mismatch")
            eligible = [r for r in scoped if math.isfinite(number(r.get(score_axis)))
                        and math.isfinite(number(r.get("SSBIndex")))]
            if not eligible:
                failures.append(f"row{index}:winner_without_scored_physical_ssb")
                continue
            winner = max(eligible, key=lambda r: number(r[score_axis]))
            expected = {
                "P1SelectedSSBBeamIndex": number(winner["SSBIndex"]),
                "P1SelectedSSBBeamScore": number(winner[score_axis]),
                "P1SSBSweptBeamCount": len({number(r.get("SSBIndex")) for r in scoped
                                           if math.isfinite(number(r.get("SSBIndex")))}),
            }[metric]
            if not math.isclose(number(row.get("MeanValue")), expected, rel_tol=0, abs_tol=1e-10):
                failures.append(f"row{index}:incorrect_{metric}")
            if row.get("SelectionEvidenceRole") != "posthoc_measured_candidate_comparison_not_receiver_decision":
                failures.append(f"row{index}:selection_authority_not_disclosed")
            quality_rows = [winner]
        else:
            quality_rows = scoped
            power_metrics = {
                "P1SS_RSRP_dBm": "SS_RSRP_dBm",
                "P1" + NORMALIZED_RSRP: NORMALIZED_RSRP,
                "P1SS_RSRPRawObserved_dB_re_UnitOccupiedRE_Es": "SS_RSRPRawObserved_dB_re_UnitOccupiedRE_Es",
            }
            if metric in power_metrics:
                power_axis = power_metrics[metric]
                normalized = row.get("PowerReferencePlane") == NORMALIZED_PLANE
                if normalized != (power_axis != "SS_RSRP_dBm"):
                    failures.append(f"row{index}:rsrp_metric_power_domain_mismatch")
                powers = [number(r.get(power_axis)) for r in scoped
                          if math.isfinite(number(r.get(power_axis)))]
                # Descriptive mean in the declared observation domain, not a
                # combined received-power measurement or serving-RSRP estimate.
                if (not powers or number(row.get("SampleCount")) != len(powers)
                        or not math.isclose(number(row.get("MeanValue")), sum(powers)/len(powers), rel_tol=0, abs_tol=1e-9)):
                    failures.append(f"row{index}:observed_rsrp_summary_mismatch")
        quality_axis = next((name for name in QUALITY if any(math.isfinite(number(r.get(name))) for r in quality_rows)), None)
        if quality_axis is None:
            if math.isfinite(number(row.get("QualityMean_dB"))) or number(row.get("QualitySampleCount")) != 0:
                failures.append(f"row{index}:invented_receiver_quality")
            continue
        values = [number(r.get(quality_axis)) for r in quality_rows if math.isfinite(number(r.get(quality_axis)))]
        if (row.get("QualityAxis") != quality_axis
                or number(row.get("QualitySampleCount")) != len(values)
                or not math.isclose(number(row.get("QualityMean_dB")), sum(values)/len(values), rel_tol=0, abs_tol=1e-9)):
            failures.append(f"row{index}:receiver_quality_distribution_mismatch")
        prefix = quality_axis.removesuffix("_dB")
        roles = {r.get(prefix+"ValueRole", "") for r in quality_rows if math.isfinite(number(r.get(quality_axis)))} - {""}
        if len(roles) == 1 and row.get("QualityValueRole") not in roles:
            failures.append(f"row{index}:receiver_quality_role_relabelled")
        origins = {r.get(prefix+"Source", "") for r in quality_rows
                   if math.isfinite(number(r.get(quality_axis)))} - {""}
        if len(origins) == 1 and row.get("QualitySource") not in origins:
            failures.append(f"row{index}:receiver_quality_source_relabelled")
    return failures
