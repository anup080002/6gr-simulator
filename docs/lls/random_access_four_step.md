# Four-Step Random Access Evidence

This note documents the strict four-step random-access anchor implemented for
`AUD-RA-001`. It is scoped to unrestricted contention-based RA. Restricted-set
PRACH and full N_CS validation remain tracked under `AUD-PRACH-001`.

## Runtime Chain

The strict path is `sixgr.mac.ra.RandomAccessProcedure`, which delegates to
`sixgr.phy.ra.runFourStepRA`. A successful run requires all of these measured
stages to pass:

1. MSG1 PRACH waveform generation and receiver correlation detection.
2. MSG2 RA-RNTI PDCCH decode and MAC RAR bytes recovered from PDSCH.
3. Msg3 PUSCH generated from the decoded RAR UL grant and decoded at the gNB.
4. Msg4 temp-C-RNTI PDCCH/PDSCH contention-resolution identity match.

The legacy `sixgr.l3.rrc.RACHProcedure.buildRAR_gNB` abstract helper is blocked
in strict mode so it cannot be mistaken for this waveform-backed RA path.

## Evidence Artifacts

Runs with `WriteArtifacts=true` export:

- `control/csv/ra_attempts.csv`
- `control/csv/ra_state_transitions.csv`
- `control/csv/msg1_prach_detection.csv`
- `control/csv/msg2_rar_trials.csv`
- `control/csv/msg2_pdcch_candidates.csv`
- `control/csv/msg3_pusch_trials.csv`
- `control/csv/msg4_contention_resolution.csv`
- `control/csv/ra_timer_events.csv`
- `control/csv/ra_negative_trials.csv`
- `control/csv/ra_collision_trials.csv`
- `control/csv/ra_oracle_guard.csv`
- `control/csv/ra_artifact_manifest.csv`
- `reports/json/ra_config_binding.json`
- `reports/json/msg2_rar_decoded.json`
- `reports/json/msg3_payload_decoded.json`
- `reports/json/msg4_contention_resolution_decoded.json`

Primary rows are empty or failed when evidence is absent. No fallback/proxy rows
are promoted into strict RA artifacts.

## Focused Tests

Use MATLAB R2024a:

```matlab
setup6GRSimToolkit('Verbose', false);
testAll('Names', {'testFourStepRASuccessAWGN','testRAConfigBinding', ...
    'testMsg1PRACHWaveformDetection','testMsg2RARWaveformDecode', ...
    'testMsg3PUSCHFromRARGrant','testMsg4ContentionResolution'}, ...
    'Verbose', false);
testAll('Names', {'testRANegativeWrongRARNTI','testRANegativeRARWindowExpiry', ...
    'testRANegativeRAPIDMismatch','testRANegativeMsg3CrcFail', ...
    'testRANegativeMsg4IdentityMismatch','testRACollisionSamePreamble'}, ...
    'Verbose', false);
testAll('Names', {'testRAOracleGuard','testRAArtifactSchemas'}, ...
    'Verbose', false);
```

Long mixed RA batches can expose a MATLAB R2024a access violation in repeated
5G Toolbox encode/decode calls. The tests are therefore structured to reuse one
strict-success fixture for positive assertions and to validate negative/artifact
cases in focused chunks.
