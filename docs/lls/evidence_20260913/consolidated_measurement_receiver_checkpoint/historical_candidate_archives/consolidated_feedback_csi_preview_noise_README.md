# Consolidated candidate with complete noise-capture lineage — 2026-09-13

Status: staged, unapplied, uncommitted, not pushed, NOT runtime-validated.
The 12 dB scenario remains unqualified. All three existing suites remain live
against unchanged source checkouts; their results do not validate this patch.

Base: 8412775e52ffba94f2cb9cb6dc9779d6ac54192a.
Patch: pending_consolidated_feedback_csi_preview_noise_20260913.patch.
22 files, 1,140 insertions, 94 deletions. Whitespace-strict git apply --check
passed against the base checkout. This does not prove MATLAB correctness.

## Additional measurement evidence retention

The prior raw-IQ audit recovered pre-RF noise power from post-RF samples and the
exact AGC trace, but only for the final occasion: earlier complete replays had
not been retained. The existing component's IQ is post-RF; its injected noise
variance is pre-RF. Comparing them without the actual stage gains is invalid.

The staged testPUCCHBaselineNoiseRF now:

- Stores the actual physical-owner pre-RF capture in PreRFIQ beside the unchanged
  post-RF IQ dataset, with identical row/branch and absolute sample bounds.
- Checks sample shape, finiteness, clock identity and the independently retained
  physical owner's pre-RF sample-power measurement.
- Writes one complete replay and observation identity per occasion in
  noise_replays/occasion_NNNNNN.mat, including the actual time-varying AGC trace.
- Binds each CSV score row to that replay's relative path and SHA-256, the two
  immutable waveform-chunk digests, the named IQ datasets, the injected variance
  domain, and measured total time-sample power at both planes.

These are retained physical observations, not synthesized or reconstructed
samples. No pre-RF sample or injected noise variance is passed to the practical
receiver. A pre-RF audit cannot replace post-RF disturbance estimation.

The complete decoder call, physical-owner process call, YAML threshold-resolution
block and existing summary/qualification calculations match the base source
exactly after newline normalization. This is a static scope check, not proof
that execution is unchanged. The test still labels its output as noise-only
component evidence and does not claim signal-present or conformance qualification.

## Consolidation and validation still required

All 21 earlier consolidated candidate files are preserved byte-for-byte; only
the existing noise-component test is added to the staged source set. This patch
supersedes pending_consolidated_feedback_csi_preview_20260913.patch and the older
overlapping feedback/CSI/CRC/PUCCH proposals. All older stages and bundles remain
preserved. Separate PRACH native-retention work is still NOT included.

The new capture path has not executed. It requires an explicit fresh
testPUCCHBaselineNoiseRF run after integration (it is not currently registered
in testAll), followed by independent checks of every capture/replay identity,
both IQ planes and gain/noise accounting. Preserve a new output directory under
logs; never replace the previous qualification samples to hide a failure.

The candidate also still requires the earlier leaf and integrated tests plus
all repository/skill-mandated testAll, NR/config/strict/grant/E2E/export checks on
the final source. No new MATLAB batch was launched with three live full suites
and approximately 0.8 GB free physical memory at the latest check.

Unfinished gates include actual false-ACK/missed-ACK detector qualification,
normal shared PUCCH/PUSCH HARQ integration, CSI calendar/measurement occasions,
DL timing/CFO/EVM fixture contracts, complete integrated measurements, 12 dB
qualification and the requested same-chain sweep. No threshold, noise or power
change is included to force these gates to pass.
