# PUCCH explicit-noise authority repair

Status: focused tests pass; not full-suite, detector or integrated 12 dB acceptance.

## Observed failure and cause

`testULNoiseVarianceValidation` failed on both retained full-suite revisions
73867a4 and 9bb69197 at the original assertion requiring explicit sample noise
variance to be converted to the receiver grid domain. In
`+sixgr/+phy/+pucch/PUCCHReceiver.m`, the condition
`estimateNoise || isempty(rintGrid)` replaced an explicitly provided variance
with the DM-RS estimate whenever no interference covariance was supplied.
This made the declared `provided` policy conditional on an unrelated input.

The repair selects DM-RS disturbance authority only for the explicit
`received_dmrs_estimate` mode. Provided sample-domain noise is converted once;
provided grid-domain noise retains its units. Received-estimate validation,
per-resource channel estimation, covariance handling, physical waveforms,
CRC decisions and detector thresholds are unchanged.

## Verification

MATLAB R2026a batch exited 0; retained log
`logs/pucch_noise_authority_20260916.log`, SHA256
`1956628E7C287A2323BC808A9CD2EE6DABA7F28A13953F8FC0ED27C47F6C557D`.

- `testULNoiseVarianceValidation`: PASS, original assertions unchanged.
- `testPUCCHReceivedNoiseEstimation`: PASS. Added sample/grid provided-policy
  checks without covariance for Formats 1-4, including equalizer input
  variance. Existing AGC/ADC received-estimate decoding and covariance
  double-counting rejection assertions remain and pass.
- `testPUCCHReceiverCRC`: PASS. Desired and wrong-RNTI physical waveforms are
  both detected; only the desired payload passes CRC.

The d05c1441 5 MHz TDD / 12 dB scenario was already frozen/queued, and started
at 06:04:42 IST after user-approved retirement of older validations. It does
not contain this later repair. Normal shared reception uses explicit
received-estimate/noncoherent modes; these were not changed by this patch.
Do not mutate its checkout or attribute its results to this later revision.

Full `testAll`, NR/config/LLS/strict/scheduler/export/E2E guards, final-source
integration and all-measurement acceptance remain required. The retained
noise-only false-ACK qualification failure is not closed by these tests.
