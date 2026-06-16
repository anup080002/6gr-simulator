function ok = testSRSNoSignalNegative()
setup6GRSimToolkit("Verbose", false);
localAssertSRSNegative("no_signal_srs", "srs_detection_failed");
ok = true;
end
