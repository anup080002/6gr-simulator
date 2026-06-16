function det = blindDecodePDCCH(rxWaveform, strictCfg, varargin)
%BLINDDECODEPDCCH Decode PDCCH using receiver-allowed config only.

p = inputParser;
addRequired(p, "rxWaveform", @isnumeric);
addRequired(p, "strictCfg", @isstruct);
addParameter(p, "Carrier", strictCfg.ToolboxCarrier, @(x) isempty(x) || isobject(x));
addParameter(p, "PDCCH", strictCfg.ToolboxPDCCH, @(x) isempty(x) || isobject(x));
addParameter(p, "RNTIAttempted", strictCfg.RNTIValue, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "DCIFormatAttempted", strictCfg.DCIFormat, @(x) ischar(x) || isstring(x));
addParameter(p, "NoiseVar", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0));
addParameter(p, "NoiseOnlyWaveform", [], @(x) isempty(x) || isnumeric(x));
addParameter(p, "ListLength", 8, @(x) isnumeric(x) && isscalar(x) && x > 0);
parse(p, rxWaveform, strictCfg, varargin{:});
opt = p.Results;

cfg = sixgr.phy.pdcch.applyPDCCHConfigToRuntime(strictCfg.BaseConfig, strictCfg, ...
    "RNTI", double(opt.RNTIAttempted), "DCIFormat", string(opt.DCIFormatAttempted), ...
    "AggregationLevel", double(strictCfg.AggregationLevel));
pdcch = opt.PDCCH;
try
    pdcch.RNTI = double(opt.RNTIAttempted);
catch
end
noiseArgs = {};
if ~isempty(opt.NoiseVar)
    noiseArgs = [noiseArgs, {"NoiseVar", double(opt.NoiseVar)}]; %#ok<AGROW>
end
if ~isempty(opt.NoiseOnlyWaveform)
    noiseArgs = [noiseArgs, {"NoiseOnlyWaveform", opt.NoiseOnlyWaveform}]; %#ok<AGROW>
end
[rx, info] = sixgr.phy.dl.PDCCH_Rx(rxWaveform, cfg, ...
    "Carrier", opt.Carrier, ...
    "PDCCH", pdcch, ...
    "K", double(strictCfg.DCIPayloadSizeBits), ...
    "ListLength", double(opt.ListLength), ...
    noiseArgs{:});

decoded = struct();
decoded.Format = string(opt.DCIFormatAttempted);
decoded.Fields = struct();
decoded.PayloadHex = "";
decoded.PayloadHash = "";
decoded.FieldTable = table();
decoded.GrantType = "";
if logical(sixgr.util.structGet(rx, "Ok", false))
    decoded = sixgr.phy.pdcch.decodeDCIPayload(rx.DCIBits, string(opt.DCIFormatAttempted), strictCfg);
end

det = struct();
det.Rx = rx;
det.Info = info;
det.DecodedDCI = decoded;
det.RNTIAttempted = double(opt.RNTIAttempted);
det.DCIFormatAttempted = upper(strrep(string(opt.DCIFormatAttempted), "-", "_"));
det.Candidates = localCandidateTable(info, rx, strictCfg, double(opt.RNTIAttempted), det.DCIFormatAttempted, decoded);
det.UsedOracleFields = "";
det.ProxyUsed = false;
det.Skipped = false;
det.ToolboxMissing = false;
end

function T = localCandidateTable(info, rx, strictCfg, rntiAttempted, dciFormatAttempted, decoded)
if isfield(info, "CandidateResults") && istable(info.CandidateResults)
    base = info.CandidateResults;
else
    base = table();
end
n = max(height(base), 1);
rows = repmat(localRow(), n, 1);
for ii = 1:n
    row = localRow();
    row.CandidateIndex = double(ii);
    row.AggregationLevel = double(strictCfg.AggregationLevel);
    row.CCEIndex = double(ii - 1);
    row.CORESETId = double(strictCfg.CORESETId);
    row.SearchSpaceId = double(strictCfg.SearchSpaceId);
    row.RNTIAttempted = double(rntiAttempted);
    row.ExpectedRNTI = double(strictCfg.RNTIValue);
    row.DCIFormatAttempted = string(dciFormatAttempted);
    if height(base) >= ii
        row.CrcPass = logical(base.DecodeOK(ii));
        row.Metric = localMetric(base, ii);
        row.LLRMeanAbs = double(row.Metric);
        row.LLRMin = -abs(double(row.Metric));
        row.LLRMax = abs(double(row.Metric));
    end
    row.Mask = string(ternary(row.CrcPass, "rnti_crc_mask_pass", "crc_fail"));
    row.PayloadHash = string(ternary(row.CrcPass, string(decoded.PayloadHash), ""));
    row.DecodedPayloadHex = string(ternary(row.CrcPass, string(decoded.PayloadHex), ""));
    row.GrantValid = false;
    row.SelectedCandidate = (logical(rx.Ok) && double(rx.CandidateIndex) == ii);
    if row.CrcPass && row.SelectedCandidate
        row.RejectedReason = "";
    else
        row.RejectedReason = "crc_or_rnti_reject";
    end
    rows(ii) = row;
end
T = struct2table(rows, "AsArray", true);
end

function row = localRow()
row = struct("CandidateIndex", NaN, "AggregationLevel", NaN, "CCEIndex", NaN, ...
    "CORESETId", NaN, "SearchSpaceId", NaN, "RNTIAttempted", NaN, ...
    "ExpectedRNTI", NaN, "DCIFormatAttempted", "", "CrcPass", false, ...
    "Mask", "", "PayloadHash", "", "DecodedPayloadHex", "", "GrantValid", false, ...
    "Metric", NaN, "LLRMeanAbs", NaN, "LLRMin", NaN, "LLRMax", NaN, ...
    "SelectedCandidate", false, "RejectedReason", "");
end

function m = localMetric(base, ii)
m = NaN;
names = string(base.Properties.VariableNames);
if any(names == "EVM_rms")
    evm = double(base.EVM_rms(ii));
    if isfinite(evm)
        m = 1 ./ (1 + max(evm, 0));
    end
end
if ~(isfinite(m)) && any(names == "ReceiverHestSINR_dB")
    s = double(base.ReceiverHestSINR_dB(ii));
    if isfinite(s)
        m = 1 ./ (1 + exp(-s / 5));
    end
end
if ~(isfinite(m))
    m = 0;
end
end

function out = ternary(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
