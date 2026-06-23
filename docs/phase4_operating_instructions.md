# Phase 4 Operating Instructions

Use the strict RA mini-anchor first. Do not run the full mobile scenario as a
Phase4Ok claim until the pending limitations are resolved.

## Strict RA Anchor

```matlab
setup6GRSimToolkit('Verbose', false);
cfg = raStrictAnchorConfig();
res = sixgr.phy.ra.runFourStepRA(cfg, 'WriteArtifacts', true);
assert(logical(res.StrictOk));
```

## Decoded SIB1 To RA Integration

```matlab
setup6GRSimToolkit('Verbose', false);
testSIB1ToFourStepRAIntegration;
```

## Scenario Runner

```matlab
setup6GRSimToolkit('Verbose', false);
out = sixgr.lls6g.runners.runSingle( ...
    'configs/lls/lls_ra_four_step_strict_mini_anchor.yaml', ...
    'results', ...
    'phase4_ra_anchor');
```

## Required Evidence Review

Check these artifacts before claiming any RA completion:

- `control/csv/rach_config_from_decoded_sib1.csv`
- `control/csv/ra_attempts.csv`
- `control/csv/msg1_prach_detection.csv`
- `control/csv/msg2_rar_trials.csv`
- `control/csv/msg2_pdcch_candidates.csv`
- `control/csv/msg3_pusch_trials.csv`
- `control/csv/msg4_contention_resolution.csv`
- `control/csv/ra_oracle_guard.csv`
- `reports/csv/phase4_decoded_config_ownership_audit.csv`

## Stop Boundary

Do not continue into RRCSetupComplete, connected-mode PUCCH, dynamic
connected-mode scheduling, general HARQ, SRS, TRS, rank adaptation, MU-MIMO, or
user-plane throughput under Phase 4.
