# Received data-assignment audit

The baseline connected PDCCH receiver now owns candidate, format and size
selection. The following downstream execution issues remain verified in code:

- `localCompletePDCCHTrial` still combines CRC acceptance with expected-TX-bit
  equality for its pass decision.
- `CoupledTruthRuntime.applyPDCCHGrantTrialImpl` and
  `bindReceivedPDCCHGrantEvidence` require expected payload and authored-grant
  binding. These are useful qualification diagnostics, not independent
  receiver assignment authority.
- `runDLPDSCHThroughput` and `runULPUSCHThroughput` still pass TX-built data
  objects, indices and coding metadata into the shared-stream receive call.
- The shared completion copies received TCI configuration epoch from
  `c.Grant.DCI.ContextData.ConfigurationEpoch`, not the installed receiver
  context used to parse the accepted bits.
- `DecodedGrantMaterializer.materialize` does not yet preserve all received
  NSCID, DM-RS, TPMI/SRI, K1/PRI and TCI fields in its output assignment.

Repair order: preserve and validate the complete received semantic capsule;
publish its scalar field evidence; consume it through independent data
configuration/coding-plan construction; separate execution acceptance from
expected-bit scoring; validate shared-clock data and feedback behavior.
No new full 12 dB run is authorized by this audit alone.

## Repair in this checkpoint

`materializeConnectedDCI` reparses the accepted received bits against the
receiver-installed context and verifies the existing parsed capsule matches.
It preserves NSCID, DM-RS ports/CDM groups/front-load length, rank, UL TPMI and
SRI, DL K1/PRI and TCI codepoint, plus allocation, MCS and HARQ fields. Absolute
slot fields are zero-based; the feedback slot is the data slot plus decoded
K1, not the control slot plus the raw indicator. TCI codepoint is not labeled
as an activated state ID. The capsule does not invent TBS and explicitly does
not qualify execution.

The shared PDCCH completion now retains this capsule and publishes its scalar
CSV evidence. The baseline received TCI epoch comes from this context rather
than the authored grant. Single-entry TDRA exports index zero instead of
looking for a nonexistent on-air field. Failed/unaccepted reception does not
create an assignment; direction-inapplicable fields remain unavailable.
The existing allocation-subset hash now uses the same derived TDRA index;
this repair does not expand that subset into a complete assignment identity.
The receiver records the absolute slot used for decoding, and materialization
rejects a different slot. DM-RS port indices are explicitly labeled as
zero-based logical indices, not physical antenna identities.

The existing typed `DecodedGrantMaterializer` is unchanged in this checkpoint.
Attempts to patch that specific file failed; it is not read-only, and other
repository edits succeed. The connected receiver capsule is a separate
semantic/evidence input, not a claim that the older typed materializer or
data receiver now has independent execution authority.

Focused test scope: actual polar-coded PDCCH reception in a deterministic
unit-channel fixture, paired formats and single-entry TDRA/K1 cases, receiver
field/identity rejection, immunity to configured TX/scoring hints, and CSV
roundtrip. Full shared data-receiver and DAI/HARQ-ACK integration remain open.
The capsule currently requires a directly resolvable MCS profile. Reserved
MCS retransmission handling needs receiver HARQ state and is not qualified by
this materializer; a rejected semantic assignment must not later be relabeled
as a CRC failure. Raw DL DAI and UL first-DAI remain in its complete `Fields`
record, but a correctly ordered dynamic HARQ-ACK codebook is still required.

The initial focused group found a fixture error: DL antenna codepoint 3 was
incorrectly expected to mean logical port 1. The ordinary DL table requires
codepoint 4 for that choice; UL uses codepoint 3. The fixture was corrected,
retaining its nonzero-port assertion and leaving production tables unchanged.
The next group passed received materialization, two-port SRS/TPMI and scheduler
grant consistency. Both original receipts/logs are preserved under
`evidence_20260912/lls_connected_received_assignment*`.

The final five-test group passed after the clock-consistency guard:
`testConnectedDCIMaterialization`, `testPDCCHReceivedClockAlignment`,
`testPDCCHReceivedGrantClock`, `testSharedQCLTimingTransfer`, and
`testPDCCHGrantBindingEvidenceCompleteness`. Its receipt and original log are
`evidence_20260912/lls_connected_received_clock_final_20260912.*`.
No `testAll`, E2E campaign or full 58-slot rerun was started. Historical
CSV/PNG/IQ artifacts were not changed or reconstructed.

Field interpretation follows the existing ordinary connected profile in
[TS 38.212 V18.8.0, sections 7.3.1.1.2 and 7.3.1.2.2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138212/18.08.00_60/ts_138212v180800p.pdf).
This is not a whole-specification conformance claim.
