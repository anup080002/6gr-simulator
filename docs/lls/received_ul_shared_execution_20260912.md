# Received-command two-port UL: shared-clock checkpoint

## Implemented and exercised

The baseline YAML already enables two logical SRS/PUSCH ports with rank one.
The UE now prepares a new PUSCH transport block from its accepted received
DCI assignment and payload. It does not take the scheduler's PHYGrant,
transmitter resource objects, TBS or coding layout as transmission inputs.
The shared runner requires that assignment to be available before preparation.
The gNB completion path derives reception from its own scheduled grant rather
than the UE transmitter's carrier, indices, TBS or coding layout.

`transmitReceivedPUSCH` verifies the decoded-command precoding authority,
independently derived new-TB size and actual native-codebook application.
The CSV records `ULTransmissionAuthority`, `ULReceiveAllocationAuthority`
and `ULReceivedAssignmentDigest`; the shared test checks their CSV roundtrip.
Power-control input uses received PRBs/TPC on this path, not a scheduler TPC
override. Absolute power control is disabled in the normalized-SNR fixture;
that test does not qualify absolute-power received-TPC operation.

Two broadcast/control defects surfaced while establishing a real received
DL clock with connected control installed:

1. Connected C-RNTI physical-scrambling checks were also imposed on explicitly
   supplied common-search-space control. Common and connected contexts are
   now separated in `PDCCH_Tx`.
2. The Type-0 builder left `SearchSpaceType` at the toolbox UE-specific default.
   It now explicitly constructs a common search space.

Common physical scrambling uses n_RNTI=0, distinct from CRC masking with
SI/RA/TC identities. See the [MathWorks SIB1 recovery reference](https://www.mathworks.com/help/5g/ug/nr-cell-search-and-mib-and-sib1-recovery.html)
and its TS 38.211 clause 7.3.2.3 anchor. The focused common-control test
checks three CRC identities, bit-exact decoding and rejection of a nonzero
common physical-scrambling RNTI; it is not full RA-procedure qualification.

## Terminal evidence

`lls_received_ul_type0_scope_20260912.txt` records a zero-exit test process:

- Common-control/connected-policy coexistence passed.
- Actual SS/PBCH reception established the DL reference at sample 3369.
- Actual shared CDL/SRS/DCI/PUSCH/UCI execution passed.
- PUSCH slot 10: two logical ports, rank one, requested/applied TPMI 3,
  CRC pass, exact decoded HARQ-ACK bits `1|0`, timing estimate 84 samples,
  receive result available at sample 76792.
- Actual precoder digest:
  `54609390e1bad2dade0c3abefdcce9a6722bdcdfcced46a0fc5a7549f62beb5f`.

The shared fixture is explicitly high-margin (inherited 60 dB), with isolated
DL ACK donors and QCL/TCI disabled because those donors have no preceding TRS.
It is not a 12 dB performance result, full RA run, dynamic-DAI test or full
main-scheduler qualification. Production QCL policy is unchanged. The
separate QCL timing-transfer regression passed.

The component regression group passed connected allocation, QCL timing
transfer, scheduler SRS propagation and actual PUSCH precoder evidence.
Measured-reference UL power control and received PDCCH clock alignment also
passed before the older stage test failed.

The final seven-test control regression process also exited zero:
`testTwoPortULYAMLAndSRS`, `testConnectedDCIMaterialization`,
`testConnectedPDCCHBlindMonitoring`, `testPDCCHPhysicalScrambling`,
`testPDCCHRNTIProcedureMatrix`, `testMIBPDCCHConfigSIB1Derivation` and
`testCommonPDCCHWithConnectedPolicy`. The first test independently selects
TPMI 3 from received two-port SRS on a known non-symmetric channel at 12 dB;
it does not substitute for the final shared-CDL baseline.

## Open gates; do not start the final baseline yet

1. UE-owned UL HARQ state and reserved-MCS/retransmission behavior. The new-TB
   received-command path explicitly rejects retransmission rather than
   substituting a newly sized block.
2. Production DL received-allocation/receiver-HARQ integration; the earlier
   independent DL component test is not strict shared-runner qualification.
3. Dynamic DAI, received HARQ-ACK ordering and UCI sizing.
4. Full shared main-scheduler qualification of the updated control/data path,
   then one final 58-slot 12 dB run and CSV/PNG/IQ/terminal audit.
5. `testDataChannelStreamStages('TDD',2)` still has an unconditional finite
   requested-power comparison at line 287. YAML disables absolute power, so
   both requested dBm values are legitimately unavailable. The intended test
   repair must check finite equal values when enabled, and explicit disabled
   status, unavailable dBm and unity scale when disabled. Repeated patch-tool
   writes to that file failed; the file and failing log remain unchanged.
   This is a recorded failed regression, not a pass or permission to weaken
   runtime power validation.

No `testAll`, E2E campaign or full 58-slot run was started in this checkpoint.
Validation claims are limited to the named focused tests. Original failed
preflights are retained alongside passing logs, not erased or relabeled.

## Reproduce the shared test

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); assert(testCommonPDCCHWithConnectedPolicy); assert(testSharedPUSCHChannelArtifacts('TDD',true,false,false,true,true));" -logfile received_ul_shared.log
```
