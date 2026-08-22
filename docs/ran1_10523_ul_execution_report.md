# RAN1 10.5.2.3 uplink implementation and bounded execution report

## Scope

The implementation is a thin study package under `+sixgr/+tdoc/+ul10523`. It does not add or duplicate a PHY. Executed uplink evidence follows:

`runRAN1UL10523TDocStudy -> sixgr.tdoc.ul10523.runULTDocStudySuiteInternal -> sixgr.lls.runLLS -> sixgr.lls.runSNRPoint -> sixgr.lls.runTransportBlock -> existing PUSCH Tx/Rx, OFDM, channel, equalization, soft LLR, LDPC decode and CRC`.

The supplied scenario catalog, proposal traceability table and figure/result contract are vendored under `simulator/configs/tdoc_ul_10523`. Their original supplied-file SHA-256 values were:

- scenario catalog: `f0f9ab384aec584d9d4d11a9a1086525abd1cde7ffbcc165679d38ac767fbafd`
- proposal traceability: `3c6a1bb3524280cd96c91bb436a2ce1d2fe2d7cec2d1d9e63dda90ae7856b666`
- figure/result contract: `5d5c37e56f8d32af47749d2b8888f894d53156bfd67398578224c4312dbb8773`

The controlling DOCX named by the catalog was not supplied. Exact DOCX visual/caption equivalence therefore remains unverified and no publication-complete claim is made.

## Focused validation

- Existing production PUSCH/PUCCH/SRS baseline: 15 actual PUSCH transport blocks plus dedicated UL suites passed before implementation.
- `testUL10523Config`: 27 campaigns, 30 proposals, 22 TFIG rows and 64 RFIG rows passed catalog validation.
- `testUL10523Deterministic`: six exact analytical invariants and 22 nonempty figure-source datasets passed.
- `testUL10523QuickArtifacts`: one actual PUSCH transport block at +20 dB, 48 CSVs and 25 PNGs passed the semantic/hash/image gate.
- `git diff --check`: passed.

No repository-wide `testAll` was run; the user explicitly requested dedicated tests only.

## Bounded TDoc run

Run folder: `results/tdoc_ul_10523/tdoc_bounded_20260814_01`

The intentionally small campaign used one actual transport block at each of -10, 0 and +20 dB. Its result is diagnostic, not publication statistics.

| SNR (dB) | Measured SNR (dB) | TB errors / TBs | BLER | Decoder noise variance |
|---:|---:|---:|---:|---:|
| -10 | -9.95045 | 1 / 1 | 1 | 10 |
| 0 | -0.001943 | 0 / 1 | 0 | 1.003128 |
| 20 | 19.93640 | 0 / 1 | 0 | 0.0103547 |

All rows reported decoded-transport-block CRC and `nrPUSCHDecode` soft-LLR lineage. The truth contract reported no BLER lookup, synthetic BLER, random pass/fail model, or geometry-as-LLS use. The observed waterfall direction and decoder-noise scaling are internally consistent. With only one trial per point, the zero-error Wilson upper bound is 0.7935; these values must not be used as calibrated BLER estimates.

## Artifact audit

- CSV: 52 files, 611 aggregate rows, zero unreadable/empty rectangular artifacts.
- PNG: 25 files, zero decode/dimension failures; minimum observed dimensions 1326 x 772.
- Vector artifacts: zero SVG and zero PDF, honoring the raster-only output instruction.
- TDoc figures: all 22 conceptual/analytical/quick-sanity figures are backed by persisted CSV sources and SHA-256 hashes.
- Result figures: all 64 RFIG rows are explicitly `BLOCKED`; no placeholder result image was generated.
- Artifact manifest: 79 files were byte-hash bound and independently rechecked.
- Campaign state: C01 passed; C00 is incomplete; C02-C26 remain blocked unless their required calibrated LLS or genuine multi-cell SLS evidence is executed.
- Proposal state: 30/30 remain blocked because the required terminal campaign evidence is not available.
- Artifact-integrity gate: pass.
- Publication gate: fail closed, as required.

The bounded run proves implementation wiring, source-driven figure production and artifact integrity. It does not prove the complete C00-C26 performance matrix, independent 3GPP FRC calibration, genuine system-level campaigns, trained-AI evidence, or publication-level confidence.
