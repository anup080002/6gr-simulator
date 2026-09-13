# HARQ feedback disposition and single-owner repair — 2026-09-13

Development handoff only: **no full-suite or 12 dB qualification**.

## Correctness repair

The HARQ entity already rejected feedback for a stale process attempt, but its
callers could still clear newer decoder buffers, update scheduler throughput
and link adaptation, and export a successful state change. In coupled mode,
the runtime and its PF/RR scheduler also called the same entity twice.

The entity now returns its actual accepted/rejected disposition. Runtime
callers change dependent buffers and adaptation only on acceptance. A
constructor-bound ownership field makes the runtime the sole HARQ feedback
owner in coupled execution; standalone schedulers remain their own owner and
reject stale feedback before modifying statistics. This is execution
ownership, not a scenario setting or a per-row bypass.

Actual received stale UCI remains an observed, finalized receiver result in
the primary trace. Its HARQ state-change flags are false; false-ACK scoring is
retained independently. New disposition columns use NaN for unprocessed rows,
not invented outcomes. Physical-occasion records retain accepted/stale bit
counts. Accepted DTX still performs its real HARQ transition.

No power, noise, path loss, receiver threshold, bit decision, PHY decoding,
TBS, or acceptance limit was changed. Normal combined-UCI independent mapping
is **not** completed by this reducer repair.

## Reproduction and verification

| Evidence directory under evidence_20260913 | Result and scope |
| --- | --- |
| harq_feedback_ownership_reproduction | Original duplicate-callback failure (exit 1), earlier known-defect reproduction, original failing test source and initial disposition unit log |
| harq_feedback_disposition_01 | Six focused tests passed before canonical stale-export and ownership changes |
| harq_feedback_disposition_02 | Eighteen tests passed, including NR/config, LLS, strict, exports, grants and both E2E guards; before scheduler ownership change |
| harq_feedback_ownership_03 | Ten focused tests passed on final repair sources, including 22 PF/RR ownership cases, PUSCH UCI, both shared-waveform clock fixtures, received ACK/NACK/DTX and grants |

The original failing test snapshot is preserved as .m.txt to avoid MATLAB
path shadowing. Its final version adds explicit AMC/baseline configuration so
OLLA is exercised; its original failing assertion was not weakened. Declared
MAC reducer fixtures are not waveform qualification. The shared-clock tests
execute their own PHY fixtures, not the 12 dB baseline.

All three batch launchers exited zero with focused_tests summaries and
baseline_12db_qualified=false on MATLAB R2026a Update 4. Their original source
snapshots differ as listed in
[evidence receipt](evidence_20260913/harq_feedback_disposition_receipt.json).
All 28 archived artifact copies were SHA-256 checked against their originals.
The final eight source hashes were checked after the ten-test process exited.
Raw logs and ZIPs remain in the development checkout's logs/ folder.

## Remaining work and publication

The next mandatory NR/export/E2E guard batch and full testAll must run on the
committed, frozen final source. Full suites already running at 2faf8d91 and
ef053a47 must finish unchanged; neither validates this newer repair.
Publishing this descendant for the requested other-server testAll does not
turn pending regression into a pass.

Still open: normal received Type-2 codebook/independent gNB mapping (including
missed DCI, DAI wrapping and combined CSI/PUSCH UCI), PUCCH detector
qualification, timing and complete power/noise/measurement/CSI/SRS/beam
evidence, and the baseline's own CSV/PNG/IQ acceptance audit. The retained
two-bit noise-only case remains 12 false ACK bits / 1024 positions, above its
configured 1% reference; this patch does not repair or conceal that result.

After those gates and the actual 12 dB run pass, publish its revision-bound
evidence before running the same-chain sweep
[-30,-20,-10,0,10,12,20,30,40]. Low-SNR decode failures are data, not grounds to
manufacture a pass. The 58-slot baseline is not an all-impairments campaign.

NR-validation guided the single-owner and grant-state checks; result-integrity
guided the separation between received evidence and accepted state changes.
