function tx = generatePRACHWaveform(prachCfg, varargin)
%GENERATEPRACHWAVEFORM Strict wrapper around runtime PRACH waveform generation.

tx = sixgr.rach.generatePRACHWaveform(prachCfg, varargin{:});
tx.ProxyUsed = false;
tx.Skipped = false;
tx.ToolboxMissing = false;
tx.UsedOracleFields = "";
tx.WaveformHash = sixgr.rrc.asn1.sha256Hex(typecast([real(tx.Waveform(:)); imag(tx.Waveform(:))], "uint8"));
tx.TruthStatus = "real_lls_evidence";
end
