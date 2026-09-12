# Configuration-owned connected DCI layout repair

This is a bounded control-layout checkpoint for the continuous-IQ 12 dB
baseline. It is not complete control/UCI conformance, a new 58-slot result,
or publication qualification.

## Root causes and repairs

The baseline previously constructed its connected DCI context through legacy
defaults. Those defaults retained optional fields that this scenario had not
configured, and its TDRA was partly constructed from the current grant.
The scheduler also encoded the numerical K1 offset where the configured
feedback-list index was required. UL DM-RS sequence initialization and the
UL-SCH indication were absent from the layout.

`ConnectedDCIProfile` now constructs an explicit paired 0_1/1_1 context from
the resolved runtime configuration, without calling `DCIContext.fromLegacy`.
Its optional-feature policy, release/version, epoch, search-space/CORESET
identities and single-cell identity are declared in `control.connected_dci`.
Unsupported extensions fail explicitly. Runtime contradictions involving
CBG, hopping, interleaving, bundling and UL ports/rank are checked separately.

The baseline declares these TDRA rows in YAML, using the repository's
`[index, start symbol, length, slot offset]` representation:

- PDSCH: `[0,2,12,0]` and `[1,2,8,0]` for full-DL and special-slot DL.
- PUSCH: `[0,0,13,1]` and `[1,0,13,2]`; symbol 13 remains available for SRS.

The two-entry tables require one TDRA bit. K1 is encoded as an index into
`pucch_resources.dl_data_to_ul_ack`, and parsing returns the resolved slot
offset separately. Single-entry TDRA/feedback lists have zero-bit indications
in the codec, with explicit derived values rather than invented received bits.

For this exact 25-RB, rank-one UL policy, independent expected layouts give
37 bits for DCI 0_1 and 43 for DCI 1_1. Both monitored contexts resolve the
same size set. Ordinary HARQ process numbering retains four bits, despite
the baseline configuring eight processes. Unconfigured VRB-interleaving,
dynamic-bundling, rate-match-group, ZP-CSI-RS-trigger and CBG fields are absent;
DCI 1_1 does not include the legacy CSI-request field. SRS request remains
two bits, restricted here to no aperiodic trigger. Rank-one UL has no
PTRS-DMRS association indication. Higher-rank UL is rejected by this profile
until that association is integrated; the underlying two-port precoding
table helper's rank-two support alone is not sufficient.

`pdsch.dmrs_nscid` is now catalog-registered, mapped into the runtime config,
and consumed by the shared PDSCH configuration factory. Previously that
factory did not consume the selector. Tests verify that selector one changes
the generated DM-RS sequence and agrees with actual received PDCCH bits and
the coded PDSCH transmitter. The baseline explicitly declares selector zero
for both PDSCH and PUSCH.

Layout reference: [TS 38.212 V18.8.0, sections 7.3.1.1.2 and 7.3.1.2.2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138212/18.08.00_60/ts_138212v180800p.pdf).

## Focused verification

The twelve-test receipt is
`evidence_20260912/lls_connected_dci_profile_retry_20260912.json`.
It covers independent field names/order/widths/bits, zero-bit indications,
K1 indexing, negative policy/port/rank checks, actual DL NSCID signaling,
UL reference signaling, two-port measured SRS/TPMI, config/catalog validation,
scheduler grant consistency, pack/parse, size alignment, QCL scenario wiring
and received-clock alignment. All twelve passed.

The final runtime-contradiction checks are recorded separately in
`lls_connected_dci_runtime_guards_20260912.json`. The additional receipt
`lls_connected_dci_authority_final_20260912.json`
checks explicit required YAML NSCID/TDRA keys, scenario validation and
two-port SRS/TPMI after the final guard changes. Original failed preflight
logs and the initial test-fixture failure are retained, not overwritten.
The first new test accessed a `ScenarioConfig` property directly; it was
corrected to use its documented `toStruct` conversion. No assertion was
weakened. No full simulation, `testAll`, E2E campaign, historical CSV/PNG
reconstruction or SINR equalization was performed.

## Remaining mandatory control work

1. **Receiver-owned monitoring:** `completePDCCHReception` still supplies
   `numel(tx.DCIBits)` as K. Integrate the installed paired contexts into
   blind format/size search. Expected TX bits may score an already-selected
   reception, but must not determine its size, format or candidate.
2. **Received grant materialization:** carry decoded NSCID, DM-RS ports/CDM,
   TPMI, K1 and TCI through the actual receiver assignment and exported
   evidence. Existing authored-bit checks and allocation/HARQ subset hashes
   do not prove every received field controls the receiver. Validate zero-bit
   TDRA consumers, not just this codec, before claiming that configuration
   is supported throughout the main runtime.
3. **DAI/HARQ-ACK semantics:** `SchedulerPF` currently assigns `DAI=1` and
   the runtime reports source-slot/HARQ-process ordering. Correct field width
   does not establish a standards-correct dynamic counter/total-DAI codebook.
   Audit and implement the counter-to-codepoint mapping, bundling, missed-DCI
   handling and PUCCH/PUSCH consistency before the final run. Do not replace
   the constant with another constant or call this closed by a CRC pass.
4. Run focused shared-clock tests using this new complete layout. The earlier
   two-port shared-clock fixture predates `control.connected_dci`; its passed
   SRS/TPMI/UCI evidence does not qualify the new monitored payload layout.
5. Only after these gates close, run one fresh 58-slot 12 dB baseline and
   audit its original measurements, CSV/PNG, IQ hashes and terminal receipts.

Two-port SRS/PUSCH remains enabled at rank one. A TPMI-selected spatial vector
is not two spatial layers. Its new full-run UL SINR and its difference from
DL/SS/CSI SINR have not yet been measured. The future 400 MHz/7 GHz experiment,
higher modulation, hardware playback and long impairment runs remain behind
the existing qualification gates.
