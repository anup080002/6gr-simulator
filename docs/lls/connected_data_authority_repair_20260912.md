# Connected data endpoint authority: 2026-09-12

Status: focused component repair, not full shared-scheduler qualification.
The final 58-slot configured-12-dB run remains held. Historical CSV/PNG/IQ
outputs are unchanged; these tests do not reconstruct missing runtime rows.

## Root causes and changes

1. The UE PUSCH transmitter required the gNB's measured-SRS decision directly,
   even when the UE had decoded a valid TPMI command. `resolvePUSCHPrecoding`
   now accepts the retained received-DCI capsule, verifies its digest and
   installed context, and enforces UL direction, TPMI, rank, RNTI, antenna
   ports, transform-precoding mode and the actual data slot. Non-codebook
   transmission cannot consume a codebook command. This route is labeled
   `AuthoritativeDCIDecisionUsed`; it does not claim an SRS measurement at the
   UE. The existing measured-SRS authority checks remain for the gNB's
   scheduler-side selection and paths without a received command.

2. `connectedDataAllocation` builds an independent resource configuration from
   the received allocation, NSCID, DM-RS ports/CDM groups, rank, MCS and UL
   TPMI. Configured reference reservations remain installed policy. The
   function derives coded capacity and nominal new-TB size from actual PHY
   allocation math. It does not obtain TBS, indices or coding layout from a
   transmitted object. Nominal TBS is explicitly not stored HARQ TB state.

3. The DL calibration receiver adapter always constructed a transmitter
   precoder, including strict checks for a selected matrix and hash. A
   practical receiver with an independently received assignment now uses
   DM-RS effective-channel estimation without this matrix. Its adapter
   validates received allocation/reference/coding fields and reports no
   applied transmitter matrix. The canonical resource-selective receiver
   can consume logical DM-RS references without a physical-port precoder
   bundle. Existing explicit matrix and oracle paths keep their contracts.
   The architecture count is installed configuration, not measured beam
   evidence; receiver processing PRG metadata is labeled separately.

The UL command interpretation follows
[TS 38.214 V18.8.0, clause 6.1.1.1](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf):
the UE obtains the codebook transmission choice from signaled SRI, TPMI and
rank. This repair is not a whole-specification conformance claim.

## Evidence and test boundaries

`testConnectedDataAllocation` sends actual polar-coded control and coded DL/UL
data, with independently constructed endpoints. The gNB fixture derives its
timing and allocation from its own scheduled values, not the UE's decoded
capsule. UL reception receives no TX object, TBS, indices or coding layout.
DL reception receives a newly derived new-TB coding plan, not the TX plan.
Transmitted bits are consulted only after decoding to score bit equality.
The fixture uses a known unit channel with 35 dB noise for endpoint wiring;
it is not the 12 dB CDL performance result. It retains nonzero logical DM-RS
port 1 and NSCID 1, and rejects altered received state.

The approved baseline already configures two SRS/PUSCH logical ports with
rank one. `testTwoPortULYAMLAndSRS` independently measures two-port SRS at
12 dB and selects TPMI 3 on its known non-symmetric channel. A commanded
TPMI test alone would not qualify that measurement/selection step.

Original failed preflight logs are retained, including the missing UE SRS
authority failure, two missing DL fixture precoder requirements, and the
actual DL receiver dependence on the TX matrix. The fixture matrix and its
hash were supplied only to the DL transmitter; no strict assertion was
disabled. The independent endpoint waveform test then passed for both
directions (UL TBS 1160 bits, DL TBS 1064 bits).

The five-test UL authority regression group passed: two-port YAML/SRS,
UL precoding DCI table, scheduler SRS propagation, transmitter precoder
evidence, and connected DCI materialization. The final five-test receiver
group also passed: `testConnectedDataAllocation`, `testPDSCHReceiverCDL`,
`testPDSCHReceiverMIMONoiseDomain`, `testPDSCHReceiverAWGN`, and
`testPDSCHReceiverWrongDMRSPort`. Both processes exited with code zero.
The changed received NSCID is rejected before data decoding. Original logs
are retained as text under `evidence_20260912/`, with prefixes
`lls_two_port_received_authority_regression_20260912` and
`lls_connected_receiver_guard_final_20260912`. The other connected-allocation
logs preserve earlier failures and the intermediate waveform pass.

Focused reproduction:

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); runFocusedTests({'testTwoPortULYAMLAndSRS','testULPrecodingDCIField','testSchedulerPUSCHSRSAuthorityPropagation','testPUSCHTransmitterPrecoderEvidence','testConnectedDCIMaterialization','testConnectedDataAllocation','testPDSCHReceiverCDL','testPDSCHReceiverMIMONoiseDomain','testPDSCHReceiverAWGN','testPDSCHReceiverWrongDMRSPort'});" -logfile connected_authority_tests.log
```

## Mandatory next integration work

1. Wire received UL allocation into actual UE preparation, while retaining
   the gNB receiver's independently authored grant. In the shared runner,
   `localCompleteSharedScheduledPDCCH` still queues the authored grant and
   `localPrepareSharedScheduledULData` still prepares through that grant.
2. Wire independent DL allocation into the production shared receiver, with
   UE receiver HARQ state and a proper received scheduling assignment.
   The focused DL fixture uses the explicit `phy_calibration` adapter; it
   does not qualify `scheduler_truth` or the typed production receiver path.
3. Implement/validate dynamic DAI and HARQ-ACK ordering, reserved-MCS
   retransmission reuse, and the received-assignment/shared timing interface.
4. Qualify the updated control/data layout on the shared clock, then run one
   final 58-slot baseline and audit runtime CSV, PNG, IQ hashes and receipts.

Additional math issue observed but not repaired here: the legacy PUSCH RX
overhead resolver floors xOverhead at 6 for transform precoding/pi/2-BPSK,
whereas the TX resolver accepts the configured value. The active connected
baseline is CP-OFDM, so this is a separate transform-precoding regression
item, not a reason to inject an overhead floor into the new allocator.

No `testAll`, E2E campaign or full 58-slot simulation was started. The
user-requested focused-test scope is preserved; suite-wide qualification is
not claimed. Single-carrier 400 MHz/7 GHz, higher QAM and the later impaired
long-run campaign remain subsequent work.
