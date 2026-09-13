# Canonical PUCCH noise evidence and validation checkpoint

This supersedes the **running-noise-test status only** in
`pucch_receiver_only_implementation_20260913.md`. It does not close the gNB
missed-DCI receive-window, Type-2 runtime, Phase-05, detector qualification,
final baseline or long impairment-enabled 6G/NR gates.

## Completed physical component

The receiver revision's process completed with exit 0. Its final negative
identity/context tests and Formats 0–4 waveform-equivalence tests passed.
The physical-owner noise/RF loop completed 512 occasions, with one- and
two-bit receive hypotheses per occasion. It used the canonical receiver,
length-only receiver context and receiver-owned assignment, without active
transmitter-to-receiver links or UE transmit-power state.

The unmodified completed artifacts and log are retained in
`evidence_20260913/pucch_canonical_receiver_noise_01/`; large MAT artifacts use
the repository's existing Git LFS policy. `source_provenance.json` records
the source revision, command, exit status and bounded scope.

| HARQ hypothesis | False detections | False ACK bits / positions | Empirical fraction | Configured reference |
| --- | --- | --- | --- | --- |
| 1 bit | 8 | 2 / 512 | 0.390625% | 1% |
| 2 bits | 16 | 12 / 1024 | 1.171875% | 1% — exceeded |

All 1,024 common CSV observation rows match the earlier direct-Toolbox
component; the largest detector-metric difference is zero. Every retained
complex IQ element is exactly equal across the two runs (HDF5 dimensions
2 by 3,932,160). The MAT-file container hashes differ. This is deterministic
same-noise equivalence, not a second independent statistical sample; do not
combine the runs to double the noise-trial denominator.

## Repeatable CSV / PNG audit

`tools/audit_pucch_noise_evidence.py` reads the retained configuration, CSVs
and complex IQ, then validates:

- configured occasion/hypothesis counts and unique observation identities;
- paired hypotheses sharing exactly one physical observation;
- finite IQ, retained IQ file hash, sample indexing and receiver dimensions;
- configured detection threshold, metric/decision consistency and scope;
- canonical receiver metadata and unique assignment/context digest shape;
- independently aggregated false detections, false-ACK bits, denominators,
  empirical reference flags and the exported IID-occasion upper bound.

It writes a separate review directory and refuses to overwrite either source
evidence or an existing review. It does not re-decode IQ, validate the contents
behind assignment digests, or qualify acquisition, missed ACK or conformance.
The IID bound concerns **occasions with any false ACK**, not individual bits.

Reproduce the review using a **new** output directory:

```powershell
python tools/audit_pucch_noise_evidence.py docs/lls/evidence_20260913/pucch_canonical_receiver_noise_01 <new-review-directory>
```

The retained review is
`evidence_20260913/pucch_canonical_receiver_noise_audit_01/`. Its JSON binds
the producer, source files, recomputed CSV and PNG by SHA256. The absolute
source path records the isolated checkout used at generation; the source
folder is also retained alongside the review for relocation after merge.

The PNG was visually inspected: both empirical CDFs, the 0.42 threshold,
2/512 and 12/1024 bars, percentages and failed two-bit reference agree with
the CSVs. Its title explicitly excludes conformance and ACK-miss qualification.

The 48 new audit tests include negative mutations, source/output overwrite
guards, rejection of direct-Toolbox evidence mislabeled as canonical, and an
end-to-end review of the actual new canonical evidence. Together with the
existing HARQ-flag, CSV-semantics and Type-2-vector tests, the Python batch
passed **159 tests**. Thirteen warnings were Matplotlib/Pyparsing deprecations;
no test assertions or failure gates were suppressed.

## Validation and integration still in progress

The original consolidation guard process exited 1: all listed guards,
including `testE2E_FastVsTruth` and `testE2E_TruthPacketSemanticCampaign`,
passed except the known `testPUCCHPhase05` evidence quarantine. Its error
`sixgr:phy:pucch:UnverifiedPhaseEvidence` remains intact.

The original main-checkout `testAll` process remains live. A new `testAll`
and a new configuration/LLS/export/grant/E2E guard batch were launched on
receiver revision `7b1bea5d`; logs are `%TEMP%/sixgr_receiver_revision_full_20260913.log`
and `%TEMP%/sixgr_receiver_revision_guards_20260913.log`. They are not complete
at this checkpoint. No MATLAB source was changed beneath these processes.

The isolated receiver commit is protected by
`checkpoint/pucch-receiver-20260913`; main-checkout integration remains
pending the unchanged-source validation boundary. NR-validation and
result-integrity guided retaining actual-IQ authority, explicit component
scope, the failed reference and the unchanged qualification gates.
