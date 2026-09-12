"""Recompute continuous transmitter IQ clock, sample and RF hashes from bytes."""
from __future__ import annotations

import hashlib
import math
import struct
import sys
from array import array
from pathlib import Path

MANIFEST = "waveform/csv/continuous_tx_iq_capture_manifest.csv"
SEGMENTS = "waveform/csv/continuous_tx_iq_segments.csv"


def validate_capture(root: Path, manifests: list[dict], segments: list[dict], io_path):
    if not __debug__:
        return ["continuous_iq_validation_requires_assertions_enabled"]
    failures: list[str] = []
    if not manifests or not segments:
        return ["continuous_iq_manifest_or_segments_missing"]
    ids = [r.get("EndpointID") for r in manifests]
    if len(ids) != len(set(ids)) or not all(ids):
        failures.append("endpoint_identity_not_unique")
    if set(ids) != {r.get("EndpointID") for r in segments}:
        failures.append("manifest_segment_endpoint_set_mismatch")
    def integer(row, key):
        value = float(row[key])
        if not math.isfinite(value) or value != int(value) or value < 0:
            raise ValueError("invalid integer " + key)
        return int(value)
    def truth(row):
        return (row.get("Source") == "actual_shared_physical_transmitter_output"
                and row.get("ApproximationMode") == "none"
                and all(row.get(k) == "0" for k in ("ProxyUsed", "FallbackFlag", "PlaceholderFlag")))
    for m in manifests:
        endpoint = m.get("EndpointID", "")
        try:
            ports = integer(m, "PortCount"); count = integer(m, "SampleCountPerPort")
            start = integer(m, "CaptureStartSample"); stop = integer(m, "CaptureEndSampleExclusive")
            assert ports > 0 and stop - start == count and count > 0
            assert truth(m) and m["CaptureStatus"] == "PASS"
            assert m["WaveformAuthority"] == "exact_shared_physical_runtime_stream"
            assert m["CapturePoint"] == "physical_antenna_output_after_composition_power_scaling_and_tx_rf_before_channel"
            assert m["BinaryLayout"] == "per_port_interleaved_I0_Q0_I1_Q1_little_endian"
            assert all(m[k] == "1" for k in ("ContinuousCoverage", "AllSchedulerSamplesIncluded", "CompositeTransmitterWaveform", "IncludesIntentionalSilence"))
            assert float(m["SampleRateHz"]) > 0 and float(m["CenterFrequencyHz"]) > 0
            precision = m["Precision"]; dtype = {"single": "f", "double": "d"}[precision]
            paths = m["PortFiles"].split("|"); hashes = m["PortFileSHA256"].split("|")
            assert len(paths) == len(hashes) == ports and len(set(paths)) == ports
            arrays = []; total_bytes = 0
            for path, expected in zip(paths, hashes):
                resolved = (root / path).resolve()
                assert resolved.is_relative_to(root.resolve()) and path.startswith("waveform/raw/")
                payload = io_path(resolved).read_bytes(); total_bytes += len(payload)
                assert hashlib.sha256(payload).hexdigest() == expected.lower()
                values = array(dtype)
                values.frombytes(payload)
                if sys.byteorder != "little":
                    values.byteswap()
                assert len(values) == count * 2 and all(map(math.isfinite, values))
                arrays.append(values)
            assert total_bytes == integer(m, "TotalFileBytes")
            rows = sorted([r for r in segments if r.get("EndpointID") == endpoint], key=lambda r: integer(r, "SegmentIndex"))
            assert len(rows) == integer(m, "SegmentCount") == integer(m, "SchedulerSlotCount")
            cursor = start; active_total = 0; peak_total = 0.
            for index, row in enumerate(rows, 1):
                first = integer(row, "StartSample"); end = integer(row, "EndSampleExclusive")
                assert truth(row) and row["Status"] == "PASS" and row["Direction"] == m["Direction"]
                assert integer(row, "SegmentIndex") == index and first == cursor and end > first and end <= stop
                assert integer(row, "SampleCountPerPort") == end-first and integer(row, "PortCount") == ports
                assert row["Precision"] == precision and row["RFHashExactMatch"] == "1"
                # Reconstruct MATLAB's column-major waveform hash, not merely
                # the file or configuration hash. Values are promoted to double.
                blocks = [a[2*(first-start):2*(end-start)] for a in arrays]
                real = array("d", (v for a in blocks for v in a[0::2]))
                imag = array("d", (v for a in blocks for v in a[1::2]))
                h = hashlib.sha256(("waveform:" + precision + ":").encode())
                h.update(struct.pack("<QQ", end-first, ports))
                for values in (real, imag):
                    encoded = array("d", values)
                    if sys.byteorder != "little":
                        encoded.byteswap()
                    h.update(encoded.tobytes())
                assert h.hexdigest() == row["WaveformSHA256"] == row["RFOutputWaveformSHA256"]
                active = sum(any(a[2*i] != 0 or a[2*i+1] != 0 for a in blocks)
                             for i in range(end-first))
                peak = max(max(map(abs, real)), max(map(abs, imag)))
                power = math.fsum(r*r + q*q for r, q in zip(real, imag)) / len(real)
                assert active == integer(row, "ActiveSampleCount")
                assert math.isclose(peak, float(row["PeakAbsComponent"]), rel_tol=1e-12, abs_tol=1e-15)
                assert math.isclose(power, float(row["MeanCompositePower"]), rel_tol=1e-12, abs_tol=1e-15)
                cursor = end; active_total += active; peak_total = max(peak_total, peak)
            assert cursor == stop and active_total == integer(m, "ActiveSampleCount")
            assert math.isclose(peak_total, float(m["PeakAbsComponent"]), rel_tol=1e-12, abs_tol=1e-15)
        except (AssertionError, KeyError, ValueError, OSError, OverflowError) as exc:
            failures.append(f"{endpoint}:continuous_iq_bytes_clock_or_truth_mismatch:{type(exc).__name__}:{exc}")
    return failures
