# Consolidated feedback/CSI candidate and retained EVM audit — 2026-09-13

Status: staged, NOT applied, committed or uploaded. The consolidated production source is NOT runtime-validated and the 12 dB scenario is NOT qualified.

Base revision: 8412775e52ffba94f2cb9cb6dc9779d6ac54192a.

## Single staged source patch

pending_consolidated_feedback_csi_20260913.patch contains 19 files (1,020 insertions, 81 deletions). git apply --check --whitespace=error passed against the base revision. A static search found no remaining candidate-function calls in the production-named stage.

The patch combines the previously tested scheduled HARQ mapper/preflight/common commit candidate, native UCI CRC correction, independent PUCCH trial receive boundary, CSI clock-domain publisher/consumer work, and the new shared-DL completion hook. Six proposed permanent tests are registered in testAll.

The completion hook now binds CSI rows after actual shared DL reception, before coordinator HARQ/CSI commits and primary aggregation. It uses the prepared transmission, complete received capture, receiver timing, and nonfaulted physical/event owner clock and epoch. The strict binder rejects conflicting pre-existing timestamps instead of rebinding them. Empty CSI tables remain empty. No power, noise, channel estimate, decoded bit, threshold or measurement value is adjusted.

This supersedes the overlapping CRC-only, independent-PUCCH-trial, scheduled HARQ mapper/preflight, and CSI publisher/consumer source proposals. Do NOT apply those overlapping patches again after this one. Earlier candidates, archives and receipts remain preserved. The PRACH native-retention patch is separate and is NOT included here.

The stage is a set of proposed source files, not a fourth Git worktree. Do not add its package directories to MATLAB's path while any existing suite is running.

## Validation boundary

Earlier isolated HARQ, CRC and PUCCH adapter passes remain evidence for those exact candidates, not this combined source. The CSI selector regression passed. Its publisher/consumer test then stopped with Out of memory; the physical-clock consumer test never ran. The binary-validity helper guard, consolidated runtime class, new shared-DL hook and strict no-rebinding guard have not been executed. No final-source testAll pass is claimed.

All three pre-existing suites remain running at the user's direction, with unchanged source checkouts. A further memory-heavy run was not launched. After an integration checkout becomes available, apply/review the consolidated source together with the separate remaining patches, run the targeted and repository/skill-required full/NR/config/strict/grant/E2E/export tests, then perform integrated measurement and 12 dB qualification. Do not commit/push this as a qualified baseline merely because its patch applies.

Still unfinished: normal combined scheduled PUCCH/PUSCH gNB obligations and HARQ consumers, CSI/SR reporting calendars and independent CSI measurement occasions, baseline false/missed ACK qualification, the DL timing/CFO/EVM fixture contracts, and integrated power/noise/loss/all-measurement/export closure. The 19-file patch does not assert those gaps are solved.

## Retained DL EVM arithmetic audit

audit_retained_dl_evm.ps1 independently parsed all 3,335 unfitted equalized/reference symbol pairs from the retained CSI timing component run. It recomputed EVM=0.0560761656653059 (5.60761656653059%), exactly matching the trial export. Residual power was 0.00314453635572283. Per-OFDM-symbol EVM is retained in the audit CSV; raw inputs and their SHA-256 identities are preserved.

The component fixture declares sample noise variance 1e-13 and a 77 dB analytic connector; the export records sample-to-grid variance gain 512. Under its unit occupied-RE, ideal single-branch connector reference, the nominal noise EVM is sqrt(512*1e-13/10^(-77/10))=0.0506564767445549 (about 5.1%). This is a declared-reference calculation, not a measured receiver channel or a general MIMO bound. It explains why the fixture's 2% residual limit cannot be treated as a valid high-SNR expectation for these inputs. No assertion or noise value was changed.

CFOApplied=0 and EstimatedCFO_Hz=NaN are consistent with disabled CFO correction in this fixture. The old unconditional near-zero CFO assertion does not account for that applicability condition.

The CSV's SNR_dB=12 is the configured component label; the fixture injected fixed noise, reporting actual sample SNR about 19.9643 dB and post-equalization SINR about 25.0244 dB. This captured component is NOT an integrated 12 dB operating-point run. The audit proves exported EVM arithmetic, not 3GPP conformance, complete noise calibration, or baseline success.
