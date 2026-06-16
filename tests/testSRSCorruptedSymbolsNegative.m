function ok = testSRSCorruptedSymbolsNegative()
setup6GRSimToolkit("Verbose", false);
localAssertSRSNegative("corrupted_srs_symbols", "srs_channel_estimate_unavailable");
ok = true;
end
