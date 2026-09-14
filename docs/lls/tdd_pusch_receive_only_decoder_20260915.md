# TDD receive-only PUSCH adapter checkpoint

Scope: physical capture -> current-observation independent receiver. This is
not normal-coordinator missing-DCI, nonempty HARQ, combined feedback, detector
qualification or integrated 12 dB acceptance. FDD-focused work remains deferred.

## Implemented

- `CoupledWaveformStream` privately retains completed receive-only observations
  and exposes them by ID. Unknown and not-yet-completed IDs are rejected; callers
  cannot supply a fabricated capture or replacement receiver configuration.
- `receiveSharedPUSCHWithoutTransmission` retrieves the owner-held gNB grant and
  actual pre/post-RF buffers. Digital gain compensation uses recorded applied
  AGC only, retaining ADC/clipping effects. Independent scheduling and installed
  CSI configuration determine the UCI context.
- The receiver uses frozen gNB coding/TBS/RV/original-MCS authority and actual
  capture coverage for bounded DM-RS correlation. No prepared transmitter, UE
  payload, generated TB bits, perfect channel, injection-variance substitution,
  UE timing advance or fabricated prior soft buffer enters `PUSCH_Rx`.
- Actual current-observation demapping/LDPC output and normalized UCI evidence
  are returned without applying HARQ state, recording a TX, or creating primary
  BER/goodput/EVM-against-transmitted-TB rows. Retransmission combining/commit is
  explicitly outside this adapter's current-observation scope, not reported as
  completed merely because a CRC was computed.

## Executed checks

R2026a Update 4. Both runs used the explicitly logged working-tree candidate
based on `e6cc1576` (`AllowDirty`), not a clean frozen-source qualification.

| Log directory under the integration checkout's `logs/` | Outcome |
| --- | --- |
| `testall_20260914T183638273Z_f3c2f033` | Decoder adapter PASS 118.30 s; capture-only PASS 56.06 s; MATLAB/launcher 0 |
| `testall_20260914T184134639Z_99776e71` | Stronger decoder adapter PASS 117.43 s; capture-only PASS 60.23 s; MATLAB/launcher 0 |

The stronger test supplies deliberately contradictory UE bookkeeping (99
declared ACK bits and a pending ACK) while preserving the actual gNB schedule.
The receiver still derives zero HARQ bits from that schedule, invokes demapping
and LDPC, and leaves the physical clock/TX/HARQ counters untouched. It also
rejects unknown and incomplete owner-held observations.

This is one no-transmission component episode with a retained scheduled UL
grant, not newly received/rejected UL DCI. The YAML-owned timing guard provides
a real capture with search offsets 0:154. Correlation selected offset 119; no
oracle timing or padding was used. The receiver actually returned CRCError=1,
DecodeAttempted=1 and ULSCHDecodeAttempted=1. Failure was not inserted as an
expected DTX result or forced by the test. The initial and stronger runs are
paired infrastructure checks, not two independent qualification episodes.

Preliminary saved scalar evidence read independently from HDF5: disturbance
source `runtime_channel_estimate`, status `OK`, value 0.06299187448916338.
The HDF5 channel-estimate dimensions are [2,14,300] (reversed MATLAB storage
order), not a single scalar copied across a fading grid. These observations
do not establish all-measurement or detector qualification.

Final raw local artifact:
`logs/tpf1629ad4_4c34_4246_a050_1a4f5259ccf2/receive_only_decode.mat`;
9,995,238 bytes, native SHA-256
`3021c4c25cad8271a22776156e36becbf3a2a0d9b6bd92d84f04a97347890084`.
Raw captures, decoded results and both ZIP log bundles remain local and intact.

## Still required before shared-feedback closure

1. Connect scheduled gNB observation ownership and this adapter to actual UL
   control rejection in `runWaveformLinkBundle`; receiver crashes must not be
   treated as measured missing DCI. Preserve received-control/sample provenance.
2. Resolve receiver-result availability, nonempty scheduled HARQ/CSI handling,
   PUCCH/PUSCH ownership and exactly-once common feedback commit without fake
   transmitted producer fields. Retain proper receiver-owned HARQ combining.
3. Execute normal-path missed/all-missed DCI, DAI wraps, combined HARQ/CSI/SR,
   duplicate/stale/late cases and signal-present regression controls.
4. Run the clean frozen revision's focused tests, full `testAll` and all required
   NR/config/export/E2E guards. Existing suites are on older source and cannot
   qualify this change. Detector qualification, integrated measurement/export
   checks and 12 dB acceptance remain open; main is not promoted.
