# 6GR two-mode end-to-end integration pack

This pack assumes the subsystem phases, including the canonical waveform phase, are implemented. It is the integration phase that proves the fixed-SNR calibration mode and geometry/network mode share one production PHY/waveform/receiver stack.

## Recommended placement

```text
tests/vectors/integration/
```

## Start

Paste `CODEX_PROMPT_16_END_TO_END_TWO_MODE_INTEGRATION_WITH_ACTUAL_RUNS.md` into Codex at repository root.

## Pack checks

```bash
python tests/vectors/integration/verify_integration_pack.py tests/vectors/integration
```

## Final artifact check

```bash
python tests/vectors/integration/verify_integration_artifacts.py artifacts/integration_acceptance tests/vectors/integration
```

The verifier is intentionally fail-closed. It does not prove the MATLAB implementation by itself; it checks the output of the mandatory actual-run suite.
