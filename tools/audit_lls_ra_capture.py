"""Read-only arithmetic audit of retained shared-stream random-access captures.

This verifies captured evidence, not detector performance or full NR conformance.
The optional report directory must be outside the measured run.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
from pathlib import Path

from audit_lls_run_exhaustive import io_path

SOURCE = "control/csv/ra_runtime_stage_waveforms.csv"


def number(row, field):
    try:
        value = float(row.get(field, ""))
        return value if math.isfinite(value) else None
    except (TypeError, ValueError):
        return None


def audit_rows(rows, require_complete=False, awgn_reference=None):
    checks = []

    def check(index, stage, name, passed, details=""):
        checks.append(dict(row=index, stage=stage, check=name,
                           passed=bool(passed), details=details))

    observed = set()
    for index, row in enumerate(rows, 1):
        stage = row.get("StageName", "")
        observed.add(stage)
        expected_direction = {"Msg1": "UL", "Msg2": "DL", "Msg3": "UL", "Msg4": "DL",
                              "RRCSetupComplete": "UL"}.get(stage)
        direction = row.get("Direction")
        check(index, stage, "stage_direction", expected_direction is not None and direction == expected_direction)
        check(index, stage, "shared_received_not_self_loop",
              row.get("RuntimeTransportMode") == "shared_physical_waveform_stream" and
              row.get("WaveformSource") == "shared_physical_stream_received_post_adc_gain_compensated" and
              number(row, "RuntimeStageWaveformUsed") == 1 and number(row, "SelfLoopWaveformUsed") == 0)
        start, end, fs, count, completion = (number(row, field) for field in (
            "ObservationStartSample", "ObservationEndSampleExclusive", "ObservationSampleRateHz",
            "RxSampleCount", "ObservationCompletionTime_s"))
        bounds = all(v is not None for v in (start, end, fs, count, completion))
        bounds = bounds and start >= 0 and end > start and fs > 0 and count > 0
        bounds = bounds and all(v == int(v) for v in (start, end, count))
        check(index, stage, "capture_sample_count", bounds and end-start == count)
        check(index, stage, "capture_completion_clock", bounds and
              math.isclose(completion, end/fs, rel_tol=0, abs_tol=1e-12))
        try:
            segments = json.loads(row.get("PhysicalExecutionSegmentsJSON", ""))
            assert bounds and isinstance(segments, list) and segments
            intervals = []
            for segment in segments:
                a, b = segment["StartSample"], segment["EndSampleExclusive"]
                assert all(isinstance(v, (int, float)) and not isinstance(v, bool)
                           and math.isfinite(v) and v == int(v) for v in (a, b))
                assert a >= 0 and b > a
                assert segment["Source"] == "composed_tx_retained_rf_per_link_channel_sum_receiver_noise_rf"
                if b > start and a < end:
                    intervals.append((max(a, start), min(b, end)))
            cursor = start
            for a, b in sorted(intervals):
                assert a == cursor  # Reject both gaps and duplicate/overlapping execution claims.
                cursor = b
            assert cursor == end
            coverage = True
        except (ValueError, TypeError, KeyError, AssertionError):
            coverage = False
        check(index, stage, "contiguous_physical_execution_coverage", coverage)
        link = row.get("RuntimeChannelLinkKey", "")
        check(index, stage, "channel_direction_binding", direction in {"UL", "DL"} and
              link.startswith(f"dir={direction};") and number(row, "RuntimeChannelStateUsed") == 1)
        if row.get("NoiseOperatingMode") == "standalone_awgn_snr_argument":
            # Normalized waveform energy is not dBm/mW. The saved resolved
            # scenario supplies the independent reference; never infer it
            # from the same noise variance being checked.
            requested, measured, reference, expected, residual = (number(row, f) for f in (
                "AppliedTxPower_dB_re_UnitOccupiedRE_Es", "MeasuredTxPowerBeforeRF_dB_re_UnitOccupiedRE_Es",
                "ReferenceOutputPower_dB_re_UnitOccupiedRE_Es", "ExpectedWaveformPower_re_UnitOccupiedRE_Es",
                "TxPowerClosureError_dB"))
            normalized = (row.get("PowerNormalizationPolicy") == "unit_occupied_re_fixed_esn0"
                          and row.get("AppliedTxPowerValueRole") == "normalized_waveform_power_not_physical_dbm"
                          and number(row, "PhysicalDevicePowerClaim") == 0
                          and all(number(row, f) is None for f in (
                              "AppliedTxPower_dBm", "MeasuredTxPowerBeforeRF_dBm", "ReferenceOutputPower_dBm",
                              "ExpectedEmittedPower_mW", "NoiseVariancePreFrontEnd_mW")))
            check(index, stage, "normalized_power_domain_not_device_power", normalized)
            power = (all(v is not None for v in (requested, measured, reference, expected, residual))
                     and expected > 0)
            check(index, stage, "normalized_tx_power_closure", power and
                  math.isclose(requested, measured, rel_tol=0, abs_tol=1e-8) and
                  math.isclose(reference, measured, rel_tol=0, abs_tol=1e-8) and
                  math.isclose(expected, 10**(measured/10), rel_tol=1e-10) and
                  abs(residual) < 1e-8)
            policy = awgn_reference or {}
            snr, energy = number(policy, "snr_db"), number(policy, "awgn_reference_re_energy")
            grid, sample, gain, applied, recorded_snr = (number(row, f) for f in (
                "ReferenceAWGNGridNoiseVariance", "ReferenceAWGNSampleNoiseVariance",
                "SampleToGridNoiseVarianceGain", "NoiseVariancePreFrontEnd_re_UnitOccupiedRE_Es",
                "RequestedAWGNReferenceSNR_dB"))
            valid = (snr is not None and energy is not None and energy > 0
                     and all(v is not None and v > 0 for v in (grid, sample, gain, applied))
                     and recorded_snr is not None and number(row, "NoiseApplied") == 1)
            check(index, stage, "fixed_awgn_reference_noise_closure", valid and
                  math.isclose(recorded_snr, snr, rel_tol=0, abs_tol=1e-10) and
                  math.isclose(grid, energy * 10**(-snr/10), rel_tol=1e-10) and
                  math.isclose(sample * gain, grid, rel_tol=1e-10) and
                  math.isclose(applied, sample, rel_tol=1e-10),
                  "Saved configured reference Es/SNR -> occupied grid variance -> sample variance, not receiver-estimator qualification.")
            reference_kind = "unit" if energy == 1 else "configured"
            noise_source = ("fixed_unit_occupied_re_esn0_canonical_ofdm_transform" if energy == 1 else
                            "fixed_configured_occupied_re_esn0_canonical_ofdm_transform")
            check(index, stage, "fixed_awgn_noise_authority", valid and
                  row.get("NoiseVarianceSource") == noise_source and
                  row.get("SharedNoiseCalibrationSource") ==
                  f"fixed_once_from_{reference_kind}_occupied_re_energy_and_canonical_ofdm_noise_transform")
            continue
        requested, measured, residual = (number(row, field) for field in (
            "AppliedTxPower_dBm", "MeasuredTxPowerBeforeRF_dBm", "TxPowerClosureError_dB"))
        reference, activity, expected = (number(row, field) for field in (
            "ReferenceOutputPower_dBm", "FullBWPActivityFactor", "ExpectedEmittedPower_mW"))
        power = all(v is not None for v in (requested, measured, residual, reference, activity, expected))
        policy = row.get("PowerNormalizationPolicy", "")
        power = power and activity > 0 and expected > 0 and policy in {
            "active_ofdm_total_power", "fixed_epre_over_configured_bwp"}
        check(index, stage, "tx_power_reference_evidence", power,
              "Needs emitted and reference power plus the actual normalization activity factor; budget is not always emitted power.")
        check(index, stage, "tx_power_closure", power and
              math.isclose(reference, measured-10*math.log10(activity), abs_tol=1e-8) and
              math.isclose(residual, reference-requested, abs_tol=1e-8) and
              math.isclose(expected, 10**(requested/10)*activity, rel_tol=1e-10) and
              abs(residual) < 1e-8)
        if row.get("NoiseOperatingMode") == "receiver_noise_figure_thermal_noise":
            psd, bandwidth, variance = (number(row, field) for field in (
                "ThermalNoisePSD_mWPerHz", "ThermalSampleNoiseBandwidth_Hz", "NoiseVariancePreFrontEnd_mW"))
            noise = all(v is not None and v > 0 for v in (psd, bandwidth, variance))
            check(index, stage, "thermal_noise_psd_bandwidth_closure", noise and
                  math.isclose(variance, psd*bandwidth, rel_tol=1e-10, abs_tol=0))
        else:
            check(index, stage, "noise_mode_audit_supported", False, "This audit requires thermal-noise evidence.")
    check(0, "all", "received_stage_rows_present", bool(rows))
    if require_complete:
        check(0, "all", "all_four_stages_observed", {"Msg1", "Msg2", "Msg3", "Msg4"} <= observed)
    return dict(scope="shared_ra_capture_arithmetic_only_not_radio_qualification",
                row_count=len(rows), stages=sorted(observed), checks=checks,
                passed=all(item["passed"] for item in checks), terminal_qualification=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_folder", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()
    root = args.run_folder.resolve()
    if args.output and args.output.resolve().is_relative_to(root):
        parser.error("Audit output must not modify the measured run.")
    payload = io_path(root / SOURCE).read_bytes()
    rows = list(csv.DictReader(io.StringIO(payload.decode("utf-8-sig"))))
    reference, reference_hash = None, None
    if any(row.get("NoiseOperatingMode") == "standalone_awgn_snr_argument" for row in rows):
        config_bytes = io_path(root / "meta/scenario_config_resolved.json").read_bytes()
        reference = json.loads(config_bytes)["simulation"]
        reference_hash = hashlib.sha256(config_bytes).hexdigest()
    report = audit_rows(rows, args.require_complete, reference)
    report["resolved_config_sha256"] = reference_hash
    report.update(source=SOURCE, source_run=str(root), source_sha256=hashlib.sha256(payload).hexdigest())
    if args.output:
        io_path(args.output).mkdir(parents=True, exist_ok=True)
        snapshot = io_path(args.output / (report["source_sha256"] + ".csv"))
        snapshot.write_bytes(payload)
        io_path(args.output / (report["source_sha256"] + ".json")).write_text(
            json.dumps(report, indent=2, allow_nan=False), encoding="utf-8")
    print(json.dumps(report, indent=2, allow_nan=False))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
