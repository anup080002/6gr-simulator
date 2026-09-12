# Received-control DL assignment endpoint

## Implemented and verified

`PDSCHAssignmentFactory.fromReceivedConnectedDCI` now creates the immutable
connected DL receiver assignment from the actual accepted DCI capsule and
installed configuration. It retains received RNTI, allocation, absolute slots,
MCS, NDI, RV, HARQ process, DM-RS indication/NSCID, and the raw DAI codepoint.
Serving-cell indices remain distinct from physical cell identity. UE identity
is an explicit caller input, not a hardcoded default.

The received TCI codepoint is resolved through the configured active mapping:
codepoint 0 selects state 17 in this scenario. Epoch, activation time and
codepoint mismatches are rejected. This is the YAML-declared preconfigured
higher-layer Type-A association, not a simulated activation MAC CE, measured
QCL timing transfer, Type-D beam operation, or a transmitter precoder identity.
The distinction and SLIV derivation follow the relevant procedures in
[TS 38.214 clauses 5.1.2.1 and 5.1.5](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf).

`PDSCHCalibrationFacadeAdapter.materializeReceivedNewTB` reuses the existing
reference/resource planning implementation but constructs the connected
assignment directly. No calibration assignment is promoted into connected
truth. This endpoint derives its new-TB coding plan from received MCS and
exact allocation; it accepts no transmitter object, coding plan, expected
payload or precoder matrix. Practical noise estimation supplies the receiver,
not the injected simulation noise variance. Exact G, new-TB size and carrier
slot are checked against the independent allocation.

The same audit fixed two MCS ownership gaps:

- Received allocation now updates per-codeword compatibility aliases, so
  stale bootstrap indices cannot override received MCS.
- Capsule validation rejects a changed installed directional MCS table,
  even if the control layout itself has not changed.

TX, legacy RX and the new endpoint now share one unchanged DM-RS EPRE helper.
The extraction first checked that the former TX/RX implementations were
identical. This avoids introducing a third scaling formula or losing the
existing exact sqrt(2) convention for the configured -3 dB token.
No scenario parameter, noise target, impairment or two-port UL setting changed.

## Evidence and failures retained

The actual coded-control/data test passed with independently constructed gNB
transmission and UE reception. Received DL MCS 10, DM-RS logical port 1 and
NSCID 1 produced an exact 1064-bit decode. A second receive invocation used
the strict compatibility entry and a 43-sample delayed capture: measured
offset 43, CRC pass, exact payload, no oracle timing. Tests also checked TCI
mapping/activation rejection, raw DAI preservation, stale MCS-alias immunity
and installed-table mismatch rejection. UL independent allocation still
decoded its 1160-bit block.

The first focused regression process failed `testPDSCHDMRSEPREDifference`
before power scaling: its PDSCH-only 12-RB fixture inherited an enabled SSB,
which cannot fit. The fixture now explicitly disables SSB; all power-ratio,
symbol, mapping, CRC and invalid-input assertions remain unchanged. This
does not disable SSB in the baseline. Six other regressions in that failed
process passed, but its overall exit remains recorded as failure.

The final process exited zero: the updated endpoint test plus eight focused
regressions passed (DM-RS EPRE, compatibility delegation, scheduling
assignment, receiver without TX precoder, capture timing, CDL receiver,
TX/RX authority separation and received UL HARQ state). The last test retained
1160 bits across received MCS10/RV0, modulation-only MCS31/RV2 and an NDI reset.

[The terminal receipt](evidence_20260913/dl_received_assignment_terminal_receipt.json)
records all three process exits and exact log hashes. These are component
tests, not a 12 dB baseline, a main-scheduler run or statistical performance
evidence. No missing full-run CSV/PNG/IQ rows were reconstructed or fabricated.
No `testAll` or E2E campaign was run, per the focused-test-only task instruction;
the repository's generic full-suite requirement is therefore not claimed met.

## Mandatory next work

1. Add UE-owned DL HARQ admission and soft state, including retained initial
   coding metadata for retransmissions. The new-TB materializer is not a HARQ
   entity. Modulation-only DL retransmissions still fail explicitly rather
   than inventing a target code rate or retaining a transmitter plan.
2. Integrate that receiver state and the new endpoint into the main shared
   scheduler, with actual received-control availability and capture timing.
   This checkpoint does not replace the first-pass TX-derived inputs there.
3. Complete dynamic DAI/monitoring-occasion Type-2 HARQ-ACK behavior. The raw
   two-bit DAI here is not an unwrapped monitoring counter or codebook proof.
4. Repair the older disabled-power assertion in `testDataChannelStreamStages`.
   A mode-aware patch was attempted again and rejected by the file-edit tool;
   that file is unchanged. No alternative write or ACL bypass was attempted.
5. Run one final 58-slot configured-12-dB baseline only after those gates,
   then audit final CSV/PNG/IQ hashes and terminal receipts.

Single-carrier 400 MHz/7 GHz, higher modulation, 30 dB, instrument playback
and the later long impaired runs remain in the overall goal, downstream of
these correctness gates. No completion or full 3GPP conformance claim is made.
