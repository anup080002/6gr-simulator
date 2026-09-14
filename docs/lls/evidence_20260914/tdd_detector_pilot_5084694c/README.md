# TDD physical pilot: execution passed, detector not qualified

These text receipts preserve actual results on frozen production revision
`5084694ccd76e888f971f694a2d346929e21f0b5`. They are not a new run.

- `tests.csv`: eight tests passed, one normalized SSB fixture failed.
- `summary.json` and `launcher.json`: the complete focused batch failed;
  its failure is deliberately retained.
- `receipt.json`: the physical pilot completed all eight cases, with
  `DetectorQualified=false`.
- `physical_trials.csv` and `case_summary.csv`: one development episode per
  case, not 600 independent qualification episodes.
- `audit.json` and `recomputed_existing_trials.csv`: independent accounting
  of those same retained samples. No new physical episodes were generated.

Original batch logs remain at
`logs/testall_20260914T131105593Z_e249b716`.
Complete received/transmitted samples and replay evidence remain locally at
`logs/tpd658d619_5813_43bd_ac91_f97af303ac4d` (about 1.7 GB).
The small tracked receipts do not replace or upload those raw MAT files.
Audit input hashes refer to the original files, not these text snapshots,
whose line endings may be normalized by Git.

The fixture was corrected and passed separately on `6da4bc10`; see sibling
`normalized_ssb_fixture_6da4bc10`. Production code was unchanged between
these two revisions. Neither result proves full `testAll`, statistical
detector qualification, all-measurement closure or integrated 12 dB acceptance.
The original 12 false ACKs / 1,024 bits failure remains unresolved.
