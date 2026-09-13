# PUCCH receiver-field extraction validation — 2026-09-13

Two isolated MATLAB R2026a batches completed with exit code 0 using -nojvm
and -singleCompThread. Neither ran a PHY simulation or loaded the large
CoupledTruthRuntime class. The three full suites were left running unchanged.

1. testPUCCHReceiverFieldAuthority passed on declared unit fixtures.
2. The same unit test passed again, then testRetainedPUCCHReceiverFields passed
   on numeric fields extracted from four prior actual PUCCH receiver captures:
   TX/RX expected lengths 3/3, 3/12, 12/3 and 12/12.

The tested extractor and unit test are exact byte copies of the corresponding
31-file staged candidate sources. This is not merely a translated algorithm
comparison. SHA-256 values:

- extractPUCCHReceiverFields.m:
  1366B8E5C80339D0D38EE3244A42EDF2645B31A7ABD93346A3502E3AA8BF1211
- testPUCCHReceiverFieldAuthority.m:
  AE6ABDF09C973C193F4D38ACFB134F05D88CD7A961F6ED9FCA9073B7C40BA6D2

The Python extraction utility copied only recorded numeric receiver fields
and receiver-owned length metadata into small MAT files. It checked those
fields against the separately retained direct receiver results. Source MAT
SHA identities are in retained_inputs_02/manifest.json. No bits, waveforms,
noise values or acceptance outcomes were generated or changed. An initial
extraction attempt failed because SciPy's default MAT struct-field limit was
31 characters; the successful attempt enabled long field names without
renaming or truncating the actual metadata. Its incomplete first output
directory remains preserved and is not qualification input.

The MATLAB checks show that transmitter/scoring metadata does not affect
receiver field ownership. A 12-bit receiver context carries two HARQ bits,
one SR bit and nine CSI-part-1 bits in these captures; a 3-bit context carries
three HARQ bits. Exact decoded fields and padding are preserved.

Limitations: these checks do not execute the revised coordinator, establish
independent gNB context installation, qualify normal PUCCH/PUSCH HARQ mapping,
or rerun RF/CRC/detector qualification. In particular, the prior TX3/RX12 CRC
failure remains a CRC failure even though its field layout can be extracted.
The full 31-file source remains staged, unapplied, uncommitted and not pushed.
Final-source regressions and the 12 dB scenario remain required.
