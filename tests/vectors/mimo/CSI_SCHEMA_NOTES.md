# CSI schema vector scope

The two-port wideband PUCCH expectations in
`mimo_csi_report_schema_test_vectors.csv` were corrected on 2026-09-08:

- TS 38.212 V18.8.0, Table 6.3.1.1.2-7 specifies one sequence in the order
  CRI, RI, LI if requested, zero padding, PMI X1/X2 if requested, CQI.
- With both ranks permitted, two-port `cri-RI-PMI-CQI` uses
  `ceil(log2(K)) + 7` bits. Rank two has one zero-padding bit; neither rank
  reports LI for this report quantity. `cri-RI-CQI` uses
  `ceil(log2(K)) + 5` bits. Part 2 is empty in both cases.
- The eight two-port `cri-RI-i1-CQI` rows are explicit implementation
  rejection checks, not a claim that 3GPP forbids that report quantity.
  The implementation has no qualified two-port i1 interpretation and must
  not replace it with the full scalar PMI. TS 38.214 5.2.2.2.1 defines the
  composite i1 for the higher-port panels. A four-port i1-only literal
  serialization/transport case is covered in
  `tests/testCSIWidebandTransportLayout.m`. That is not qualification of
  the i1-conditioned CQI measurement algorithm.
- `FORMULA_FROM_CONFIG` advanced-profile rows remain legacy internal
  schema checks, NOT independent bit-exact Type-II conformance vectors.
  Production build/decode/noiseless-wire-roundtrip now reject these
  unqualified schemas with `sixgr:mimo:UnqualifiedCSIWireLayout`. They
  remain inspectable as internal size models only; passing those constructor
  vectors does not enable their use as actual NR feedback.

The validator checks field order and separate-encoding metadata as well as
bit counts for the numeric vectors. An empty CSV Part2Fields cell means an
empty sequence, not a missing measurement. No measurements are filled by
this fixture import rule.

References:

- [TS 38.212 V18.8.0](https://www.etsi.org/deliver/etsi_ts/138200_138299/138212/18.08.00_60/ts_138212v180800p.pdf)
- [TS 38.214 V18.9.0](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.09.00_60/ts_138214v180900p.pdf)
