function ok = testHARQSoftBufferPositionAware()
%TESTHARQSOFTBUFFERPOSITIONAWARE Position-map HARQ soft-buffer contract.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
if ~localHaveRequired5G()
    error("sixgr:test:Required5GToolboxUnavailable", ...
        ["testHARQSoftBufferPositionAware requires the 5G Toolbox APIs " ...
        "checked by localHaveRequired5G; unavailable tests cannot pass."]);
end

cfg = struct("A", 8448, "R", 0.48, "Modulation", "16QAM", ...
    "NumLayers", 2, "Direction", "DL");
layout0 = localLayout(cfg, 0);
layout3 = localLayout(cfg, 3);

cur0 = localObservation(layout0, 1.25);
[out0, info0] = sixgr.phy.harq.combineSoftLLR(cur0, [], "CurrentLayout", layout0);
assert(~logical(info0.Applied), "Initial RV must store, not combine, without a prior buffer.");
assert(isstruct(info0.SoftBuffer) && isfield(info0.SoftBuffer, "LLRSum"), ...
    "Initial RV must return a canonical HARQ soft buffer.");
assert(isequal(out0, cur0), "Initial no-prior output must equal the current mother-code LLRs.");

cur3 = localObservation(layout3, -0.75);
[combined, info3] = sixgr.phy.harq.combineSoftLLR(cur3, info0.SoftBuffer, ...
    "CurrentLayout", layout3);
expected = cur3 + cur0;
overlapExpected = numel(intersect(localMappedPositions(layout0), localMappedPositions(layout3)));
assert(logical(info3.Applied) && logical(info3.PositionAware), ...
    "Different RVs with the same CodingLayoutHash must combine position-aware.");
assert(localEqualWithInf(combined, expected), ...
    "Combined mother-code LLRs must equal the sum at exact recovered positions.");
assert(double(info3.OverlapPositionCount) == double(overlapExpected), ...
    "Overlap count must be derived from actual mother-code positions.");

[duplicate, dupInfo] = sixgr.phy.harq.combineSoftLLR(cur0, info0.SoftBuffer, ...
    "CurrentLayout", layout0);
idx0 = double(info0.SoftBuffer.ObservedLinearIndex(:));
assert(all(double(dupInfo.SoftBuffer.ObservationWeight(idx0)) >= 2), ...
    "Duplicate RV observations must increase observation weights at matching positions.");
assert(localEqualWithInf(duplicate(idx0), 2 * cur0(idx0)), ...
    "Duplicate RV observations must add only their mapped mother-code positions.");

bad = layout0;
bad.CodingLayoutHash = "different_layout_hash";
bad.CombineSignature = "different_layout_hash";
[badOut, badInfo] = sixgr.phy.harq.combineSoftLLR(cur0, info0.SoftBuffer, ...
    "CurrentLayout", bad);
assert(~logical(badInfo.Applied) && contains(string(badInfo.Reason), "coding_layout_mismatch"), ...
    "Same-shape but different CodingLayoutHash must reject instead of adding.");
assert(isequal(badOut, cur0), "Rejected combine must keep the current observation.");

localAssertHARQEntityLifecycle(info0.SoftBuffer, info3.SoftBuffer, cfg.A);

fprintf("HARQSoftBufferPositionAware: rv0Positions=%d rv3Positions=%d overlap=%d\n", ...
    nnz(info0.SoftBuffer.ObservationWeight(:) > 0), ...
    nnz(info3.SoftBuffer.ObservationWeight(:) > 0), ...
    double(info3.OverlapPositionCount));
ok = true;
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

function rec = localObservation(layout, value)
rec = zeros(double(layout.MotherCodeLength), double(layout.NumCodeBlocks));
idx = localMappedPositions(layout);
rec(idx) = double(value);
end

function idx = localMappedPositions(layout)
idx = double(layout.RateMatchPositionMap.MotherCodeLinearIndex(:));
idx = idx(isfinite(idx) & idx >= 1 & idx <= double(layout.MotherCodeLength) * double(layout.NumCodeBlocks));
idx = unique(round(idx), "stable");
end

function localAssertHARQEntityLifecycle(buffer0, buffer3, tbsBits)
harq = sixgr.l2.mac.HARQEntity(struct(), "Direction", "DL", ...
    "NumProcesses", 1, "MaxRetx", 2);
rnti = 101;
txp = harq.allocate(rnti, 0, ceil(tbsBits / 8), "NewData", true);
harq.onTx(rnti, txp.HARQ.HarqID, uint8(zeros(tbsBits, 1)), struct("TBSBits", tbsBits), 0);
harq.storeSoftBuffer(rnti, txp.HARQ.HarqID, buffer0);
stored = harq.getSoftBuffer(rnti, txp.HARQ.HarqID);
assert(isfield(stored, "LLRSum"), "HARQEntity must store the canonical soft buffer.");

harq.onFeedback(rnti, txp.HARQ.HarqID, false, "SourceSlot", 0);
stored = harq.getSoftBuffer(rnti, txp.HARQ.HarqID);
assert(isfield(stored, "LLRSum"), "NACK must preserve the soft buffer for retransmission.");

retx = harq.allocate(rnti, 1, ceil(tbsBits / 8), "NewData", false);
harq.onTx(rnti, retx.HARQ.HarqID, uint8(zeros(tbsBits, 1)), struct("TBSBits", tbsBits), 1);
harq.storeSoftBuffer(rnti, retx.HARQ.HarqID, buffer3);
harq.onFeedback(rnti, retx.HARQ.HarqID, true, "SourceSlot", 1);
stored = harq.getSoftBuffer(rnti, retx.HARQ.HarqID);
assert(isempty(fieldnames(stored)), "ACK must clear the matching HARQ soft buffer.");

txp2 = harq.allocate(rnti, 3, ceil(tbsBits / 8), "NewData", true);
harq.onTx(rnti, txp2.HARQ.HarqID, uint8(zeros(tbsBits, 1)), struct("TBSBits", tbsBits), 3);
harq.storeSoftBuffer(rnti, txp2.HARQ.HarqID, buffer0);
tf = harq.hasFreeProcess(rnti, 6); %#ok<NASGU> trigger stale expiry
stored = harq.getSoftBuffer(rnti, txp2.HARQ.HarqID);
assert(~tf && isfield(stored, "LLRSum"), ...
    "Elapsed slots must not synthesize a HARQ timeout or clear soft state.");
harq.onFeedback(rnti, txp2.HARQ.HarqID, true, "SourceSlot", 3);
stored = harq.getSoftBuffer(rnti, txp2.HARQ.HarqID);
assert(isempty(fieldnames(stored)), ...
    "Explicit ACK must clear the matching HARQ soft buffer.");

try
    sixgr.l2.mac.HARQEntity(struct(), "Direction", "DL", ...
        "StaleProcessTimeoutSlots", 2);
    error("testHARQSoftBufferPositionAware:ExpectedTimeoutGuard", ...
        "Finite HARQ age timeout was accepted.");
catch ME
    assert(string(ME.identifier) == ...
        "sixgr:mac:SynthesizedHARQTimeoutForbidden", ...
        "Finite HARQ age timeout must fail with the typed guard.");
end
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
        error("testHARQSoftBufferPositionAware:BadModulation", "Unsupported modulation.");
end
end

function tf = localEqualWithInf(a, b)
a = double(a);
b = double(b);
tf = isequal(size(a), size(b)) && all((a(:) == b(:)) | (isinf(a(:)) & isinf(b(:))));
end

function tf = localHaveRequired5G()
tf = exist("nrDLSCHInfo", "file") == 2 && ...
    exist("nrRateMatchLDPC", "file") == 2 && ...
    exist("nrRateRecoverLDPC", "file") == 2 && ...
    exist("nrLDPCEncode", "file") == 2;
end
