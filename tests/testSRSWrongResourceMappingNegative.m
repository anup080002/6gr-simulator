function ok = testSRSWrongResourceMappingNegative()
setup6GRSimToolkit("Verbose", false);
localAssertSRSNegative("wrong_resource_mapping", "srs_detection_failed");
ok = true;
end
