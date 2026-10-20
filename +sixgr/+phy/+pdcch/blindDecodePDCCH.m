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
assert(isempty(opt.NoiseVar) && isempty(opt.NoiseOnlyWaveform), ...
    'sixgr:phy:pdcch:OracleNoiseInputForbidden', ...
    ['Strict practical PDCCH reception must estimate noise from received ' ...
     'samples. Injected variance and generated noise are scoring-only evidence.']);

cfg = sixgr.phy.pdcch.applyPDCCHConfigToRuntime(strictCfg.BaseConfig, strictCfg, ...
    "RNTI", double(opt.RNTIAttempted), "DCIFormat", string(opt.DCIFormatAttempted), ...
    "AggregationLevel", double(strictCfg.AggregationLevel));
pdcch = opt.PDCCH;
try
    pdcch.RNTI = double(opt.RNTIAttempted);
catch
end
[rx, info] = sixgr.phy.dl.PDCCH_Rx(rxWaveform, cfg, ...
    "Carrier", opt.Carrier, ...
    "PDCCH", pdcch, ...
    "K", double(strictCfg.DCIPayloadSizeBits), ...
    "ListLength", double(opt.ListLength));
% Keep physical hypothesis selection separate from later schema parsing.
% A CRC-valid payload decoded under a deliberately wrong DCI schema is a
% semantic rejection, not a noise-only false alarm at another candidate.
rx.PhysicalHypothesisSelected=logical(rx.Ok);

decoded = struct();
decoded.Format = string(opt.DCIFormatAttempted);
decoded.Fields = struct();
decoded.PayloadHex = "";
decoded.PayloadHash = "";
decoded.FieldTable = table();
decoded.GrantType = "";
if logical(sixgr.util.structGet(rx, "Ok", false))
    try
        decoded = sixgr.phy.pdcch.decodeDCIPayload( ...
            rx.DCIBits, string(opt.DCIFormatAttempted), strictCfg);
    catch ME
        if ~startsWith(string(ME.identifier), "sixgr:phy:pdcch:")
            rethrow(ME);
        end
        % CRC success is necessary but not sufficient for a blind
        % hypothesis.  A payload that cannot be parsed under the attempted
        % DCI schema is a rejected candidate and must never materialize a
        % grant or abort evaluation of the remaining hypotheses.
        rx.Ok = false;
        rx.DecodeOK = false;
        rx.DCIParseErrorIdentifier = string(ME.identifier);
        % Retain every attempted candidate's actual CRC/LLR evidence.
    end
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
n = height(base);
rows = repmat(localRow(), n, 1);
for ii = 1:n
    row = localRow();
    row.CandidateIndex = double(base.CandidateIndex(ii));
    row.AggregationLevel = double(base.AggregationLevel(ii));
    row.CCEIndex = double(base.CCEIndex(ii));
    row.CORESETId = double(strictCfg.CORESETId);
    row.SearchSpaceId = double(strictCfg.SearchSpaceId);
    row.RNTIAttempted = double(rntiAttempted);
    row.ExpectedRNTI = double(strictCfg.RNTIValue);
    row.DCIFormatAttempted = string(dciFormatAttempted);
    row.DecodeAttempted = logical(base.DecodeAttempted(ii));
    row.CrcPass = isfinite(base.ErrFlag(ii)) && double(base.ErrFlag(ii))==0;
    row.LLRMeanAbs = double(base.LLRMeanAbs(ii));
    row.LLRMin = double(base.LLRMin(ii));
    row.LLRMax = double(base.LLRMax(ii));
    row.LLRCount = double(base.LLRCount(ii));
    row.Metric = row.LLRMeanAbs;
    row.Mask = string(ternary(row.CrcPass, "rnti_crc_mask_pass", "crc_fail"));
    row.PayloadHash = string(base.PayloadHash(ii));
    row.DecodedPayloadHex = string(base.DecodedPayloadHex(ii));
    row.GrantValid = false;
    row.SelectedCandidate = (rx.PhysicalHypothesisSelected && double(rx.CandidateIndex) == row.CandidateIndex && ...
        double(rx.DCIPayloadLength)==double(base.DCIPayloadLength(ii)));
    if row.CrcPass && row.SelectedCandidate
        row.RejectedReason = "";
        if ~rx.Ok
            row.RejectedReason="selected_physical_payload_rejected_by_DCI_schema";
        end
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
    "DecodeAttempted", false, ...
    "Metric", NaN, "LLRMeanAbs", NaN, "LLRMin", NaN, "LLRMax", NaN, "LLRCount", 0, ...
    "SelectedCandidate", false, "RejectedReason", "");
end

function out = ternary(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
