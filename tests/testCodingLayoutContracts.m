function ok = testCodingLayoutContracts()
%TESTCODINGLAYOUTCONTRACTS Canonical CRC/LDPC/rate-match layout checks.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
if ~localHaveRequired5G()
    error("sixgr:test:Required5GToolboxUnavailable", ...
        ["testCodingLayoutContracts requires the 5G Toolbox APIs " ...
        "checked by localHaveRequired5G; unavailable tests cannot pass."]);
end

rng(7404, "twister");
configs = localRepresentativeConfigs();
rvOrder = [0 2 3 1];
for i = 1:numel(configs)
    cfg = configs(i);
    for rv = rvOrder
        layout = localLayout(cfg, rv);
        localAssertToolboxAgreement(cfg, rv, layout);
        localAssertPositionMap(cfg, rv, layout);
    end
end

roundtripErrors = 0;
roundtripCfg = configs(2);
for k = 1:100
    rv = rvOrder(mod(k - 1, numel(rvOrder)) + 1);
    layout = localFullMotherLayout(roundtripCfg, rv);
    roundtripErrors = roundtripErrors + localNoiselessRoundTrip(roundtripCfg, rv, layout);
end
assert(roundtripErrors == 0, "Noiseless 100-random-TB coding roundtrips must have zero bit errors.");

localAssertHARQLayoutGuard(configs(2));

fprintf("CodingLayoutContracts: configs=%d rv=%d randomRoundTrips=100 bitErrors=%d\n", ...
    numel(configs), numel(rvOrder), roundtripErrors);
ok = true;
end

function configs = localRepresentativeConfigs()
configs = struct( ...
    "A", {384, 8448, 16000, 32160}, ...
    "R", {0.30, 0.48, 0.65, 0.78}, ...
    "Modulation", {"QPSK", "16QAM", "64QAM", "256QAM"}, ...
    "NumLayers", {1, 2, 3, 4}, ...
    "Direction", {"DL", "UL", "DL", "UL"});
end

function layout = localLayout(cfg, rv)
E = localRateMatchedLength(cfg);
layout = sixgr.phy.phycode.resolveCodingLayout( ...
    "Direction", cfg.Direction, ...
    "TransportBlockSize", cfg.A, ...
    "TargetCodeRate", cfg.R, ...
    "RV", rv, ...
    "Modulation", cfg.Modulation, ...
    "NumLayers", cfg.NumLayers, ...
    "RateMatchedBitCount", E);
end

function layout = localFullMotherLayout(cfg, rv)
layout0 = localLayout(cfg, rv);
qm = localQm(cfg.Modulation);
quantum = qm * cfg.NumLayers;
E = double(layout0.MotherCodeLength) * double(layout0.NumCodeBlocks);
E = ceil(E / quantum) * quantum;
layout = sixgr.phy.phycode.resolveCodingLayout( ...
    "Direction", cfg.Direction, ...
    "TransportBlockSize", cfg.A, ...
    "TargetCodeRate", cfg.R, ...
    "RV", rv, ...
    "Modulation", cfg.Modulation, ...
    "NumLayers", cfg.NumLayers, ...
    "RateMatchedBitCount", E);
end

function localAssertToolboxAgreement(cfg, rv, layout)
tb = int8(randi([0 1], cfg.A, 1));
tbCrc = sixgr.phy.tb.attachCRC(tb, layout.TBCRCType);
[cbs, ~] = sixgr.phy.tb.segmentLDPC(tbCrc, double(layout.BaseGraph));
[enc, ~] = sixgr.phy.phycode.ldpcEncode(cbs, double(layout.BaseGraph));
[rm, rmInfo] = sixgr.phy.phycode.rateMatchLDPC(enc, double(layout.RateMatchedBitCount), ...
    rv, cfg.Modulation, cfg.NumLayers);
refRM = nrRateMatchLDPC(enc, double(layout.RateMatchedBitCount), rv, cfg.Modulation, cfg.NumLayers);
assert(isequal(rm(:), refRM(:)), "rateMatchLDPC must be bit-exact with nrRateMatchLDPC.");
assert(isequal(uint32(rmInfo.PositionMap.MotherCodeLinearIndex), ...
    uint32(layout.RateMatchPositionMap.MotherCodeLinearIndex)), ...
    "Rate-match wrapper map must match CodingLayout map.");

llr = 20 * (1 - 2 * double(rm(:)));
[rec, ~] = sixgr.phy.phycode.rateRecoverLDPC(llr, cfg.A, cfg.R, rv, cfg.Modulation, cfg.NumLayers, ...
    double(layout.NumCodeBlocks), [], "CodingLayout", layout);
refRec = nrRateRecoverLDPC(llr, cfg.A, cfg.R, rv, cfg.Modulation, cfg.NumLayers, double(layout.NumCodeBlocks));
assert(localEqualWithInf(rec, refRec), "rateRecoverLDPC must be bit-exact with nrRateRecoverLDPC.");
end

function localAssertPositionMap(cfg, rv, layout)
labels = reshape((1:(double(layout.MotherCodeLength) * double(layout.NumCodeBlocks))).', ...
    double(layout.MotherCodeLength), double(layout.NumCodeBlocks));
direct = nrRateMatchLDPC(labels, double(layout.RateMatchedBitCount), rv, cfg.Modulation, cfg.NumLayers);
assert(isequal(uint32(direct(:)), uint32(layout.RateMatchPositionMap.MotherCodeLinearIndex(:))), ...
    "CodingLayout position map must equal Toolbox label-rate-match locations.");
assert(numel(layout.RateMatchPositionMap.OutputBitIndex) == double(layout.RateMatchedBitCount), ...
    "Position map must have one entry per rate-matched output bit.");
end

function bitErrors = localNoiselessRoundTrip(cfg, rv, layout)
tb = int8(randi([0 1], cfg.A, 1));
tbCrc = sixgr.phy.tb.attachCRC(tb, layout.TBCRCType);
[cbs, ~] = sixgr.phy.tb.segmentLDPC(tbCrc, double(layout.BaseGraph));
enc = sixgr.phy.phycode.ldpcEncode(cbs, double(layout.BaseGraph));
rm = sixgr.phy.phycode.rateMatchLDPC(enc, double(layout.RateMatchedBitCount), rv, cfg.Modulation, cfg.NumLayers);
llr = 50 * (1 - 2 * double(rm(:)));
rec = sixgr.phy.phycode.rateRecoverLDPC(llr, cfg.A, cfg.R, rv, cfg.Modulation, cfg.NumLayers, ...
    double(layout.NumCodeBlocks), [], "CodingLayout", layout);
decCell = cell(1, size(rec, 2));
maxLen = 0;
for c = 1:size(rec, 2)
    dc = int8(sixgr.phy.phycode.ldpcDecode(rec(:, c), double(layout.BaseGraph), 12, "Normalized min-sum"));
    decCell{c} = dc(:);
    maxLen = max(maxLen, numel(dc));
end
dec = zeros(maxLen, size(rec, 2), "int8");
for c = 1:size(rec, 2)
    dec(1:numel(decCell{c}), c) = decCell{c};
end
tbCrcRx = sixgr.phy.tb.desegmentLDPC(dec, layout);
[tbRx, ok] = sixgr.phy.tb.checkCRC(tbCrcRx, layout.TBCRCType);
assert(logical(ok), "Noiseless coding roundtrip must pass TB CRC.");
bitErrors = sum(int8(tbRx(:)) ~= tb(:));
end

function localAssertHARQLayoutGuard(cfg)
layout0 = localLayout(cfg, 0);
layout2 = localLayout(cfg, 2);
cur = zeros(double(layout0.MotherCodeLength), double(layout0.NumCodeBlocks));
prior = ones(size(cur));
[combined, info] = sixgr.phy.harq.combineSoftLLR(cur, prior, ...
    "CurrentLayout", layout2, "PriorLayout", layout0);
idx0 = unique(double(layout0.RateMatchPositionMap.MotherCodeLinearIndex(:)), "stable");
idx0 = idx0(isfinite(idx0) & idx0 >= 1 & idx0 <= numel(combined));
assert(logical(info.Applied) && logical(sixgr.util.structGet(info, "PositionAware", false)) && ...
    all(combined(idx0) == 1), ...
    "HARQ combine must accept different RVs with the same mother-code layout.");
bad = layout0;
bad.CodingLayoutHash = "different_layout";
bad.CombineSignature = "different_layout";
[~, badInfo] = sixgr.phy.harq.combineSoftLLR(cur, prior, ...
    "CurrentLayout", layout2, "PriorLayout", bad);
assert(~logical(badInfo.Applied) && contains(string(badInfo.Reason), "coding_layout_mismatch"), ...
    "HARQ combine must reject shape-equal buffers with different CodingLayout signatures.");
end

function E = localRateMatchedLength(cfg)
qm = localQm(cfg.Modulation);
quantum = qm * cfg.NumLayers;
E = ceil((cfg.A + 24) / cfg.R);
E = max(quantum, ceil(E / quantum) * quantum);
end

function qm = localQm(modulation)
switch upper(char(string(modulation)))
    case {'PI/2-BPSK','BPSK'}
        qm = 1;
    case 'QPSK'
        qm = 2;
    case '16QAM'
        qm = 4;
    case '64QAM'
        qm = 6;
    case '256QAM'
        qm = 8;
    otherwise
        error("testCodingLayoutContracts:BadModulation", "Unsupported modulation.");
end
end

function tf = localEqualWithInf(a, b)
a = double(a);
b = double(b);
tf = isequal(size(a), size(b)) && all((a(:) == b(:)) | (isinf(a(:)) & isinf(b(:))));
end

function tf = localHaveRequired5G()
tf = exist("nrDLSCHInfo", "file") == 2 && ...
    exist("nrULSCHInfo", "file") == 2 && ...
    exist("nrRateMatchLDPC", "file") == 2 && ...
    exist("nrRateRecoverLDPC", "file") == 2 && ...
    exist("nrLDPCEncode", "file") == 2 && ...
    exist("nrLDPCDecode", "file") == 2;
end
