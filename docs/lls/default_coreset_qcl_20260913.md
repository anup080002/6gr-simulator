# Absent-TCI CORESET QCL and received-DL handoff checkpoint

The absent-TCI donor regression is repaired and the bounded two-port UL
regression passes again. This is **not** a successful final 58-slot 12 dB run.
No `testAll`, E2E campaign, full baseline or instrument playback was run.

## Root cause and implementation

The UE-owned received-DL factory previously required an explicit TCI field
and activated TCI mapping for every connected assignment. The UL feedback
fixture correctly declares the TCI field absent; its old legacy decoder had
hidden that unsupported case. The new main received-HARQ route exposed it.

The repair adds YAML/catalog-backed `control.coreset_qcl_association`, copied
through the existing whole-control configuration authority. The fixture
explicitly configures a Type-A association to SS/PBCH index 0 for CORESET 0,
RRC serving cell 0, carrier 0, BWP 0 and epoch 1. This is labeled
`lls_preconfigured_higher_layer_context`, not a simulated MAC activation or
measured reference observation.

The PDCCH configuration binds the association to its actual control clock.
Receiver output retains that association; materializing received DCI checks
it against installed configuration before including it in the hashed capsule.
The PDSCH factory, immutable assignment validation and integration binding
then preserve it. Cell/carrier/BWP/CORESET/epoch, activation time and source
identity must agree. Missing or altered received evidence fails.

There is no invented TCI state ID or codepoint. Those quantities are absent
for this case and remain non-applicable. CSV QCL/TCI status identifies the
default CORESET association rather than incorrectly saying no association is
configured. It does not manufacture timing offsets, spatial gain, accuracy
or a measured source slot. The practical receiver still estimates its channel
and timing from received references.

TS 38.214 V18.8.0 clause 5.1.5 specifies the scheduling-CORESET QCL assumption
for an absent TCI field under the applicable timing conditions. This patch
supports the non-spatial association; Type-D is rejected until actual
receive-spatial-filter reuse and capability-dependent short-offset/monitored-
CORESET history are integrated. It is not claimed as complete default-beam
management. [Specification, pages 50–51](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf).

Explicit-TCI Type-A timing-transfer behavior remains separate. A configured
association is not permission to claim a measured Type-A transfer or Type-D
beam gain. The final 12 dB YAML continues to use its existing explicit-TCI
mapping; no baseline RF, SNR or geometry policy changed.

## Focused execution results

1. `default_coreset_qcl_handoff_01.txt`: **exit 1**. The first implementation
   assumed that the config-only PDCCH factory already had a runtime clock.
   The failure exposed that `buildInternalConfig` also invokes this factory.
   Configuration validation now checks policy/identity without inventing a
   slot; actual reception separately requires clock-qualified evidence.
2. `default_coreset_qcl_handoff_02.txt`: **exit 0**. Actual blind PDCCH and ten
   negative guards pass. The real donor PDSCHs pass/fail CRC as expected at
   slots 3/6, returning ACK/NACK 1/0 through the UE-owned receiver, with
   received-assignment identities and retained entities checked.
3. `default_coreset_qcl_ul_regression_01.txt`: **exit 0** on the final source
   version. It reruns the ten default-QCL guards, actual two-port shared
   SRS/DCI/PUSCH/UCI, PUCCH clock/power export and the explicit-TCI timing
   authority test. That last test is an explicitly labeled boundary fixture,
   not a claim of a newly measured full-run TRS transfer.

Logs and captures are under `docs/lls/evidence_20260913/`. New failure logs
are retained; none was overwritten or changed to a pass.

The actual UL fixture remains **60 dB**, not 12 dB. It applies TPMI 3 with two
physical coefficients, one layer and 2,701 angular samples. PUSCH/UCI decode
passes; EVM is 0.10689322340553% over all 3,522 captured symbols. The earlier
45 dB reported SINR cap and its raw-domain distinctions remain open as
documented in the prior measurement checkpoint.

Two original temporary capture trees were copied without alteration and all
hashes verified: `default_coreset_qcl_shared_ul_capture_01` (5 files) and
`default_coreset_qcl_constellation_capture_01` (23 files). Originals remain.
Embedded original paths retain execution provenance, not a new execution.

- [New UL beam PNG](evidence_20260913/default_coreset_qcl_ul_beam_01/applied_data_beam.png)
- [New UL constellation PNG](evidence_20260913/default_coreset_qcl_ul_constellation_01/post_equalization_constellation.png)

The adjacent receipts bind all input and output hashes. Both rendered PNGs
and their numerical input CSVs are byte-identical to the earlier verified
UL reference captures. The beam plot is local-array pre-RF directivity, not
OTA gain. The constellation CSV retains all 3,522 samples; the PNG displays
the uniformly selected 450. Neither receipt claims full-run qualification.

## Still mandatory before restarting 12 dB

The CSI-RS allocator patch was retried through `apply_patch` after the MATLAB
regression terminated. The editor again returned `Failed to write file` for
`+sixgr/+phy/+grid/allocREsPDSCH.m`. Read-only inspection shows `Archive`,
`IsReadOnly=False`, last modification 2026-09-09 04:45:33. The underlying
write refusal is unresolved. No ACL change, alternate writer or workaround
was used; the allocator remains unchanged and its capacity guard remains
failing. Windows' writable attribute alone does not prove editor access.

Next work remains: restore that allocator's normal editor access; apply its
shared absolute CSI-RS calendar; generate new separately named captures for
the changed rate-matching map; qualify the main coordinator's retained DL
state with actual feedback; finish repeated-ACK and failed-DCI/DTX dispositions,
dynamic DAI, special-slot scheduling and independent TA/synchronization tests.
Then reconcile all measurement domains and complete terminal publication
before one final 58-slot baseline. No historical CSV is relabeled corrected.

The wider goal remains unchanged: full measurement/artifact integrity,
single-carrier 400 MHz at 7 GHz, higher-rank/two-codeword and extended-QAM
support, and validated Keysight export/playback. Those are not qualified by
this Type-A association repair or by changing YAML alone.
