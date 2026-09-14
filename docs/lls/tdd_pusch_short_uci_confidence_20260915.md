# TDD PUSCH short-UCI confidence: implementation and codec checkpoint

NOT physical detector qualification, final-source full-suite acceptance,
all-measurement closure, or 12 dB acceptance. FDD feature work remains deferred.

## Root cause and retained failure

The physical no-UE-PUSCH episode documented in
`tdd_rejected_ul_due_harq_20260915.md` returned raw HARQ bit 1 with
DecodeUsable=true. Its 24 received LLR magnitudes were below 0.001.
`decodeUCIWithEvidence` previously accepted any binary output of the expected
short-UCI length. Lengths 1–11 have no CRC; a decoder choice alone was wrongly
treated as usable receiver evidence.

The original raw MAT, CSV and ACK are preserved. The new test includes the
unchanged 24 LLR values with the original MAT SHA-256. Independent Python/HDF5
inspection gives conditional posterior 0.5003980372090233 for the selected
one-bit ACK. This is a replay calculation, not another physical episode.

## Implemented decision

- `shortUCICodewordConfidence.m`: enumerate all legal words with public
  `nrUCIEncode`; calculate their likelihoods using the actual received LLRs.
  Repetitions are summed by the exact short-code base period; candidate-
  independent filler terms cancel. No transmitted bits, TB CRC, measured
  silence flag, power change, noise rescaling or synthetic samples are used.
- The statistic is the selected word's posterior under uniform codeword priors
  and a factorized bit-LLR model, conditional on a transmission hypothesis.
  It is NOT a signal-presence probability or a calibrated physical error rate.
  Correlated/approximate demapper LLRs still require physical qualification.
- Accept only a unique maximum-likelihood word matching the actual decoder's
  word and meeting the configured posterior threshold. Preserve raw bits even
  when unusable. Ambiguity, unusable decoder output, nonfinite informative
  LLRs or nonfinite scores cannot pass. Fixed infinite filler terms cancel.
- `decodeUCIWithEvidence` retains raw decoder usability separately from the
  confidence decision. CRC-protected UCI behavior is unchanged.
- `puschUCIFieldUsable` requires short confidence evidence, checks its model
  and word binding, and refuses stale usability/acceptance flags that disagree
  with the posterior. The existing normalizer consequently emits an erasure
  rather than promoting the saved weak raw ACK.

## Configuration and integration

Core YAML owns `phy.pusch.shortUCIDecision.algorithm=codeword_posterior` and
`minimumPosterior=0.99`. The latter is a candidate implementation policy
corresponding to a 1% conditional word-error budget, NOT the physical PUCCH
false-ACK gate and NOT a threshold mandated by 3GPP. It was not fitted to the
saved false-ACK episode; physical qualification is still required.

Scenario YAML exposes `pusch.short_uci_decision_algorithm` and
`pusch.short_uci_minimum_posterior`; both master configurations list them.
Validation requires a finite threshold strictly between 0.5 and 1.
`buildInternalConfig` maps overrides into the resolved receiver config.

Both `PUSCH_Rx` entry paths pass their resolved policy explicitly through
`receiveConfiguredUCI` / `PUSCHUCIDemultiplexer`, including first-stage CSI1
interpretation, final field decoding and `receiveInvariantUCI`.
Standalone codec APIs retain catalog defaults with the explicit evidence
label `core_catalog_component_default`; runtime policy is labeled
`explicit_receiver_policy`. A missing runtime config is not silently repaired
by a component default.

## Executed tests

MATLAB R2026a Update 4; candidate working tree based on `cc35e774`.
Source/HEAD stayed unchanged while MATLAB ran. Diagnostic AllowDirty was
explicit; these are not clean final-revision or full-suite qualification.

Log folder and sibling ZIP:
`logs/testall_20260914T203955052Z_b90fb4c0`.
MATLAB and launcher exited 0; engine 1500 and launcher 17800 exited.

| Test | Result |
| --- | --- |
| testPUSCHShortUCIConfidence | PASS, 48.63 s: 55 count/modulation cases, independent full-length log-likelihood comparison, strong/weak/tied inputs, original false ACK retained but rejected, nonfinite/filler checks, policy override and malformed-policy/word-binding guards |
| testPUSCHUCIReceiverEvidence | PASS, 2.10 s: existing codec/CRC assertions unchanged |
| testPUSCHIndependentReceiveBoundary | PASS, 3.93 s: 11 codec cases and existing oracle/context/mapping guards |
| testPUSCHPartialCSIReception | PASS, 3.97 s: 12 cases, explicit policy propagation and weak-ACK rejection during partial CSI reception |
| test6GParameterCatalog | PASS, 1.34 s |

SHA-256:

- matlab.log: `a933943cdeb20ba6548b9586b1ada328a666e921976d9c0e0ac2b00195c78da4`
- summary.json: `d38237c27e6a00128e4110ab689359eb14571b8fbd2d07eb46b19cbbe002a974`
- launcher.json: `decf71a6b9f384715187f72f5daa31ace0c9b2afb2eb8a4d1f78815c0ef40b91`

Raw logs remain local and ignored; this report does not upload the raw MATs.

## Required next evidence

1. Strengthened `testSharedRejectedULDueHARQ` now requires a receiver erasure
   on the actual no-UE-PUSCH capture after writing raw artifacts. This physical
   assertion has NOT yet run on this candidate. Pair it with the unchanged
   signal-present `testTDDSharedPUSCHNonemptyCompletion`.
2. Independent physical no-signal and signal-present PUSCH campaigns with
   frozen thresholds/confidence gates; original PUCCH 12/1024 failure and
   missed-ACK qualification remain open. A 0.99 posterior is not proof of
   <=1% physical false ACKs.
3. Clean final-source `testAll`; scenario/config/NR/channel, strict-proxy,
   scheduler, export/E2E, toolkit and hybrid guards required by repository
   skills. Codec-only passes do not replace them.
4. Existing-producer overlap, combined HARQ/CSI/SR, DAI gaps/wrap, stale/late
   cases, receiver-owned UL retransmission combining, production SR timers,
   complete integrated measurement/CSV/PNG verification and accepted 12 dB.
   Preserve the complete SINR sweep; do not promote qualified main yet.

## References

[MathWorks nrUCIDecode](https://www.mathworks.com/help/5g/ref/nrucidecode.html)
documents short-UCI ML decoding without CRC and modulation-dependent coding.
[MathWorks nrUCIEncode](https://www.mathworks.com/help/5g/ref/nruciencode.html)
provides the public legal-codeword encoder. The confidence decision here is
an explicitly configured receiver implementation, not a new 3GPP requirement.
