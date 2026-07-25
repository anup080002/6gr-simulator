function ok = testPDSCHLDPCEncodingCanonical()
%TESTPDSCHLDPCENCODINGCANONICAL Check explicit stages against canonical API.
%   The supplied frozen pack has CRC/TBS vectors but no external LDPC
%   parity fixture, so this test makes the comparison source explicit.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
rng(38212, "twister");
cases = [ ...
    struct("A",384,  "R",0.30, "Mod","QPSK", "NL",1, "RV",0), ...
    struct("A",4096, "R",0.55, "Mod","16QAM","NL",2, "RV",2), ...
    struct("A",9000, "R",0.70, "Mod","64QAM","NL",1, "RV",3)];

for i = 1:numel(cases)
    cfg = cases(i);
    seg = sixgr.pdsch.oracle.LDPCSegmentationSpec(cfg.A, cfg.R);
    qm = localQm(cfg.Mod);
    quantum = qm * cfg.NL;
    G = quantum * ceil(seg.MotherCodeLength * seg.NumCodeBlocks / quantum);
    plan = sixgr.pdsch.DLSCHCodingPlan.resolve( ...
        "TransportBlockSize", cfg.A, "TargetCodeRate", cfg.R, ...
        "RateMatchedBitCount", G, "RV", cfg.RV, ...
        "Modulation", cfg.Mod, "NumLayers", cfg.NL);
    bits = int8(randi([0 1], cfg.A, 1));
    encoded = sixgr.pdsch.DLSCHEncoder(bits, plan);

    tbCRC = nrCRCEncode(bits, plan.TBCRCType);
    codeBlocks = nrCodeBlockSegmentLDPC(tbCRC, double(plan.BaseGraph));
    mother = nrLDPCEncode(codeBlocks, double(plan.BaseGraph));
    rateMatched = nrRateMatchLDPC(mother, G, cfg.RV, cfg.Mod, cfg.NL);
    assert(isequal(encoded.TBCRCBlock(:), int8(tbCRC(:))), ...
        "Case %d TB CRC stage mismatch.", i);
    assert(isequal(encoded.CodeBlocks, int8(codeBlocks)), ...
        "Case %d code-block stage mismatch.", i);
    assert(isequal(encoded.EncodedCodeBlocks, int8(mother)), ...
        "Case %d LDPC stage mismatch.", i);
    assert(isequal(encoded.RateMatchedBits(:), int8(rateMatched(:))), ...
        "Case %d rate-matched stage mismatch.", i);
    assert(string(encoded.CodingPlanID) == string(plan.PlanID), ...
        "Case %d immutable plan ID was not propagated.", i);
end

fprintf("PDSCH LDPC canonical stages: %d/%d exact; bit mismatches=0\n", ...
    numel(cases), numel(cases));
ok = true;
end

function qm = localQm(modulation)
switch upper(char(string(modulation)))
    case "QPSK"
        qm = 2;
    case "16QAM"
        qm = 4;
    case "64QAM"
        qm = 6;
    case "256QAM"
        qm = 8;
    otherwise
        error("testPDSCHLDPCEncodingCanonical:BadModulation", ...
            "Unsupported modulation.");
end
end
