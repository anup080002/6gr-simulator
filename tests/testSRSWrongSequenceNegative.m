function ok = testSRSWrongSequenceNegative()
setup6GRSimToolkit("Verbose", false);
localAssertSRSNegative("wrong_sequence_id", "srs_detection_failed");
ok = true;
end
