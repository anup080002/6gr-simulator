# Failed actual TDD PUSCH receive-to-commit batch

Source: clean unchanged 41854a9b42996d204f66dc89a92a9ff7b60d893d.
Original logs/testall_20260914T061303251Z_abe6cf37/ is preserved.
Three passed, one failed. The new test passed actual PUSCH reception but failed
common commit when its returned grant lacked ULTotalDAIAuthority. Its snapshot
whitelist also omitted UCIOnPUSCHFeedbackBitIndices. The receiving context was
successfully built before PHY execution, distinguishing loss at return from
missing initial scheduling authority. No common-commit or 12 dB pass is claimed.
Adjacent JSON files are exact copies of the failed terminal receipts.
