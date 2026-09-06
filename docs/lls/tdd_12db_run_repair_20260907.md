# Short TDD run: measured failures and remaining integration work

## Frozen execution evidence

Run `tdd_12db_verify_20260907_0018` executed revision `9fd99e55` using
`simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd.yaml`.
MATLAB session 75994 exited **1**. The scheduled horizon was 25 slots;
execution failed at slot 16. No FDD or 25 dB diagnostic scenario was launched.
The subsequent export-regression batch did exercise its existing FDD E2E
fixtures; those are not evidence for this TDD access/timing repair.

- Slot 3: TRS requested sample 15360 (2 ms), but the eagerly executed SSB
  observation had advanced the shared TDD channel to sample 38400 (5 ms).
- Slot 13: TRS consumed its multi-slot window through sample 138240 (18 ms).
- Slot 15 prepared Msg1 for the correct current PRACH epoch, 14 ms.
- Slot 16: consuming Msg1 requested sample 107520 (14 ms), behind the
  channel's 18 ms clock. `sixgr:channel:RuntimeChannelTimeReversal` stopped
  execution. Moving the RA epoch fixed the old 4 ms target, not this overlap.
- The failure checkpoint contains `DLTrialRows=0` and `ULTrialRows=0`.
- Failure recovery also reported `sixgr:artifact:TerminalBrowserClosureFailed`
  after three passes (`materialization=0 visual=1 lineage=1`).

Log: `logs/tdd_12db_verify_20260907_0018.log`.
Run root: `results/lls/qualification_working/lls/lls_causal_access_to_data_wiring_tdd/tdd_12db_verify_20260907_0018`.
Historical artifacts were not repaired or relabeled in place.

## Output review

The separate exhaustive audit (session 69468, exit 1) used `--preview-rows 5
--strict-value-closure`. Its output is in
`results/lls/qualification_working/audits/tdd_12db_verify_20260907_0018`.
It inspected 435 CSVs, 196225 rows, 12690 columns and 68 PNGs. Parsing/raster
decoding passed; 71 required CSV semantic checks failed across 33 files.
These are failed checks, not 71 proven independent PHY bugs. Empty tables,
NaNs and diagnostic words such as "proxy" are not individually proof of
fabricated primary measurements. The primary-data absence remains a failure.

All four saved SSB candidates decoded. SSB index 0 was selected from measured
SS-RSRP (-84.7077648905873 dBm); its SS-SINR is 42.2787558330549 dB.
Recomputing RSRP from each branch's saved desired watts, SINR from its saved
desired/disturbance watts, and pathloss from TX EPRE minus RSRP reproduces all
four reported values within 3e-13 dB. This is arithmetic closure, not proof
that the incomplete combined waveform/channel/scheduler execution is valid.

Manual PNG inspection found defects not caught by the automated chart gate:

1. `channel_impulse_response.csv` explicitly records
   `ResponseType=model_average_power_delay_profile` and a source ending in
   `model_profile_metadata_not_in_path_realization`. The renderer nonetheless
   titles it "Channel Impulse Response" with a "RUNTIME MEASUREMENT" badge,
   and concatenates the repeated DL/UL tap sets on a categorical delay axis.
   Model PDP and an actually observed complex CIR must remain separate.
2. `contract__error-reliability-analytics__fer-vs-snr.csv` labels 35.776611
   as `ConfiguredSNR_dB`, sourced from four PBCH rows. The run's configured
   label was 12. The chart also lacks a visible marker for its single point.
   The selected measurement field/domain and frame-error denominator need
   to be audited; a named chart contract does not establish physical meaning.

## Bounded evidence repair

The PBCH adapter previously left generic availability flags false despite
copying valid measured receiver SINR values. The generic string filler then
replaced empty NA reasons with invented "field_not_emitted" explanations.
`bindPBCHReceiverSINREvidence` now retains receiver values/status/reasons and
the actual post-equalizer availability flag. Missing values are not filled
and an explicitly rejected observation is not promoted by a finite number.
NA reason fillers preserve the producer's empty reason instead of guessing.
The failure-log format was also corrected from a two-element string array
to one format string, so the checkpoint coordinates can be printed.

The focused session 36464 exited 0: `testPBCHSINRRuntimeBinding`,
`testRuntimeIdentityFillerIsolation`, and `testPBCHSINRDomainContract` passed.
The new binding test uses actual SSB/PBCH decoding with reference AWGN at
12 dB, plus unavailable/contradictory receiver cases. This does not repair
the physical scheduler overlap. Export regression session 29847 also exited
0: `testLLSSINRFieldTruth`, `testLinkExportPipeline`, `testArtifactIntegrity`,
`testOrganizeRunResults_E2EArtifactPreservation`, `testSchedulerGrantConsistency`,
`testE2E_FastVsTruth`, and `testE2E_TruthPacketSemanticCampaign` passed. Results
are in `logs/pbch_evidence_export_regressions_20260907.log`. The full `testAll`
suite was not run, following the user's bounded-test instruction.

## Ordered work still required (not implemented by the evidence repair)

1. **P0: main scheduler sample ownership.** Replace eager multi-slot physical
   execution with prepared TX contributions, one chronological node/carrier
   sample stream, and complete received-window dispatch. Register SSB/TRS,
   RA stages, control and data before consuming their common intervals.
   Prepare gNB PDCCH/PDSCH from the same grant without making transmission
   depend on an already completed UE DCI decoder. Apply PA/TX RF to each
   transmitter's composed antenna samples, not independently to contributors.
   Preserve TDD reciprocity and FDD independent carrier states. Do not reset,
   rewind, clamp clocks, clone future tails or disable conflicting resources.
2. **P0: RA reception integration.** The existing prepared-stage continuation
   API does not yet connect its waveform to the common sample owner. Its
   bare `RuntimeStageWaveforms` input also lacks the typed sample-clock,
   receiver-noise and transport evidence of SSB/TRS/PDCCH received buffers.
   Complete each stage from the actual stream, then expose decoded RAR,
   timing advance, contention identity and RRC state at the correct deadline.
3. **P0: reference-SNR authority.** The current YAML resolves physical thermal
   noise and geometry; its 12 dB is noncontrolling metadata. A genuine 12 dB
   reference-SNR run needs a declared RE/branch reference and frozen
   independent calibration, not per-faded-waveform measured-power AWGN.
   Keep link-budget operation separate; never force instantaneous SINR to 12.
4. **P1: actual data/feedback closure.** Execute and inspect PDSCH/PUSCH CRC,
   adaptive MCS/rank/precoder, CSI/SRS age, PUCCH overlap and HARQ delivery on
   the repaired timeline. Zero trials cannot establish correctness.
5. **P1: output semantics and coverage.** Repair the model-PDP/CIR and
   configured-SNR/estimated-SINR chart distinctions; close remaining audited
   identity, required-schema, reciprocity, stage-evidence and publication
   failures using actual outputs. Repeat all first-five-row/value reviews.
6. **After correct LLS: instrument export.** User targets M9384B/M9383B and
   89600 VSA/89601201C. Preserve actual continuous complex IQ per physical
   transmitter branch with sample clock, RF center, units/scaling, absolute
   origin, TDD activity and hashes. Existing grant IQ snippets are not the
   all-channel stream. Verify file round trips and model-specific playback;
   do not claim instrument validation without executing it.

The three supplied Downloads prompts are supporting engineering requirements,
not authority to silently replace this 5 MHz/CDL-A single-UE experiment with
their differing 100 MHz/CDL-C/two-UE RF examples or upgrade pinned NR editions.
Keep waveform receiver estimates separate from standardized SS/CSI quantities
([TS 38.215 V18.2.0, clauses 5.1.1/2/5/6](https://www.etsi.org/deliver/etsi_ts/138200_138299/138215/18.02.00_60/ts_138215v180200p.pdf)).
Reference-SNR normalization must document RE/antenna and FFT conventions
([MathWorks SNR definition](https://www.mathworks.com/help/5g/ug/snr-definition-used-in-link-simulations.html)).
No full-simulator, all-impairment, instrument, or 6G conformance claim is made.
