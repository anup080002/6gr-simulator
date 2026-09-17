# Selected-source TDD test failure: evidence, not a passing receipt

Observed 17 September 2026 at 14:42 IST in the still-running unfiltered
`testAll`, source `6be2985f9f6b78b4349c91ab71da81f32e25f7c8`, MATLAB
R2026a Update 4. The source checkout was not edited.

Console: `logs/research_selected_iq_6be2985f_20260917/matlab.log`.
Test: `tests/testResearchTDDLink.m`, lines 32-33.

```text
TEST_FAILURE identifier=MATLAB:table:UnrecognizedVarName
Unrecognized table variable name 'ClippedComponents'.
Error in testResearchTDDLink (line 33)
assert(height(iq)==8 && all(iq.ClippedComponents==0));
FULLSTACK_TEST_END testResearchTDDLink FAIL
[FAIL] testResearchTDDLink (123.20s)
```

The test calls `readtable` without an explicit delimiter. Its original
comma-separated `iq_manifest.csv` includes `ClippedComponents` in the header.
PowerShell `Import-Csv -Delimiter ','` reads eight rows, all with zero clipped
components and 491,520 samples. This is a read-only cross-parser observation,
not a MATLAB test rerun or a replacement verdict. The exact automatically
inferred MATLAB delimiter in this failed test was not observed.

The accompanying original `manifest.json` reports `Status=completed`,
`ResultOk=true`, 7/7 successful transport blocks, `StandardNR=false`, and
`InstrumentImportVerified=false`. These native-run results do not override the
test failure or prove its later, unexecuted assertions. This is the 1 ms base
fixture, not the selected rate-0.82 10 ms capture.

Both files are byte-for-byte copies, SHA256 checked against this retained root:

`C:/Users/anup0/AppData/Local/Temp/tp6b511d4c_32dd_4469_8356_03958f678171/lls/lls_7ghz_400mhz_1024qam_tdd_30db/integrated`

No bug fix, acceptance relaxation, regenerated IQ, or failure-to-pass relabeling
was performed. The unfiltered suite continued after this failure.
