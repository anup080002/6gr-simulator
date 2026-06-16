function ok = testPDCCHWaveformGeneration()
%TESTPDCCHWAVEFORMGENERATION Real PDCCH waveform/grid generation evidence.

setup6GRSimToolkit("Verbose", false);
b = pdcchStrictAnchorResult();
tx = sixgr.phy.pdcch.generatePDCCHWaveform(b.Config, b.Result.TxDCI10);
assert(~isempty(tx.Waveform), "Strict PDCCH Tx must produce a time-domain waveform.");
assert(~isempty(tx.Grid) && nnz(abs(tx.Grid(:)) > 0) > 0, "Strict PDCCH Tx grid must contain mapped symbols.");
assert(~isempty(tx.PDCCHInd) && ~isempty(tx.DMRSInd), "Strict PDCCH Tx must expose PDCCH and DM-RS resource indices.");
assert(strlength(string(tx.GridHash)) > 0 && strlength(string(tx.WaveformHash)) > 0, ...
    "Strict PDCCH Tx must export grid and waveform hashes.");
ok = true;
end
