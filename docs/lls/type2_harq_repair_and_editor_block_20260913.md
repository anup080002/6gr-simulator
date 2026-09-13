# Type-2 HARQ-ACK procedure repair — integration blocked

This checkpoint is **unqualified**, not permission to run the final 58-slot
12 dB scenario. It follows `baseline_readiness_recheck_20260913.md`.
The complete LLS, measurement/artifact closure, single-carrier 400 MHz / 7 GHz,
high-order modulation, Keysight, long impairment-enabled LLS and later NTN/ISAC
objectives are unchanged.

## Reproduced defect and applied component repair

The old Type-2 builder only checked DAI range and preserved input order. In the
eight-event vectors HARQ-012 and HARQ-016, input and expected output grouped
equal modulo DAI values across different chronological events. The independent
oracle also sorted by DAI rather than monitoring chronology. A range check or
agreement with these expectations was not evidence of correct wrap handling.

The scalar-TB, two-bit-DAI procedure now orders received events by the declared
chronological EventIndex. An explicit MonitoringOccasionIndex additionally
supports serving-cell ordering within one occasion. It unwraps observed counter
DAI, uses a received total DAI when supplied for the final monitoring occasion,
and generates the protocol NACK positions indicated by those counters.

`Events` contains only supplied received events. `SourceEventIndex=0` and
`MissingAssignmentMask=true` identify inferred NACK bit positions; their PDSCH
identity is empty, not fabricated. They are not marked receiver DTX. Received
DTX events retain their separate mask. Digests now bind event evidence and the
bit-to-event mapping. Numeric/state checks reject malformed evidence before
hashing, and mixed priorities, conflicting feedback identities, stale epochs,
inconsistent total DAI and explicitly unsupported bit-width/codeword variants
are rejected.

The algorithm does not use a gNB scheduling ledger to reconstruct UE knowledge.
It cannot identify an entirely missed modulo-counter cycle or an unindicated
trailing assignment. It does not claim to implement multi-TB/spatial bundling,
CBG, SPS append, multicast grouping, one-bit counter DAI or retransmitted
codebooks. Those extensions and main-runtime producer/consumer wiring remain
part of the overall unfinished goal. Type-1/Type-3 semantics were not repaired
or newly qualified by this work.

Reference: [TS 38.213 v18.8.0, section 9.1.3.1](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf),
particularly monitoring/cell ordering, DAI wrap and unassigned NACK positions
on specification pages 102–105. No new waveform scenario parameter was hidden
in the implementation; constants here describe this two-bit protocol contract.

## Independent expectations and verification

The two corrected chronological expected sequences are:

- HARQ-012: `10D10D10`, P12_0 through P12_7.
- HARQ-016: `0D10D10D`, P16_0 through P16_7.

Type-2 fixture priorities now belong to one priority class per codebook;
mixed-priority rejection is independently tested. State outcomes, event
identities, DAI values and the input permutations were not changed to force
an implementation match. `.gitattributes` pins these two vector files as bytes
so their new SHA256 values survive checkout line-ending settings.

Receipts under `evidence_20260913/`:

- `type2_harq_layout_01.txt`: FAIL. A complex DAI reached JSON hashing before
  domain validation. The event constructor was repaired; the test was retained.
- `type2_harq_layout_02.txt`: exit 0. Literal leading/interior/trailing gaps,
  repeated/wrapped DAI, total DAI, cell/occasion order, empty inputs, digest
  identity, 256 four-event DAI combinations, negative guards, UCI serializer,
  and all 24 retained scalar-event vectors passed.
- `type2_harq_focused_03.txt`: exit 1. The final layout regression and existing
  resource-planning-without-power regression pass. The new actual-YAML typed
  codebook planning test fails at `PUCCHConfigBuilder.localPlan`: raw-bit-only
  conversion rejects the codebook. The required repair could not be saved.
- `type2_harq_vectors_01.xml` and `_02.xml`: 10 Python tests pass in each;
  the second follows byte-preserving LF normalization of the two vectors.
  Independent modulo-distance
  arithmetic checks the eight Type-2 vectors, reversal invariance, a literal
  gap/wrap case and mixed-priority rejection.

`type2_vector_integrity_01.json` preserves the existing vector-pack verifier's
nonzero exit and exactly two failures: stale
SHA256 values for the changed HARQ input/expected CSVs. Its integrity checks
were not weakened. Updating `independent_vector_manifest.json` was rejected by
the editor. `pending_type2_vector_manifest.patch` retains the exact new hashes
and the revised bounded-oracle provenance; it is **unapplied**.

Reproduction:

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); testType2HARQACKLayout; testPUCCHResourcePlanningWithoutPower; testType2HARQRuntimePlan"
python -m pytest tests/test_type2_harq_vectors.py -q
python tests/vectors/pucch/verify_pucch_vector_pack.py
```

No `testAll`, E2E campaign or full 58-slot simulation was run, following the
user's focused-test restriction. These tests do not establish full-suite PASS.

## Why integration is blocked

The patch tool repeatedly rejects writes to mandatory existing source files,
despite successful edits to other files. This turn additionally reproduced
failures for `PUCCHConfigBuilder.m`, `runPUCCHPhaseValidation.m`, the vector
manifest and its verifier. The older CSI planner / PUCCH receiver source-edit
failure remains unresolved. Git/security/permissions have not been proved to
be the cause. No alternate writer, permission change, source deletion or file
replacement was used.

`pending_type2_harq_consumers.patch` retains **unapplied, untested** changes for
typed resource-planner handoff and phase export's bit-to-event mapping. The
phase exporter still assumes one observed event per codebook bit: it must not
be used to publish new DAI-gap cases until repaired and tested. The existing
24 vectors have no inferred gaps, but do not qualify that missing export path.

The pending consumer patch is necessary, not sufficient: scheduler fixed-DAI
production, received-DCI event grouping and identity, PUSCH/PUCCH codebook
handoffs, receive-only expectations, timing and the broader codebook features
still require implementation/qualification. The final baseline remains held.

The same edit failure has persisted across the CSI, constellation/readiness
and current HARQ checkpoints. Further isolated helpers would not close these
mandatory integration gates. The work requires an external editing/tool-state
change; saved patches can be applied in the IDE, followed by the failing tests.

The NR-validation and result-integrity skills guided keeping the hard guards,
received-event authority and failed receipts; the config-driven skill guided
preserving the actual scenario and explicit capability boundaries.
