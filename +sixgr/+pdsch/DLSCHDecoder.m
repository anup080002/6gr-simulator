function decode = DLSCHDecoder(arg1, varargin)
%DLSCHDecoder Summarize or execute truthful DL-SCH decode processing.

if isstruct(arg1) && isfield(arg1, "CRCError")
    rx = arg1;
    decode = struct();
    decode.TransportBlock = sixgr.util.structGet(rx, "TransportBlock", []);
    decode.TransportBlocks = sixgr.util.structGet(rx, "TransportBlocks", {decode.TransportBlock});
    decode.CRCPass = logical(sixgr.util.structGet(rx, "Ok", false));
    decode.CRCError = logical(sixgr.util.structGet(rx, "CRCError", true));
    decode.CRCPassPerCodeword = logical(sixgr.util.structGet(rx, "CRCPassPerCodeword", decode.CRCPass));
    decode.CRCErrorPerCodeword = logical(sixgr.util.structGet(rx, "CRCErrorPerCodeword", decode.CRCError));
    decode.DecodeLatency_s = double(sixgr.util.structGet(rx, "DecodeLatency_s", NaN));
    decode.DecoderIterations = double(mean(sixgr.util.structGet(rx, "ActiveIterations", NaN), "omitnan"));
    decode.ActiveIterations = double(sixgr.util.structGet(rx, "ActiveIterations", NaN));
    decode.Source = "pdsch_rx_ldpc_decode_truth_path";
    return;
end

if iscell(arg1)
    llr = cellfun(@(x) double(x(:)), arg1(:).', "UniformOutput", false);
else
    llr = double(arg1(:));
end
nCodewords = localNumCodewords(llr);
ip = inputParser;
ip.addParameter("TransportBlockSize", [], @(x) isnumeric(x) && isvector(x) && all(x(:) > 0));
ip.addParameter("TargetCodeRate", 0.4785, @(x) isnumeric(x) && isvector(x) && all(x(:) > 0 & x(:) < 1));
ip.addParameter("RV", 0, @(x) isnumeric(x) && isvector(x) && all(x(:) >= 0));
ip.addParameter("Modulation", "16QAM", @(x) ischar(x) || isstring(x) || iscell(x));
ip.addParameter("NumLayers", 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
ip.addParameter("MaxIterations", 8, @(x) isnumeric(x) && isscalar(x) && x >= 1);
ip.addParameter("Algorithm", "Normalized min-sum", @(x) ischar(x) || isstring(x));
ip.parse(varargin{:});
opt = ip.Results;

trBlkSize = localExpandNumeric(opt.TransportBlockSize, nCodewords, "TransportBlockSize");
targetCodeRate = localExpandNumeric(opt.TargetCodeRate, nCodewords, "TargetCodeRate");
rv = localExpandNumeric(opt.RV, nCodewords, "RV");
modulation = localExpandStringList(opt.Modulation, nCodewords);
numLayers = max(1, round(double(opt.NumLayers)));
maxIter = max(1, round(double(opt.MaxIterations)));
alg = char(string(opt.Algorithm));
layerCounts = localLayerCountPerCodeword(numLayers, nCodewords);

tbCell = cell(1, nCodewords);
blkErr = false(1, nCodewords);
actIterCell = cell(1, nCodewords);
for cw = 1:nCodewords
    decObj = nrDLSCHDecoder( ...
        "TargetCodeRate", targetCodeRate(cw), ...
        "TransportBlockLength", trBlkSize(cw), ...
        "MaximumLDPCIterationCount", maxIter, ...
        "LDPCDecodingAlgorithm", alg);
    llrC = localSelectLLR(llr, cw);
    [tbRxC, blkErrC] = decObj(llrC, modulation{cw}, layerCounts(cw), rv(cw));
    decInfo = info(decObj);
    if iscell(tbRxC)
        tbRxC = tbRxC{1};
    end
    tbCell{cw} = int8(tbRxC(:));
    blkErr(cw) = logical(blkErrC);
    actIterCell{cw} = double(sixgr.util.structGet(decInfo, "ActualLDPCIterationCount", NaN));
end
crcOk = ~logical(blkErr);
crcErr = logical(blkErr);
actIter = [actIterCell{:}];

decode = struct();
decode.TransportBlock = vertcat(tbCell{:});
decode.TransportBlocks = tbCell;
decode.CRCPass = all(logical(crcOk));
decode.CRCError = any(logical(crcErr));
decode.CRCPassPerCodeword = logical(crcOk);
decode.CRCErrorPerCodeword = logical(crcErr);
decode.DecodeLatency_s = NaN;
decode.DecoderIterations = double(mean(actIter, "omitnan"));
decode.ActiveIterations = actIter;
decode.Source = "pdsch_llr_sum_decode_truth_path";
end

function n = localNumCodewords(llr)
if iscell(llr)
    n = numel(llr);
else
    n = 1;
end
end

function llrC = localSelectLLR(llr, cw)
if iscell(llr)
    llrC = double(llr{cw}(:));
else
    llrC = double(llr(:));
end
end

function values = localExpandNumeric(values, n, name)
values = double(values(:).');
if isempty(values)
    error("sixgr:pdsch:DLSCHDecoder:MissingParameter", ...
        "%s is required for DL-SCH decode.", char(string(name)));
end
if numel(values) == 1 && n > 1
    values = repmat(values, 1, n);
elseif numel(values) ~= n
    error("sixgr:pdsch:DLSCHDecoder:BadPerCodewordVector", ...
        "%s must be scalar or have one value per codeword. Expected %d, got %d.", ...
        char(string(name)), char(string(name)), n, numel(values));
end
end

function values = localExpandStringList(values, n)
if ischar(values) || isstring(values)
    values = cellstr(string(values));
else
    values = cellstr(string(values(:)));
end
if isempty(values)
    values = {'16QAM'};
end
if numel(values) == 1 && n > 1
    values = repmat(values, 1, n);
elseif numel(values) < n
    values(end+1:n) = values(end);
elseif numel(values) > n
    values = values(1:n);
end
end

function counts = localLayerCountPerCodeword(numLayers, nCodewords)
if nCodewords == 1
    counts = double(numLayers);
    return;
end
switch round(double(numLayers))
    case 5
        counts = [2 3];
    case 6
        counts = [3 3];
    case 7
        counts = [3 4];
    case 8
        counts = [4 4];
    otherwise
        error("sixgr:pdsch:DLSCHDecoder:BadCodewordLayerMapping", ...
            "Two-codeword PDSCH decode is defined for ranks 5-8. Requested rank %d.", round(double(numLayers)));
end
end
