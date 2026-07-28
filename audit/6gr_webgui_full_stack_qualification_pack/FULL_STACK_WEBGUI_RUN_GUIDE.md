# WebGUI run and inspection guide — full-stack qualification suite

## What this scenario is

`lls_webgui_full_stack_sinr_geometry_qualification` is one WebGUI-selected campaign containing multiple child subcases. The child environments are separated so controlled AWGN, LOS, NLOS/O2I, interference, RF and handover assumptions do not corrupt one another.

## Presets

### Comprehensive smoke

- Functional execution of every declared component.
- Requires 746 artifacts: 447 CSV and 299 PNG.
- Small bounded counts; intended to find integration defects.
- Not publication-quality statistics.

### Deep acceptance

- Same YAML and same orchestrator.
- Requires 1248 artifacts: 623 CSV and 625 PNG.
- Includes impact-analysis contracts and larger trial/slot counts.
- Expensive.

## How to launch

1. Start the canonical React/FastAPI WebGUI on `0.0.0.0` using the secured local/LAN profile.
2. Log in.
3. Select **Full-Stack SINR + Geometry Qualification Suite**.
4. Select `comprehensive_smoke`.
5. Open Source, Effective and Resolved YAML.
6. Confirm carrier, SNR grid, LOS/NLOS probes, RF probes, L2/L3 and artifact policy.
7. Record the resolved YAML SHA-256.
8. Start the run.

## Live page

Confirm that every `SC-00` through `SC-30` subcase appears. A missing subcase is a failure.

## Results pages

Inspect in this order:

1. Full Stack Overview — acceptance, component coverage and artifact completeness.
2. TX Chain — coding/modulation/reference signals/precoding/waveform/power/RF TX.
3. RX Chain — synchronization/estimation/equalization/demapping/decoding/SINR/EVM.
4. Control and Access — SSB/SIB1/PRACH/PDCCH/PUCCH/DCI/UCI.
5. MIMO and Beam — arrays, codebooks, ranks, covariance, beams and TCI.
6. Channel and RF — LOS/NLOS/O2I/blockage/CIR/Doppler/interference/RF impairments.
7. MAC and Protocol — HARQ/scheduler/BSR/PHR/SR/TA/RLC/PDCP/SDAP/RRC/traffic/handover.
8. Validation — all rules and every failure.
9. Artifact Explorer — all selected-preset artifacts.

## Final command

```bash
python tests/vectors/full_stack_qualification/verify_full_stack_qualification_artifacts.py \
  <run-output-directory> \
  tests/vectors/full_stack_qualification \
  --preset comprehensive_smoke
```

Exit code must be zero.

## Interpretation

A PASS demonstrates bounded functional integration of every declared component and correct artifact publication for the selected profile. It does not prove every 3GPP parameter combination or publication-grade performance statistics. Use `deep_acceptance` and the full domain campaigns for those claims.
