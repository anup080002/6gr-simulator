function out = LDPCSegmentationSpec(transportBlockSize, targetCodeRate)
%LDPCSEGMENTATIONSPEC Independent TS 38.212 DL-SCH segmentation oracle.
%   No production coding helper or nr* function is called.

A = localPositiveInteger(transportBlockSize, "TransportBlockSize");
R = double(targetCodeRate);
if ~(isscalar(R) && isfinite(R) && R > 0 && R <= 1)
    error("sixgr:pdsch:oracle:BadTargetCodeRate", ...
        "TargetCodeRate must be finite in (0,1].");
end
if A > 3824
    tbCRCType = "24A";
    L = 24;
else
    tbCRCType = "16";
    L = 16;
end
if A <= 292 || (A <= 3824 && R <= 0.67) || R <= 0.25
    bgn = 2;
    Kcb = 3840;
else
    bgn = 1;
    Kcb = 8448;
end
B = A + L;
if B <= Kcb
    C = 1;
    cbCRCLength = 0;
else
    cbCRCLength = 24;
    C = ceil(B / (Kcb - cbCRCLength));
end
Bprime = B + C * cbCRCLength;
payloadPerCB = ceil(Bprime / C);
paddingBitCount = C * payloadPerCB - Bprime;

if bgn == 1
    Kb = 22;
    Kfactor = 22;
    Nfactor = 66;
else
    if B > 640
        Kb = 10;
    elseif B > 560
        Kb = 9;
    elseif B > 192
        Kb = 8;
    else
        Kb = 6;
    end
    Kfactor = 10;
    Nfactor = 50;
end
liftingSizes = localLiftingSizes();
zc = liftingSizes(find(Kb * liftingSizes >= payloadPerCB, 1));
K = Kfactor * zc;
N = Nfactor * zc;
fillerPerCB = K - payloadPerCB;
fillerPositions = cell(1, C);
for c = 1:C
    fillerPositions{c} = uint32((payloadPerCB:(K - 1)).');
end

out = struct( ...
    "ContractVersion", "IndependentLDPCSegmentationSpec/v1", ...
    "TransportBlockSize", A, ...
    "TargetCodeRate", R, ...
    "TBCRCType", char(tbCRCType), ...
    "TBCRCLength", L, ...
    "B", B, ...
    "BaseGraph", bgn, ...
    "Kcb", Kcb, ...
    "NumCodeBlocks", C, ...
    "CBCRCType", char(string(localCBCRCType(C))), ...
    "CBCRCLength", cbCRCLength, ...
    "BPrime", Bprime, ...
    "PayloadPerCodeBlock", payloadPerCB, ...
    "SegmentationPaddingBitCount", paddingBitCount, ...
    "KbForLiftingSelection", Kb, ...
    "LiftingSize", zc, ...
    "LiftingSetIndex", localLiftingSetIndex(zc), ...
    "CodeBlockLength", K, ...
    "MotherCodeLength", N, ...
    "FillerCountPerCodeBlock", fillerPerCB, ...
    "FillerCount", C * fillerPerCB, ...
    "FillerPositionsZeroBased", {fillerPositions}, ...
    "Source", "independent_ts_38_212_segmentation_oracle");
end

function value = localPositiveInteger(raw, name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value > 0 && ...
        abs(value - round(value)) < 1e-9)
    error("sixgr:pdsch:oracle:BadInteger", ...
        "%s must be a positive integer.", char(string(name)));
end
value = round(value);
end

function values = localLiftingSizes()
values = [ ...
    2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 18 20 22 24 26 28 30 32 ...
    36 40 44 48 52 56 60 64 72 80 88 96 104 112 120 128 144 160 176 ...
    192 208 224 240 256 288 320 352 384];
end

function type = localCBCRCType(C)
if C > 1
    type = "24B";
else
    type = "";
end
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
end
