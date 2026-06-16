function ok = testSRSWrongPortNegative()
setup6GRSimToolkit("Verbose", false);
localAssertSRSNegative("wrong_port", "srs_detection_failed");
ok = true;
end
