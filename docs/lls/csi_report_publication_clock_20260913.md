# CSI report publication-clock repair — 2026-09-13

Development checkpoint, not integrated 12 dB qualification or calendar closure.
Base: `dbf21bfd79ccd7779df41bd4aff7a5d5ed0bd003`.

## Production change

`completeSlotImpl` publishes a received CSI-RS row through `applyCSIRSTrialImpl`
before queuing its CSI report. The queue previously published that measurement
again with `AvailableSlot = report.DueSlot`, although its retained sample clock
still identified the earlier receiver completion. Thus a transport delay became
a conflicting measurement-availability timestamp.

The queue now consumes the already-published receiver row without republishing
it. It checks all six producer flags, actual availability, sample rate/epoch,
the retained input row and its UE-owned publication. It records
`MeasurementAvailableSlot`, `MeasurementAvailableAtSample`,
`MeasurementClockEpoch` and `MeasurementClockDomain` separately from `DueSlot`.
Unavailable, altered/unpublished, wrong-epoch and wrong-UE publication inputs
are rejected. The measurement's source slot is retained, and an already-past
transport occasion is rejected rather than reported as an executed transfer.

The source-authority fixture now publishes its declared CSI rows, including the
second changed-CQI occasion, before queuing them. No production guard or test
assertion was weakened to admit the former incomplete fixtures.

## Evidence

`docs/lls/evidence_20260913/csi_report_publication_clock/` contains:

- `red_duplicate_publication`: original regression failed because report
  queuing duplicated/retimed the published measurement.
- `intermediate_fixture_failure`: 4/5 passed; the source-authority test's second
  changed-CQI fixture had not published its new row and was correctly rejected.
- `focused_seven_pass`: final-source focused batch, 7/7 passed, MATLAB exit 0.
- `clock_data`: exact declared CSI input, published measurement and queued
  report, including CSV round-trip verification. The real shared owner advanced
  to sample 7680; publication remained one row at slot 2/sample 7680 while the
  queued report was due in slot 4. No CSI-RS RF execution is claimed here.
- `calendar_data`: configured nominal report obligations and independent
  receiver contexts. These are configuration evidence, not received UCI.
- `source_manifest.json`: execution-source hashes for this checkpoint.

The seven checks cover the new publication/queue boundary, existing source
authority/PUSCH reducer, physical-clock consumer, calendar helper, occasion
predicate, actual shared PUCCH CSI transport, and frozen future-UL planning.
The existing shared transport fixture decoded seven CSI bits, due slot 4,
delivered slot 5; its input CSI is declared, not measured by CSI-RS RF.

## Not closed by this repair

The periodic-calendar helper is now retained alongside the repair but is still
not the normal report producer. Production still filters on PDSCH source slots
and selects a later UL slot from a measurement-delay calculation. The configured
58-slot baseline has twelve nominal CSI occasions with unavailable UL symbols;
a declared offset-3 alternative has eleven available occasions. Production YAML
was not changed independently of the producer wiring.

The next integration must reserve configured receive occasions independently
of UE payload, select only eligible causal receiver measurements, encode at the
proper event, and handle missing measurement/absent transmission without invented
CSI. Report timing and the CSI reference resource are distinct requirements in
[TS 38.214 V18.8.0, clauses 5.2.1.4 and 5.2.2.5](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf).
The reference-resource cutoff must not be replaced by the AMC feedback delay.

Normal combined HARQ/SR/CSI and independent PUSCH Type-2 handling, false/missed
ACK qualification, DMRS knowledge publication, full measurement closure and
integrated 12 dB acceptance remain open. No radio power, noise, gain, detector
threshold, acceptance limit or truth/proxy label was changed.

Main remains frozen for its running `testAll`. The mandatory new-source full
suite and NR/config/export/E2E/scenario guards must run on this checkpoint;
the seven focused passes cannot substitute for those tests or the 12 dB run.
The NR-validation, result-integrity and config-driven skills guided preservation
of failed evidence and the separation of measured state from configured timing.
