# Failed FDD policy batch, with successful E2E guards

Source: clean unchanged 3abf9625e75f5d52394ac53cdb8e71450213ab93.
Run: logs/testall_20260914T050951992Z_c19736ec.
The exact summary, launcher and test reports are retained alongside this note.

Result: 3 passed, 1 failed. Both E2E guards and the independent PUSCH CSI
receive-obligation test passed. testSharedCSIReportClockVariants failed with
PUCCHDetectionYAMLAuthorityRequired in its first FDD case; remaining variants
were not reached in this revision. The self-contained FDD YAML lacked explicit
detector policy. This failed batch is NOT final-source or 12 dB qualification.

The following repair keeps catalog thresholds unchanged and makes the wrapper
retain outcomes for every variant. Its results are not covered by this receipt.
No failed log, original archived patch or older source revision was removed.
