import hashlib
import sys
import subprocess
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from lls_continuous_iq_audit import validate_capture


def test_auditor_imports_without_site_packages():
    # MATLAB's publisher may use a standard-library-only Python executable.
    tool_dir = str(Path(__file__).resolve().parents[1] / "tools")
    result = subprocess.run([sys.executable, "-S", "-c",
        f"import sys; sys.path.insert(0, {tool_dir!r}); import lls_continuous_iq_audit"],
        capture_output=True, text=True)
    assert result.returncode == 0, result.stderr


def test_optimized_python_cannot_silently_disable_audit():
    tool_dir = str(Path(__file__).resolve().parents[1] / "tools")
    result = subprocess.run([sys.executable, "-S", "-O", "-c",
        f"import sys; sys.path.insert(0, {tool_dir!r}); from lls_continuous_iq_audit import validate_capture; "
        "sys.exit(0 if validate_capture(None, [], [], None) else 1)"], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr


def capture_fixture(tmp_path):
    root = tmp_path / "waveform/raw"; root.mkdir(parents=True)
    x = np.array([[0, 0], [.5, -.25], [.25, .125], [0, 0]], dtype="<f8")
    payload = x.tobytes(); (root / "port1.bin").write_bytes(payload)
    h = hashlib.sha256(b"waveform:double:")
    h.update(np.array([4, 1], dtype="<u8").tobytes())
    h.update(x[:, 0].tobytes()); h.update(x[:, 1].tobytes())
    common = dict(EndpointID="ue_1", Direction="UL", Precision="double", PortCount="1",
        Source="actual_shared_physical_transmitter_output", ApproximationMode="none",
        ProxyUsed="0", FallbackFlag="0", PlaceholderFlag="0", ActiveSampleCount="2", PeakAbsComponent="0.5")
    m = dict(common, CaptureStatus="PASS", WaveformAuthority="exact_shared_physical_runtime_stream",
        CapturePoint="physical_antenna_output_after_composition_power_scaling_and_tx_rf_before_channel",
        SampleRateHz="1000", CenterFrequencyHz="2350000000", CaptureStartSample="0", CaptureEndSampleExclusive="4",
        SampleCountPerPort="4", BinaryLayout="per_port_interleaved_I0_Q0_I1_Q1_little_endian",
        ContinuousCoverage="1", AllSchedulerSamplesIncluded="1", CompositeTransmitterWaveform="1",
        IncludesIntentionalSilence="1", PortFiles="waveform/raw/port1.bin", PortFileSHA256=hashlib.sha256(payload).hexdigest(),
        TotalFileBytes=str(len(payload)), SegmentCount="1", SchedulerSlotCount="1")
    s = dict(common, Status="PASS", StartSample="0", EndSampleExclusive="4", SampleCountPerPort="4",
        SegmentIndex="1", RFHashExactMatch="1", WaveformSHA256=h.hexdigest(), RFOutputWaveformSHA256=h.hexdigest(),
        MeanCompositePower=str(np.mean(np.sum(x*x, axis=1))))
    return m, s


def test_actual_bytes_and_silence_are_verified(tmp_path):
    m, s = capture_fixture(tmp_path)
    assert not validate_capture(tmp_path, [m], [s], lambda p: p)


@pytest.mark.parametrize("field,value", [("StartSample", "1"), ("RFOutputWaveformSHA256", "0"*64),
    ("ActiveSampleCount", "4"), ("MeanCompositePower", "12"), ("PortCount", "2"), ("FallbackFlag", "1")])
def test_corrupt_segment_is_not_qualified(tmp_path, field, value):
    m, s = capture_fixture(tmp_path); s[field] = value
    assert validate_capture(tmp_path, [m], [s], lambda p: p)


def test_corrupt_file_or_unsealed_capture_is_not_qualified(tmp_path):
    m, s = capture_fixture(tmp_path)
    (tmp_path / m["PortFiles"]).write_bytes(b"changed")
    assert validate_capture(tmp_path, [m], [s], lambda p: p)
    assert validate_capture(tmp_path, [], [s], lambda p: p)
