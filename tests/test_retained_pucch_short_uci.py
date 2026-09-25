"""Independent-analysis checks; not PHY acceptance or detector qualification."""
import importlib.util
from pathlib import Path

import numpy as np
import pytest

SPEC = importlib.util.spec_from_file_location("pucch_replay", Path(__file__).parents[1] / "scripts/analyze_retained_pucch_short_uci.py")
REPLAY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPLAY)


def test_scrambling_matches_published_mathworks_example():
    # https://www.mathworks.com/help/5g/ref/nrpucchprbs.html
    assert REPLAY.scrambling(17, 120, 15).tolist() == [0, 1, 1, 0, 1, 1, 0, 1, 0, 0, 0, 0, 1, 1, 1]


@pytest.mark.parametrize("count", [3, 7, 11])
def test_high_snr_and_zero_gain(count):
    words, ref = REPLAY.references(count, 32, 1, 1)
    index = 2**count - 3
    gain = np.linspace(.2, .8, 32) * np.exp(1j * np.linspace(0, 1, 32))
    variance = np.linspace(.0001, .0002, 32)
    bits, p, maxima = REPLAY.decode_with_response(gain * ref[:, index], gain, variance, count, 1, 1)
    np.testing.assert_array_equal(bits, words[index])
    assert p > .999 and maxima == 1
    _, p, maxima = REPLAY.decode_with_response(ref[:, index], gain * 0, variance, count, 1, 1)
    assert p == 2**-count and maxima == 2**count


def test_qpsk_llr_equals_four_point_marginal_likelihood():
    rng = np.random.default_rng(25925073)
    bits = np.array([[0, 0], [0, 1], [1, 0], [1, 1]])
    ref = ((1 - 2 * bits[:, 0]) + 1j * (1 - 2 * bits[:, 1])) / np.sqrt(2)
    y = rng.normal(size=64) + 1j * rng.normal(size=64)
    g = rng.normal(size=64) + 1j * rng.normal(size=64)
    v = .1 + rng.random(64)
    logp = -np.abs(y[:, None] - g[:, None] * ref)**2 / v[:, None]
    expected = np.column_stack([np.logaddexp.reduce(logp[:, bits[:, b] == 0], axis=1) -
                                np.logaddexp.reduce(logp[:, bits[:, b] == 1], axis=1) for b in range(2)])
    matched = np.conj(g) * y
    closed = 2 * np.sqrt(2) * np.column_stack([matched.real / v, matched.imag / v])
    np.testing.assert_allclose(expected, closed, rtol=1e-12, atol=1e-12)


def test_invalid_variance_rejected():
    with pytest.raises(ValueError):
        REPLAY.decode_with_response(np.ones(32), np.ones(32), np.zeros(32), 11, 1, 1)
