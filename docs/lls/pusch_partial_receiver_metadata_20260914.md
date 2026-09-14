# Preserve independent UCI and measured front-end evidence after CSI failure

Implemented against `8c9b9853`; **MATLAB runtime validation is pending**.
This is not completion of normal shared PUSCH integration or a 12 dB pass.

## Concrete gap

The partial PUSCH branch retained decoded HARQ bits and nested receiver evidence,
but returned before the normal output annotations. It omitted top-level
`HARQACKDecodeStatus`, `HARQACKBitCount`, `UCIOnPUSCHApplied` and CSI bit-count
metadata. The throughput adapter reads those top-level fields, and the shared
HARQ consumer requires a decoded status plus the actual UCI usability evidence.
The missing metadata could therefore discard an otherwise usable HARQ decode.

The branch also omitted already measured channel-estimate/equalizer availability,
post-equalization SINR, noise-domain labels and equalized samples. A failure to
resolve CSI-dependent data positions does not undo the completed receiver front end.

## Repair

`sixgr.phy.ul.pusch.annotateUCIReceiverEvidence` now supplies the same output
metadata contract in partial, complete single-codeword and complete two-codeword
reception. It copies actual decoder status and bits, validates bits before integer
conversion, and preserves unavailable CSI Part-2 length as NaN. Independent input
cannot inherit TX-reference scoring. Explicit legacy scoring remains separate.
The adapter does not decode, infer an ACK or create a transport-block CRC.

Partial reception retains the actual pre-CSI-failure front-end observations and
their original sources/statuses/domains. The unchanged receiver-evidence validator
is also evaluated. The complete PUSCH `StrictReceiverEvidenceOk` and `StrictOk`
flags remain false while any codeword mapping is unresolved. Per-field UCI
usability remains independent, and the failure reason is unresolved mapping, not
an invented failed TB CRC. No power, noise, detector threshold or physical
acceptance limit was changed.

## Evidence and scope

- Five MATLAB files passed native static checks with a malformed negative control;
  all diagnostics and exact source snapshots are preserved locally in
  `logs/pending_integration_evidence_20260913/pusch_partial_metadata_20260914_02/`.
- Revision 01 preserves the prior snapshot before adding the explicit complete-
  evidence rejection on partial reception; it was not runtime-tested either.
- `testPUSCHUCIAnnotation` covers declared metadata, unusable status preservation,
  malformed bits, missing status, stale scoring rejection and explicit legacy
  scoring. Those are metadata tests, not physical decoding evidence.
- `testPUSCHReceivedCSIWaveform` retains its existing waveform/CRC assertions and
  adds checks for usable HARQ metadata after invalid received CSI, actual front-end
  fields, absent TB CRC and rejection of complete-PUSCH qualification.

These MATLAB tests have not run on this revision. The other two original MATLAB
workers remain untouched. Required validation includes the new test, the actual
CSI waveform case, high-rank PUSCH regressions, `testAll`, NR/config/strict,
export/artifact/scheduler and E2E guards. Local resource checks remain distinct
from test execution and cannot establish a pass.

Normal shared callers still need independent gNB context/occasion binding and
the common scheduled-feedback commit path. Detector statistics, all-measurement
CSV/PNG closure, integrated 12 dB, the same-chain sweep and the later classified
impairment-enabled 6G study remain open.
