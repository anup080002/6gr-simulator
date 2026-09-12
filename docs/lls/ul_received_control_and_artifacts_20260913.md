# Received-control UL and artifact checkpoint

This checkpoint closes component failures; it does **not** qualify the final
58-slot configured-12-dB baseline. No full baseline, `testAll` or E2E campaign
was launched. The final-run hold remains. Earlier failed evidence is retained.

## What changed and actually passed

The DL-feedback donor decoded connected PDCCH but discarded its typed received
assignment. The connected receiver correctly rejected that missing authority.
`receivedDLFeedbackFixture` now materializes the capsule from received DCI and
installed configuration, checks its control/data clock and HARQ identity, and
forwards it through `ReceivedContext`. The connected PDCCH decoder receives
samples and sample rate, not transmitter DCI bits or a transmitter coding plan.
Known-bit comparison remains a scoring assertion after reception. The donor's
legacy PDSCH decoder is still not the main UE-owned DL HARQ integration.

Three MATLAB processes completed with exit 0:

| Focused check | Actual result | Retained log under `evidence_20260913` |
| --- | --- | --- |
| `testReceivedDLFeedbackAuthority` | Received ACK/NACK = 1/0 at slots 3/6, processes 0/1; typed control and sample-availability checks | `received_dl_feedback_authority_01.txt` |
| `testExecutedDataPrecoderEvidence(...,'UL')` | Actual shared SRS/DCI/PUSCH/UCI; one transmission, two coefficients, 2,701 angular samples | `applied_data_precoder_ul_04.txt` |
| `testSharedPUCCHFeedbackClock(false,'TDD'); testPostEqSINR` | PUCCH feedback clock/power export and existing SINR-estimator assertions | `received_control_pucch_regression_01.txt` |

The UL component fixture uses **60 dB**, not the baseline's 12 dB. Its slot-10
PUSCH decodes 2,152 payload bits, CRC passes, and carried ACK/NACK bits decode
as `1|0`. TPMI **3** is applied with the actual two-port rank-one weights
`[+0.70710678118654746; -0.70710678118654746]`. Their exact matrix SHA-256 is
`54609390e1bad2dade0c3abefdcce9a6722bdcdfcced46a0fc5a7549f62beb5f`.
The CSV and independent beam renderer agree on that identity. The beam PNG
is calculated local-array directivity before node RF, **not** measured OTA
gain or an explanation for adding dB to configured SNR.

The actual receiver exported 3,522 paired constellation symbols with
EVM **0.10689322340553%**. The chart materializer now prefers full canonical
sample CSVs to preview/alias tables, prevents duplicate source ingestion,
and accepts raw equalized symbols or explicitly labeled unfitted receiver
output. It no longer substitutes post-equalization values into a
pre-equalization chart. Every sample remains in the chart CSV; the PNG
uniformly displays up to 450 per direction, including first and last.

- [Actual UL beam PNG](evidence_20260913/applied_data_beam_ul_render_01/applied_data_beam.png)
- [Actual UL constellation PNG](evidence_20260913/ul_constellation_render_02/post_equalization_constellation.png)
- The adjacent `receipt.json` files bind input/output hashes and explicitly
  state `full_run_qualification: false`.

The first constellation rendering (`_01`) exposed a second truncation inside
the SVG renderer: it drew only 420 of the selected 450 symbols and limited
references to 64 rather than the advertised 256. Both limits are repaired
and asserted. `_02` is the corrected image; `_01` remains historical evidence
whose claimed display coverage was incorrect. Its full CSV was unaffected.

Both temporary capture trees were copied without changing their contents to
`shared_ul_capsule_handoff_01` (5 files) and `ul_constellation_handoff_01`
(23 files), and each copied file's SHA-256 was checked against its original.
Original temporary files were retained. Embedded original paths are capture
provenance, not claims of a new execution at the copied location.

## Other artifact repairs and focused regressions

Single-occasion PRACH peaks no longer imply elapsed-time evolution. SSB
indices retain their actual slot (or an honestly absent slot); a beam index
is not silently relabeled as an SSB index. Fractional SSB identities fail.
Sparse event cards remain explicitly sparse and are not multi-slot evidence.

The aggregate PRACH probability plot previously carried a missing/low-information
marker despite actual trial counts. It now shows the observed rate and its
Wilson 95% bounds as labeled statistics, not three SNR operating points.
Count consistency is checked; configured SNR is not invented as a measured axis.
Existing missing-evidence gates are unchanged. The PBCH single-axis regression
now verifies the existing exact projection's original slots, cells and values
instead of requiring an obsolete missing-surface marker.

`python -m pytest tests/test_lls_contract_materialization.py tests/test_lls_applied_beam.py tests/test_lls_sparse_signal_evidence.py tests/test_lls_full_constellation_source.py -q`
completed with **52 passed** (retained JUnit receipt:
`evidence_20260913/ul_artifacts_focused_01.xml`). The separate executable
`python tests/test_lls_contract_materialization.py` also completed with exit 0;
its main assertions are not included in pytest's 52-test count.
`python tests/test_lls_csv_semantics.py` completed with exit 0.
These are focused regressions, not a blanket artifact or PHY conformance verdict.

## Measurement caveat found, still open

The high-margin UL capture exports capped `PostEqSINR_dB=45` and raw equalizer
SINR **65.1572933359167 dB**, with explicit
`OK_dynamic_range_limited` status. DM-RS residual SINR is
**64.4253302503596 dB**; EVM-derived SINR is **59.4209965 dB**. These are
different estimator domains, not interchangeable measurements.

`computePostEqSINR` applies configured `maxTrustedReferenceSINR_dB`; its
existing regression explicitly checks that cap. The subsequent demapper
noise variance can therefore reflect the cap instead of measured RF noise.
The `LLRNoiseVarianceSource` label needs reconciliation with that actual
path. This engineering cap is not proof of a physical 45 dB ceiling or a
3GPP-prescribed limit. No cap or assertion was removed to make this test pass.

## Remaining mandatory order before a new 12 dB run

1. Repair the still-unmodified non-occasion CSI-RS reservation in
   `allocREsPDSCH` once the recorded write restriction is resolved. The
   independent 12-excess-RE regression remains failing; do not bypass it.
2. Complete the main UE-owned DL received-assignment/HARQ handoff, remove
   double-combining/TX-plan authority there, and qualify causal ACK/DTX,
   repeated ACK and dynamic DAI. The isolated donor is not that integration.
3. Qualify special-slot TDRA dispatch with legal feedback timing, all grant
   clock callers, Type-A QCL source age/identity and TA/DL-UL synchronization
   against independent timing perturbations. Type-D and all beam modes are
   not certified by a rank-one component beam image.
4. Reconcile every measurement domain, power normalization and SINR/LLR
   source label; audit all new runtime CSVs/PNGs and access-grid producers.
   Old snapshot alignment columns/contracts and sparse-card publication
   classification remain distinct from corrected live data.
5. Resolve repeated-rendering work, verify terminal publication/manifest
   counts and hashes, then run one final 58-slot baseline and audit its own
   outputs. Do not reconstruct missing runtime facts into the old failed run.

The final YAML remains
`simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml`.
It explicitly enables two SRS ports and two PUSCH ports (rank remains one),
connected control and the special-slot PDSCH TDRA `[1,2,8,0]`; its parent
selects 12 dB. Applied-pattern output is enabled in the parent. Configuration
presence is not end-to-end qualification. The old access trace explains
first data at slot 31 by configured RA/SRS/TDD opportunities, not 30 slots
of host processing or a universal required access delay; see the prior
[complete-count re-audit](continuous_iq_02_access_artifact_reaudit_20260913.md).

Single-carrier 400 MHz/7 GHz, eight layers/two codewords, extended QAM and
Keysight instrument playback remain downstream work. Earlier IQ file/hash/
sample-clock checks are not proof of successful instrument import/playback.
No all-scenarios or full 3GPP compliance claim is made.
