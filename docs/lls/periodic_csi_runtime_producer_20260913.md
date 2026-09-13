# Periodic CSI runtime producer checkpoint — 2026-09-13

Development validation checkpoint, not a full-suite PASS, integrated 12 dB
qualification, or universal 3GPP conformance declaration. Base: `032ad7e6`.
This advances the calendar work left open in
[the publication-clock checkpoint](csi_report_publication_clock_20260913.md);
that historical document and its failed evidence remain unchanged.

## Implemented and exercised

- Normal slot entry now builds configured periodic CSI report obligations
  independently of PDSCH execution. It selects retained, receiver-available
  CSI-RS rows bound to the UE and serving cell, no later than the reference
  resource. Missing usable CSI produces no invented report payload.
- The report period/offset, rather than AMC delay or arbitrary next-UL-slot
  shifting, controls transmission. The baseline YAML offset changes from 1 to
  3 together with this producer integration: resource 10's symbols 12–13 fit
  the configured TDD special slots 4, 9, 14, ... (one-based).
- The same-cell/equal-numerology reference helper applies the single/multiple
  resource minimum delay and installed measurement-gap exclusion. Report 9
  references special slot 4; report 14 references special slot 9. A report
  without a reference resource in the current sweep is not fabricated.
- A newer eligible measurement can refresh an unexecuted report without
  changing its configuration/occasion identity or duplicating a grant.
  Receiver completion and transport delivery timestamps remain separate.
- Configured obligations export to `control/csv/configured_csi_report_obligations.csv`,
  separately labelled `configured_report_obligation_not_RF_execution`.
  They are not primary RF trial rows or evidence of received CSI.

The standards basis is TS 38.214 V18.8.0 clauses 5.2.1.4 and 5.2.2.5:
[ETSI publication](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf).
Reference-resource timing and eligible received measurements are distinct
from the UL reporting calendar and from an AMC feedback-delay parameter.

## Preserved evidence

`docs/lls/evidence_20260913/periodic_csi_runtime_producer/` contains:

- `fixture_red`: 3/5 passed, two failed. The new test initially expected
  reference slot 3, overlooking slot 4's ten configured DL symbols. An existing
  shared fixture also manually assigned a slot without initializing its sweep
  horizon. The tests were corrected to use the configured partition and normal
  slot entry; production timing guards and performance limits were not relaxed.
- `focused_seven_pass`: 7/7 passed, MATLAB and launcher exit 0. This was an
  explicitly dirty-checkout diagnostic batch, not a clean-revision testAll.
- `producer_data`: normal report generation for slots 9 and 14 with retained
  source slots 3 and 8, despite competing AMC delay 90. Declared CSI inputs,
  no PDSCH, and no CSI-RS RF measurement execution.
- `shared_transport_data`: normal producer followed by actual shared PUCCH
  waveform/CDL/RF/thermal-noise execution in slot 9, delivered in slot 10;
  decoded CQI 10, RI 1, PMI 0, reference slot 4. Captured sample planes and
  configuration are retained in MAT. CSI/access/pathloss-selector inputs are
  declared fixtures: this is PUCCH transport evidence, not measured CSI-RS
  accuracy, access qualification or a connected 12 dB run.
- `calendar_data`: historical offset-1 unavailable obligations versus the
  production offset-3 calendar, with no shifting to rescue invalid occasions.
- `publication_clock_data`: declared CSI input/publication/report CSV round
  trip preserving the actual owner's sample 7680 completion timestamp.
- `source_manifest.json`: current checkpoint file identities captured after
  the focused run. These are not a pre-run source snapshot; the launcher
  records before/after HEAD and status, not content hashes. Clean-revision
  mandatory validation is still required.
- `evidence_manifest.json`: preserved input/output file hashes and original
  locations. Red results stay red; no historical evidence is overwritten.

## Remaining work and limits

1. Independently schedule gNB receive-only CSI obligations when the UE has no
   eligible measurement; complete combined HARQ/SR/CSI and independent PUSCH
   Type-2 mapping/commit. Configured obligation rows alone do not close this.
2. Qualify actual CSI-RS generation/measurement and all downstream consumers
   on the integrated run, independently of PDSCH opportunities.
3. Complete per-UE activation/reconfiguration/DRX and gap-state eligibility;
   qualify cross-numerology, carrier aggregation/NTN offsets and unresolved
   flexible-symbol cases. The current reference helper rejects mismatched
   numerology and does not implement those broader procedures.
4. Remove the remaining legacy source-delay behaviour in direct component
   enqueue callers where appropriate; it is not used by the new normal
   periodic producer. Other reporting triggers are not qualified here.
5. Avoid rebuilding the whole horizon and scanning all obligations at every
   callback before a long-duration study; preserve semantics when optimizing.
6. Finish mandatory testAll and NR/config/strict/export/E2E/scenario guards
   against the committed new source, then address integrated 12 dB gates.
   The retained 12/1024 false-ACK failure, signal-present missed ACK, CFO/EVM
   applicability/performance checks and all-measurement acceptance remain open.

No radio power, noise, gain, detector threshold, acceptance limit or truth/proxy
label was relaxed. The NR-validation, result-integrity and config-driven skills
guided calendar authority, fixture labelling and failed-evidence preservation.
Main and the older checkpoint remain frozen while their existing suites run;
their results cannot qualify this newer producer revision.
