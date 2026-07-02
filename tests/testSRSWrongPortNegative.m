function ok = testSRSWrongPortNegative()
setup6GRSimToolkit("Verbose", false);
localAssertSRSNegative("wrong_port", "srs_strict_config_invalid");
ok = true;
end
