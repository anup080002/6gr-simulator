function ok = testSRSGridGeneration()
setup6GRSimToolkit("Verbose", false);
b = srsStrictAnchorResult();
mapping = sixgr.phy.srs.generateSRSSymbolsAndIndices(b.Config);
tx = sixgr.phy.srs.generateSRSWaveform(b.Config);
assert(height(mapping.ResourceMappingTable) > 0, "SRS mapping table must contain real RE rows.");
assert(size(tx.Waveform, 1) > 0 && strlength(tx.TxWaveformHash) > 0, "SRS waveform and hash must be generated.");
assert(double(tx.ExpectedRECount) == height(mapping.ResourceMappingTable), "SRS expected RE count must match generated mapping rows.");
assert(~contains(lower(string(tx.TxWaveformHash)), "proxy"), "SRS waveform hash must not be proxy-labelled.");
ok = true;
end
