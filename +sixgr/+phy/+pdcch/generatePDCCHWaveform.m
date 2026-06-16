function tx = generatePDCCHWaveform(strictCfg, dci, varargin)
%GENERATEPDCCHWAVEFORM Generate strict waveform-backed PDCCH Tx evidence.

p = inputParser;
addRequired(p, "strictCfg", @isstruct);
addRequired(p, "dci", @isstruct);
addParameter(p, "RNTI", strictCfg.RNTIValue, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "AggregationLevel", strictCfg.AggregationLevel, @(x) isnumeric(x) && isscalar(x));
parse(p, strictCfg, dci, varargin{:});
opt = p.Results;

cfg = sixgr.phy.pdcch.applyPDCCHConfigToRuntime(strictCfg.BaseConfig, strictCfg, ...
    "RNTI", double(opt.RNTI), "DCIFormat", string(dci.Format), ...
    "AggregationLevel", double(opt.AggregationLevel));
[rawTx, info] = sixgr.phy.dl.PDCCH_Tx(cfg, ...
    "DCIBits", dci.Bits, ...
    "K", double(strictCfg.DCIPayloadSizeBits), ...
    "RNTI", double(opt.RNTI), ...
    "NCellID", double(strictCfg.NCellID));

tx = rawTx;
tx.Info = info;
tx.ConfigHash = string(strictCfg.ConfigHash);
tx.DCI = dci;
tx.RNTI = double(opt.RNTI);
tx.RNTIType = string(strictCfg.RNTIType);
tx.AggregationLevel = double(opt.AggregationLevel);
tx.CandidateIndex = double(strictCfg.CandidateIndex);
tx.CCEIndex = double(strictCfg.CandidateCCEIndex);
tx.GridHash = sixgr.rrc.asn1.sha256Hex(localComplexBytes(tx.Grid));
tx.WaveformHash = sixgr.rrc.asn1.sha256Hex(localComplexBytes(tx.Waveform));
tx.PDCCHResourceHash = sixgr.rrc.asn1.sha256Hex(uint8(unicode2native(jsonencode(struct( ...
    "PDCCHInd", double(tx.PDCCHInd(:).'), "DMRSInd", double(tx.DMRSInd(:).'))), "UTF-8")));
end

function bytes = localComplexBytes(x)
data = single([real(x(:)).'; imag(x(:)).']);
bytes = typecast(data(:), "uint8");
end
