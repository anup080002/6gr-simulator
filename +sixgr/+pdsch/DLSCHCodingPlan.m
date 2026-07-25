classdef DLSCHCodingPlan
    %DLSCHCODINGPLAN Immutable, explicit DL-SCH coding contract.
    %   The plan freezes every input that changes CRC attachment, LDPC
    %   segmentation, rate matching, or rate recovery. Codeword indices and
    %   all externally exposed rate-match positions are zero based.

    properties (SetAccess = private)
        ContractVersion
        Immutable
        PlanID
        CodewordIndex
        TransportBlockSize
        TargetCodeRate
        RateMatchedBitCount
        RV
        Modulation
        ModulationOrder
        NumLayers
        TBCRCType
        TBCRCLength
        TransportBlockLengthWithCRC
        BaseGraph
        NumCodeBlocks
        CBCRCType
        CBCRCLength
        CodeBlockLength
        MotherCodeLength
        LiftingSize
        LiftingSetIndex
        FillerCount
        FillerPositionsZeroBased
        Nref
        Ncb
        K0
        EPerCodeBlock
        RateMatchPositionMapZeroBased
        CodingLayoutHash
        CombineSignature
        RateMatchSignature
        Source
    end

    properties (Access = private)
        CodingLayoutStorage
    end

    methods (Static)
        function obj = resolve(varargin)
            %RESOLVE Build a complete plan; coding-critical inputs are required.
            ip = inputParser;
            ip.FunctionName = "sixgr.pdsch.DLSCHCodingPlan.resolve";
            ip.addParameter("TransportBlockSize", [], ...
                @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("TargetCodeRate", [], ...
                @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("RateMatchedBitCount", [], ...
                @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("RV", [], @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("Modulation", "", ...
                @(x) ischar(x) || isstring(x));
            ip.addParameter("NumLayers", [], ...
                @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("CodewordIndex", 0, ...
                @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("Nref", [], ...
                @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
            ip.parse(varargin{:});
            opt = ip.Results;

            localRequireSpecified(opt.TransportBlockSize, "TransportBlockSize");
            localRequireSpecified(opt.TargetCodeRate, "TargetCodeRate");
            localRequireSpecified(opt.RateMatchedBitCount, "RateMatchedBitCount");
            localRequireSpecified(opt.RV, "RV");
            localRequireSpecified(opt.Modulation, "Modulation");
            localRequireSpecified(opt.NumLayers, "NumLayers");

            A = localPositiveInteger(opt.TransportBlockSize, "TransportBlockSize");
            R = double(opt.TargetCodeRate);
            if ~(isfinite(R) && R > 0 && R <= 1)
                error("sixgr:pdsch:DLSCHCodingPlan:BadTargetCodeRate", ...
                    "TargetCodeRate must be finite in (0,1].");
            end
            G = localPositiveInteger(opt.RateMatchedBitCount, "RateMatchedBitCount");
            rv = localIntegerInRange(opt.RV, 0, 3, "RV");
            modulation = upper(strtrim(string(opt.Modulation)));
            qm = localModulationOrder(modulation);
            nLayers = localIntegerInRange(opt.NumLayers, 1, 4, "NumLayers");
            codewordIndex = localIntegerInRange(opt.CodewordIndex, 0, 1, "CodewordIndex");
            quantum = qm * nLayers;
            if mod(G, quantum) ~= 0
                error("sixgr:pdsch:DLSCHCodingPlan:BadRateMatchedBitCount", ...
                    ["RateMatchedBitCount=%d must be divisible by Qm*NumLayers=%d " ...
                    "for codeword %d."], G, quantum, codewordIndex);
            end
            if isempty(opt.Nref)
                nref = [];
            else
                nref = localPositiveInteger(opt.Nref, "Nref");
            end

            args = { ...
                "Direction", "DL", ...
                "TransportBlockSize", A, ...
                "TargetCodeRate", R, ...
                "RV", rv, ...
                "Modulation", char(modulation), ...
                "NumLayers", nLayers, ...
                "RateMatchedBitCount", G};
            if ~isempty(nref)
                args = [args, {"Nref", nref}];
            end
            layout = sixgr.phy.phycode.resolveCodingLayout(args{:});
            [positionMap, ePerCB] = localTruthPositionMap(layout);
            layout.CircularBufferPositionMap = positionMap;
            layout.RateMatchPositionMap = positionMap;
            layout.E_r = uint32(ePerCB(:).');
            layout.CodewordIndex = uint8(codewordIndex);

            obj = sixgr.pdsch.DLSCHCodingPlan();
            obj.ContractVersion = "DLSCHCodingPlan/v1";
            obj.Immutable = true;
            obj.CodewordIndex = uint8(codewordIndex);
            obj.TransportBlockSize = uint32(A);
            obj.TargetCodeRate = R;
            obj.RateMatchedBitCount = uint32(G);
            obj.RV = uint8(rv);
            obj.Modulation = char(modulation);
            obj.ModulationOrder = uint8(qm);
            obj.NumLayers = uint8(nLayers);
            obj.TBCRCType = char(layout.TBCRCType);
            obj.TBCRCLength = uint16(layout.TBCRCLength);
            obj.TransportBlockLengthWithCRC = uint32(layout.B);
            obj.BaseGraph = uint8(layout.BaseGraph);
            obj.NumCodeBlocks = uint16(layout.C);
            obj.CBCRCType = char(layout.CBCRCType);
            obj.CBCRCLength = uint16(layout.CBCRCLength);
            obj.CodeBlockLength = uint32(layout.K);
            obj.MotherCodeLength = uint32(layout.N);
            obj.LiftingSize = uint16(layout.Zc);
            obj.LiftingSetIndex = uint8(localLiftingSetIndex(double(layout.Zc)));
            obj.FillerCount = uint32(layout.FillerCount);
            obj.FillerPositionsZeroBased = localZeroBasedFillers(layout.FillerPositions);
            obj.Nref = nref;
            obj.Ncb = uint32(localNcb(double(layout.N), nref));
            obj.K0 = uint32(localK0(double(layout.BaseGraph), rv, ...
                double(obj.Ncb), double(layout.N), double(layout.Zc)));
            obj.EPerCodeBlock = uint32(ePerCB(:).');
            obj.RateMatchPositionMapZeroBased = localZeroBasedPositionMap(positionMap);
            obj.CodingLayoutHash = char(layout.CodingLayoutHash);
            obj.CombineSignature = char(layout.CombineSignature);
            obj.RateMatchSignature = char(layout.RateMatchSignature);
            obj.PlanID = char("DLSCHCodingPlan/v1|cw=" + string(codewordIndex) + ...
                "|" + string(layout.RateMatchSignature));
            obj.Source = "explicit_truth_plan_from_3gpp_coding_inputs";
            layout.PlanID = obj.PlanID;
            layout.ContractVersion = obj.ContractVersion;
            obj.CodingLayoutStorage = layout;
        end
    end

    methods
        function layout = toCodingLayout(obj)
            %TOCODINGLAYOUT Return the frozen shared PHY coding contract.
            layout = obj.CodingLayoutStorage;
        end

        function s = toStruct(obj)
            %TOSTRUCT Return a serialization-friendly public plan snapshot.
            names = properties(obj);
            s = struct();
            for i = 1:numel(names)
                s.(names{i}) = obj.(names{i});
            end
        end
    end
end

function localRequireSpecified(value, name)
if isempty(value) || (isstring(value) && all(strlength(value) == 0))
    error("sixgr:pdsch:DLSCHCodingPlan:MissingParameter", ...
        "%s is required; DL-SCH coding plans do not infer coding-critical inputs.", ...
        char(string(name)));
end
end

function value = localPositiveInteger(raw, name)
value = double(raw);
if ~(isfinite(value) && value > 0 && abs(value - round(value)) < 1e-9)
    error("sixgr:pdsch:DLSCHCodingPlan:BadInteger", ...
        "%s must be a positive integer scalar.", char(string(name)));
end
value = round(value);
end

function value = localIntegerInRange(raw, lo, hi, name)
value = double(raw);
if ~(isfinite(value) && abs(value - round(value)) < 1e-9 && ...
        value >= lo && value <= hi)
    error("sixgr:pdsch:DLSCHCodingPlan:BadInteger", ...
        "%s must be an integer in [%d,%d].", char(string(name)), lo, hi);
end
value = round(value);
end

function qm = localModulationOrder(modulation)
switch upper(strrep(char(modulation), " ", ""))
    case {"QPSK", "QAM4"}
        qm = 2;
    case "16QAM"
        qm = 4;
    case "64QAM"
        qm = 6;
    case "256QAM"
        qm = 8;
    case "1024QAM"
        qm = 10;
    otherwise
        error("sixgr:pdsch:DLSCHCodingPlan:UnsupportedModulation", ...
            "Unsupported DL-SCH modulation '%s'.", char(modulation));
end
end

function [positionMap, ePerCB] = localTruthPositionMap(layout)
N = double(layout.N);
C = double(layout.C);
labels = reshape((1:(N * C)).', N, C);
Zc = double(layout.Zc);
for c = 1:C
    cbFiller = double(layout.FillerPositions{c}(:));
    encodedFiller = cbFiller - 2 * Zc;
    encodedFiller = encodedFiller(encodedFiller >= 1 & encodedFiller <= N);
    labels(encodedFiller, c) = -1;
end
if isempty(layout.Nref)
    matched = nrRateMatchLDPC(labels, double(layout.E), double(layout.RV), ...
        char(layout.Modulation), double(layout.NumLayers));
else
    matched = nrRateMatchLDPC(labels, double(layout.E), double(layout.RV), ...
        char(layout.Modulation), double(layout.NumLayers), double(layout.Nref));
end
matched = double(matched(:));
if any(matched < 1)
    error("sixgr:pdsch:DLSCHCodingPlan:PositionMapFailure", ...
        "Rate-match position-map construction retained a filler position.");
end
[rowIndex, cbIndex] = ind2sub([N C], matched);
positionMap = struct( ...
    "OutputBitIndex", uint32((1:numel(matched)).'), ...
    "MotherCodeLinearIndex", uint32(matched), ...
    "MotherCodeBitIndex", uint32(rowIndex(:)), ...
    "CodeBlockIndex", uint16(cbIndex(:)), ...
    "MotherCodeShape", uint32([N C]));
ePerCB = zeros(1, C);
for c = 1:C
    ePerCB(c) = nnz(cbIndex == c);
end
end

function values = localZeroBasedFillers(values)
for c = 1:numel(values)
    values{c} = uint32(double(values{c}(:)) - 1);
end
end

function out = localZeroBasedPositionMap(in)
out = in;
out.OutputBitIndex = uint32(double(in.OutputBitIndex) - 1);
out.MotherCodeLinearIndex = uint32(double(in.MotherCodeLinearIndex) - 1);
out.MotherCodeBitIndex = uint32(double(in.MotherCodeBitIndex) - 1);
out.CodeBlockIndex = uint16(double(in.CodeBlockIndex) - 1);
end

function ncb = localNcb(N, nref)
if isempty(nref)
    ncb = N;
else
    ncb = min(N, double(nref));
end
end

function k0 = localK0(bgn, rv, ncb, N, zc)
if bgn == 1
    factors = [0 17 33 56];
else
    factors = [0 13 25 43];
end
k0 = floor(factors(rv + 1) * ncb / N) * zc;
end

function index = localLiftingSetIndex(zc)
sets = { ...
    [2 4 8 16 32 64 128 256], ...
    [3 6 12 24 48 96 192 384], ...
    [5 10 20 40 80 160 320], ...
    [7 14 28 56 112 224], ...
    [9 18 36 72 144 288], ...
    [11 22 44 88 176 352], ...
    [13 26 52 104 208], ...
    [15 30 60 120 240]};
index = find(cellfun(@(v) any(v == zc), sets), 1) - 1;
if isempty(index)
    error("sixgr:pdsch:DLSCHCodingPlan:UnsupportedLiftingSize", ...
        "Lifting size Zc=%d is not in TS 38.212 Table 5.3.2-1.", zc);
end
end
