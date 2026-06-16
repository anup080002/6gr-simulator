function ok = testSRSWrongCombCyclicShiftNegative()
setup6GRSimToolkit("Verbose", false);
localAssertSRSNegative("wrong_comb_cyclic_shift", "srs_detection_failed");
ok = true;
end
