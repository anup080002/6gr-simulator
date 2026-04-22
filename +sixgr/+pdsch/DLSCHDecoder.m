function decode = DLSCHDecoder(arg1, varargin)
%DLSCHDecoder Summarize or execute truthful DL-SCH decode processing.

if isstruct(arg1) && isfield(arg1, "CRCError")
    rx = arg1;
    decode = struct();
    decode.TransportBlock = sixgr.util.structGet(rx, "TransportBlock", []);
    decode.CRCPass = logical(sixgr.util.structGet(rx, "Ok", false));
    decode.CRCError = logical(sixgr.util.structGet(rx, "CRCError", true));
    decode.DecodeLatency_s = double(sixgr.util.structGet(rx, "DecodeLatency_s", NaN));
    decode.DecoderIterations = double(mean(sixgr.util.structGet(rx, "ActiveIterations", NaN), "omitnan"));
    decode.Source = "pdsch_rx_ldpc_decode_truth_path";
    return;
end

llr = double(arg1(:));
ip = inputParser;
ip.addParameter("TransportBlockSize", [], @(x) isnumeric(x) && isscalar(x) && x > 0);
ip.addParameter("TargetCodeRate", 0.4785, @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
ip.addParameter("RV", 0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
ip.addParameter("Modulation", "16QAM", @(x) ischar(x) || isstring(x));
ip.addParameter("NumLayers", 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
ip.addParameter("MaxIterations", 8, @(x) isnumeric(x) && isscalar(x) && x >= 1);
ip.addParameter("Algorithm", "Normalized min-sum", @(x) ischar(x) || isstring(x));
ip.parse(varargin{:});
opt = ip.Results;

trBlkSize = double(opt.TransportBlockSize);
targetCodeRate = double(opt.TargetCodeRate);
rv = double(opt.RV);
modulation = char(string(opt.Modulation));
numLayers = max(1, round(double(opt.NumLayers)));
maxIter = max(1, round(double(opt.MaxIterations)));
alg = char(string(opt.Algorithm));

decObj = nrDLSCHDecoder( ...
    "TargetCodeRate", targetCodeRate, ...
    "TransportBlockLength", trBlkSize, ...
    "MaximumLDPCIterationCount", maxIter, ...
    "LDPCDecodingAlgorithm", alg);
[tbRx, blkErr] = decObj(llr, modulation, numLayers, rv);
decInfo = info(decObj);
if iscell(tbRx)
    tbRx = tbRx{1};
end
crcOk = ~logical(blkErr);
crcErr = logical(blkErr);
actIter = double(sixgr.util.structGet(decInfo, "ActualLDPCIterationCount", NaN));

decode = struct();
decode.TransportBlock = tbRx;
decode.CRCPass = logical(crcOk);
decode.CRCError = logical(crcErr);
decode.DecodeLatency_s = NaN;
decode.DecoderIterations = double(mean(actIter, "omitnan"));
decode.ActiveIterations = actIter;
decode.Source = "pdsch_llr_sum_decode_truth_path";
end
