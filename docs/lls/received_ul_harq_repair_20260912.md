# Received-command UL HARQ checkpoint

## Root causes and changes

The received-command transmitter previously accepted only new transport
blocks. Retransmission inputs still came from the scheduler's replay cache.
The stateless DCI materializer also rejected modulation-only MCS entries
because they have no defined target code rate.

`ReceivedULHARQState` now owns a separate UE buffer per configured HARQ
process. It consumes accepted C-RNTI assignments, retains payload/NDI and
original coding history, and returns updated state only after successful
preparation. Repeated/noncausal assignments and replacement retransmission
payloads are rejected. An NDI toggle starts a new buffer generation.

`resolveConnectedMCS` distinguishes defined-rate MCS entries from the
modulation-only entries in the three supported CP-OFDM tables. The latter
retain their actual modulation but do not invent a target code rate or new
TBS. Allocation requires retained coding history; UE retransmission uses
the original TB, initial MCS and coding rate with received RV/resources.
An ordinary-MCS retransmission implying a different TB size is rejected.

These changes follow the connected C-RNTI buffer procedure in
[TS 38.321 clause 5.4.2](https://etsi.org/deliver/etsi_ts/138300_138399/138321/18.01.00_60/ts_138321v180100p.pdf)
and retained-TBS rules in
[TS 38.214 clause 6.1.4.2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf).
They are not qualification of configured grants, Msg3, transform-precoded
HARQ, cross-BWP reconfiguration or two-codeword UL.

The main shared queue now retains the UE entity separately from gNB state
and passes its snapshot into PUSCH preparation. UE state is updated after
successful queue insertion, not from the gNB decoder result. Received
completion removes UE state before constructing gNB receiver arguments.
The CSV adds `UEHARQAttempt` and `UEHARQInitialAssignmentDigest`.

## Evidence and remaining qualification

The reserved-MCS endpoint process exited zero. Actual PDCCH decoding drove
new-TB MCS 10/RV 0, retained-TB MCS 31/RV 2 with a larger PRB allocation,
then an NDI toggle back to a new MCS-10 block. The independently configured
gNB receiver decoded each 1160-bit TB. The retained LDPC combining signature
was unchanged on retransmission. This is a unit-channel/high-SNR endpoint
test, not shared-CDL retransmission or statistical combining-gain evidence.

`testConnectedDataAllocation` and `testConnectedDCIMaterialization` also
passed in that process. A final focused group adds modulation-only table
coverage and rejection of missing history and changed-TBS ordinary MCS.
The final four-test process exited zero: `testConnectedMCSHARQSemantics`,
`testReceivedULHARQState`, `testConnectedDCIMaterialization` and
`testConnectedDataAllocation` all passed, including the added rejections.

The shared SRS/DCI/PUSCH/UCI process also exited zero. Its actual new-TB
waveform retained the UE buffer, applied TPMI 3 on two ports/rank one, passed
CRC and recovered HARQ-ACK `1|0`. `UEHARQAttempt=1` and the initial received
assignment digest survived CSV write/read. It uses the existing high-margin
shared fixture and isolated DL ACK donors, not a 12 dB performance run or a
shared retransmission. The fixture's QCL/TCI exclusion remains unchanged.
The full main-scheduler callback is wired but not qualified by this fixture.

The earlier `lls_received_ul_harq_20260912` log is an exploratory PHY decode
check that allowed changed-TBS ordinary MCS. It is not normative HARQ
acceptance evidence. The retained-TBS rejection and reserved-MCS test replace
that insufficient check; the original log is preserved unchanged.

## Mandatory next gates

1. Shared-stream retransmission with UCI and independently retained gNB
   initial-MCS/coding state. The current throughput receive call still passes
   current trial MCS as `InitialIMCSPerCodeword`; a successful new-TB shared
   test cannot close that retransmission issue.
2. Strict production DL received-allocation and receiver HARQ integration.
3. Dynamic DAI and received HARQ-ACK ordering/sizing on PUCCH and PUSCH.
   Audit evidence: PF/RR still assign constant DAI; `HARQACKCodebookBuilder`
   validates DAI range but retains input event order. Its companion oracle
   sorts by cell/priority/modulo DAI/event index, which is not sufficient
   authority for monitoring-occasion ordering and modulo-wrap handling.
   Those bounded vector checks do not qualify the production Type-2 path.
4. The previously recorded disabled-absolute-power stage assertion remains
   unresolved; its test file was not changed in this checkpoint.
5. Full main-scheduler timing/state qualification, then one final 58-slot
   configured-12-dB run and complete CSV/PNG/IQ/terminal audit.

No full baseline, `testAll` or E2E campaign is authorized by this checkpoint's
focused validation. No old run output is reconstructed or promoted to a new
run. The wider 400 MHz/7 GHz, high-QAM and impairment goals remain unchanged.

## Focused reproduction

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); runFocusedTests({'testConnectedMCSHARQSemantics','testReceivedULHARQState','testConnectedDCIMaterialization','testConnectedDataAllocation'});" -logfile received_ul_harq.log
matlab -batch "setup6GRSimToolkit('Verbose',false); assert(testSharedPUSCHChannelArtifacts('TDD',true,false,false,true,true));" -logfile received_ul_harq_shared.log
```
