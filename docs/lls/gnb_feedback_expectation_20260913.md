# gNB feedback expectation and PUCCH disposition checkpoint

Follow-up to [special-slot scheduling](special_slot_scheduler_trs_20260913.md).
The full 58-slot baseline remains held; these changes do not close missed-DCI
reception, dynamic codebook handling or terminal publication qualification.

## Causal finding

`localCompleteSharedScheduledPDCCH` arms the shared PUCCH observation only
when DL control was accepted by the UE. `localCompleteSharedDataPlan` then
stops on failed control with `SharedDataDTXDispositionRequired`. A transmitted
DL assignment can therefore exist without an independent gNB feedback
expectation. Using its scheduled grant to decode PDSCH at the UE, inventing a
NACK, or cancelling an already transmitted TB would all hide the actual defect.

`commitSharedDataTransmission` now records a separate
`SharedDLHARQExpectations` entry after the physical owner proves the actual
TX start and the existing queue/HARQ commit succeeds. Its validation is done
before shared HARQ handles mutate. The entry retains transmission identity,
HARQ process/NDI/RV, canonical control/data/feedback timing and the scheduled
packed DCI/PRI. It is not conditioned on UE control success. It supplies no
ACK, NACK, received CRC, decoded bits, assumed codebook length or UE transmit
authority. Duplicate commits and identity/timing mismatches fail.

This is the gNB expectation producer needed by the missing receive-only
feedback path, not that completed receiver path. Expectations presently remain
in runtime state; the component test retains them as explicitly labeled
diagnostic CSV/MAT evidence. They are not promoted to received-UCI trials.

The additional investigation confirmed why the codebook cannot be guessed
from completed PDSCH rows: the baseline declares dynamic HARQ-ACK, while
the existing runtime report builder accepts already assembled payload bits.
The generic codebook class does not reconstruct missing DAI positions and
wraparound. Scheduler paths also contain fixed `DAI=1` assignments. The
connected DCI path and monitoring-occasion counter need joint qualification.
The applicable procedures are [TS 38.213 v18.8.0, 9.1.3 and 9.2.3](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).
The expectation deliberately retains scheduled DCI rather than inventing an
unwrapped DAI, feedback-vector length or per-bit outcome.

## False transfer disposition repaired

`prepareSharedPUCCHFeedbackRuntime` previously treated an empty set of
standalone feedback rows as proof that feedback had moved to PUSCH. That
does not distinguish actual reservations from missing producer state.

The path now requires matching physical-occasion keys, explicit multiplexing,
nonempty PUSCH grant context IDs, unique feedback IDs and uncensored rows.
The owner retains the reservation proof through capture completion. It is
labeled **reservation**, not proof of PUSCH transmission or successful UCI.
Missing evidence fails instead of silently assigning the transfer reason.
The receive-only no-UE-transmission case still needs its own implementation;
it is not routed through this transfer disposition.

## Test history and scope

- `_01`: exit 1. The TDD shared physical queue ran, but a new test incorrectly
  expected receiver-only fields inside the immutable TX contract. That contract
  correctly omits them; the test now checks their absence and invariance to
  added receiver/scoring fields. This was a test failure, not UCI reception.
- `_02`: exit 1. TDD expectation checks passed and its MAT was retained.
  FDD reached an existing negative test which expected a fixed-Es/N0 error
  despite the FDD YAML explicitly selecting thermal noise. Doubling variance
  correctly raised `SharedThermalNoiseClosure`. The test now requires the
  exact error for the actual declared mode; unknown modes still fail. No
  noise model, variance, threshold or production closure assertion changed.
- `_03`: **exit 0**. Two actual DL TX commits in each TDD/FDD fixture produce
  four expectations, independent of receiver/scoring fields. Identity,
  premature-commit and timing-mutation negatives pass. Transfer-ledger
  positives/negatives pass. The existing two-port shared SRS / received UL
  DCI / PUSCH / HARQ-ACK UCI regression also passes, with channel/constellation
  artifact checks. This does not exercise a missed-DCI receive-only consumer
  or an actual PUCCH-to-PUSCH capture-transfer completion; those scopes remain open.
- `gnb_feedback_semantics_tests_01.xml`: **exit 0**, 122 existing retained-ACK,
  CSV semantic and exhaustive-auditor regression tests pass. These do not
  independently verify all new PHY equations.

The UL regression's temporary CSV/channel files and separate constellation
capture are copied without modification into `gnb_feedback_ul_regression_03`
and `gnb_feedback_ul_constellation_03` under the evidence root. Original/copy
SHA256 and paths are retained in the checkpoint receipt. Nothing is relabeled
as the production 12 dB run.

Inspection of this high-margin UL component CSV found `PostEqSINR_dB=45`
with `PostEqSINRValueStatus=OK_dynamic_range_limited` and retained
`PostEqSINRRawEqualizer_dB=65.1572933359167`. The receiver helper applies its
configured maximum-trusted reporting bound; 45 dB is not the uncapped
estimate. EVM is 0.106893223406 percent. The copied EVM-per-symbol PNG was
visually inspected and identifies itself as partial checkpoint evidence.
Raw/bounded SINR labeling and AMC use remain part of measurement closure;
no cap, noise value or estimator equation was changed in this checkpoint.

The physical queue fixtures isolate TX ownership, radio clock, CDL/RF/noise
and queue/HARQ commitment. TDD uses the existing 60 dB component fixture;
FDD uses the existing thermal-noise fixture. Neither is a rerun or qualification
of the requested 12 dB access scenario. Ledger-only transfer tests are not
physical PUSCH transfer qualification.

## Next required work

1. Derive the gNB expected-UCI reception context from scheduled/installed
   policy without requiring a UE transmit-power assignment or payload report.
   The current typed PUCCH receiver requires `PUCCHTransmissionAssignment`;
   that TX/RX contract coupling must be addressed honestly.
2. Register and complete actual shared-clock receiver-only observations;
   permit real noise false detections and retain their outcomes. Never set
   DTX solely because the simulator knows the UE missed DCI.
3. Complete scheduled/received Type-2 DAI and codebook ordering jointly,
   including missed control, bundling and same-occasion multiple assignments.
4. Integrate those outcomes with HARQ, then remove the missed-DCI stop only
   after end-to-end shared control/data/feedback component tests pass.
5. Retain all other baseline gates: Format-0 SR and detector ROC, the blocked
   CSI non-occasion repair, TA perturbations, measurement/beam/AMC closure,
   artifact production and terminal baseline audit. No full run or push yet.

Focused reproduction, choosing new evidence names:

```powershell
matlab -batch "diary('docs/lls/evidence_20260913/feedback_expectation_NEW.txt'); setup6GRSimToolkit('Verbose',false); testSharedDLHARQExpectation('docs/lls/evidence_20260913/feedback_expectation_NEW'); testPUCCHObservationTransferEvidence; testSharedPUSCHChannelArtifacts('TDD',false,false,false,true,true,false); diary off"
```
