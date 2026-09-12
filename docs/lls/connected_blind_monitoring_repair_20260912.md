# Receiver-owned connected PDCCH monitoring

Scope: the continuous-IQ baseline's configured paired DCI 0_1/1_1 receiver.
This checkpoint removes TX payload-size and mapping-object authority from
that reception path. It does not qualify the full scheduler, UCI codebook,
all receiver assignment fields or a new 58-slot run.

## Root causes and implementation

`completePDCCHReception` previously supplied the TX carrier/PDCCH object,
TX identity and `numel(tx.DCIBits)` to the receiver. The independent legacy
receiver builder also did not materialize the transmitter's complete CORESET
mapping. Both legacy builders relied on Toolbox defaults for search-space
type rather than applying that configured property explicitly. The Toolbox
default is UE-specific, so this observation alone is not evidence that the
old baseline actually used a common search space.

The connected baseline now declares `control.connected_monitoring` in YAML:
CCE/REG mapping, REG bundle/interleaver/shift, precoder granularity,
monitoring start/period/offset/duration and scrambling identity. The validated
`ConnectedPDCCHConfiguration` factory builds TX and RX objects independently
from that installed configuration. The existing configured bitmap, candidate
counts, DCI identities and BWP remain authoritative. This factory currently
requires contiguous six-RB groups; unsupported bitmaps fail explicitly.

With connected configuration and no explicit calibration K, `PDCCH_Rx`
builds both monitored contexts before decoding. It tries each configured
payload length against each monitored candidate, reusing that candidate's
received REs, channel estimate and LLRs. CRC-valid bits must also parse in
the installed context, including the received format identifier. Different
formats with the same length are tested, not selected using a TX format hint.
Unrelated implementation exceptions must not be turned into failed radio
observations. Ambiguous accepted payloads remain rejected by the scalar API.

Expected TX bits are retained for post-reception scoring only: changing their
length or contents does not change the selected RX payload/candidate/format.
The main trial parser now takes the receiver's actual `DecodedDCI`, instead
of reparsing it with an expected TX context. The legacy explicit-K codec
entry point remains a separately identifiable calibration/compatibility path.

Candidate evidence distinguishes raw `CRCOK`, contextual parse acceptance,
parse rejection identifier, payload length, format and context digest.
Raw CRC-valid hypotheses and context-valid hypotheses are separate.
Physical candidates attempted and payload/format hypotheses attempted are
also separate counts; the main `BlindDecodeCount` uses the latter.
Physical cell identity and PDCCH scrambling identity have separate metadata.

References: [MathWorks search-space configuration](https://www.mathworks.com/help/5g/ref/nrsearchspaceconfig.html),
[all-candidate resource generation](https://www.mathworks.com/help/5g/ref/nrpdcchspace.html),
[DCI decoder](https://www.mathworks.com/help/5g/ref/nrdcidecode.html).
These APIs implement the referenced TS 38.213 monitoring and TS 38.212
coding procedures; API use alone is not a conformance verdict.

## Focused evidence

`testConnectedPDCCHBlindMonitoring` uses actual coded PDCCH waveforms and
independently configured reception. It checks:

- both 37/43-bit baseline formats and a paired 39/39-bit configuration;
- a non-default interleaved CORESET and scrambling ID distinct from cell ID;
- actual decoded UL TPMI 3 in the explicit codec fixture;
- unchanged selected reception after erasing TX carrier/PDCCH/identity
  metadata and corrupting legacy size/format hints and expected TX bits;
- wrong-RNTI rejection and CRC-valid but context-invalid payload rejection;
- failure on attempted TX-object injection into connected blind monitoring.

These are deterministic unit-channel control fixtures, not a 12 dB BLER
curve or new main-scheduler result. Existing received-clock and shared physical
queue regressions have distinct scope; they do not by themselves prove the
new paired layout has traversed the complete access-to-data scenario.

Receipts and original logs are under `evidence_20260912/lls_connected_blind_*`.
The first five-test group passed. The following group found a stale source
inspection in `testPDCCHSharedSlotResourceAllocation`: its function-boundary
lookup required the old two-output qualifier signature, while the actual
qualifier now also returns queued grants. Its TDD/FDD composite-waveform and
exact allocation checks had already passed. The boundary locator was repaired
and given an explicit uniqueness/order assertion. The reservation and
no-assumed-control assertions were retained unchanged. The failed receipt
remains preserved alongside the final rerun; it is not removed or relabeled.

The final five-test group passed: connected blind monitoring, exact shared
slot allocation, preparation/reception, shared physical queue and two-port
UL YAML/SRS selection. The last test measures a two-port pilot fixture at
12 dB and selects TPMI 3 rather than bootstrap TPMI 0. It does not assert
that the new full baseline will select that same TPMI.

A final edge-case repair also makes the explicitly sized calibration
receiver honor the configured scrambling ID when it differs from cell ID.
Parser exception handling recognizes only the named received-field rejection
classes; unrelated configuration/programming failures propagate.
All three final edge-case tests passed in
`evidence_20260912/lls_connected_blind_scrambling_20260912.json`:
connected blind monitoring (including explicit-K scrambling compatibility),
connected DCI profile, and PDCCH preparation/reception.

No full 12 dB run, `testAll`, E2E campaign or historical result reconstruction
was performed for this checkpoint.

## Remaining execution gates

1. Carry actual decoded reference selections, K1, NSCID and TCI through
   receiver assignment and CSV evidence, with complete received-field
   semantics. In particular, expected TX-bit comparisons remain scoring
   diagnostics, not legitimate authority for executing a received grant.
   Audit downstream `CausalGrantDecodeOk`/expected-grant binding usage as
   part of this work; changing the decoder alone does not close that gate.
2. Repair and test dynamic DAI/HARQ-ACK counter/codepoint semantics,
   bundling/missed-DCI handling and consistency across PUCCH and PUSCH.
3. Exercise the new paired layout in the actual shared-clock access/control/
   data path with two-port SRS/PUSCH. Preserve causal received synchronization,
   per-resource fading estimates and single-owner waveform/RF execution.
4. Run one fresh 58-slot 12 dB baseline only after these gates close, then
   audit original CSV/PNG/IQ/hash/terminal evidence and the new UL/SS/CSI/data
   measurements. No measured SINR is forced to equal another channel's value.

The broader 400 MHz/7 GHz, higher-modulation, hardware-playback and long-run
impairment requirements remain in the overall ledger; this repair does not
replace or redefine them.
