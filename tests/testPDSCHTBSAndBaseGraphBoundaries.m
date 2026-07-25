function ok = testPDSCHTBSAndBaseGraphBoundaries()
%TESTPDSCHTBSANDBASEGRAPHBOUNDARIES Check all frozen TBS/CRC/BG rows.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
vectorDir = fullfile(fileparts(mfilename("fullpath")), "vectors", "pdsch");
inputT = localReadInput(fullfile(vectorDir, "pdsch_coding_tbs_test_vectors.csv"));
expectedT = localReadExpected(fullfile(vectorDir, "expected_pdsch_tbs_basegraph.csv"));
assert(height(inputT) == 23 && height(expectedT) == 23, ...
    "PDSCH TBS vector pack must contain exactly 23 input and expected rows.");

positiveCount = 0;
negativeCount = 0;
planCount = 0;
for i = 1:height(inputT)
    row = inputT(i, :);
    expected = expectedT(expectedT.CaseID == row.CaseID, :);
    assert(height(expected) == 1, "Missing expected row for %s.", row.CaseID);
    call = @() sixgr.pdsch.oracle.TBSAndBaseGraphSpec( ...
        "NPRB", row.NPRB, ...
        "NScheduledSymbols", row.NScheduledSymbols, ...
        "NDMRSREPerPRB", row.NDMRSREPerPRB, ...
        "NOverheadREPerPRB", row.NOverheadREPerPRB, ...
        "Qm", row.Qm, ...
        "TargetCodeRate", row.TargetCodeRate, ...
        "NumLayers", row.NumLayers, ...
        "TBScaling", row.TBScaling);
    if row.ExpectedStatus == "ERROR"
        localAssertIdentifier(call, row.ExpectedError);
        negativeCount = negativeCount + 1;
        continue;
    end

    actual = call();
    localAssertClose(actual.NREPrimePerPRB, expected.NREPrimePerPRB, row.CaseID);
    localAssertClose(actual.NRE, expected.NRE, row.CaseID);
    localAssertClose(actual.NInfo, expected.NInfo, row.CaseID);
    localAssertClose(actual.NInfoPrime, expected.NInfoPrime, row.CaseID);
    assert(actual.CForTBS == expected.CForTBS, "%s C-for-TBS mismatch.", row.CaseID);
    assert(actual.TBS == expected.TBS, "%s TBS mismatch.", row.CaseID);
    assert(string(actual.TBCRCType) == expected.TBCRCType, ...
        "%s TB CRC type mismatch.", row.CaseID);
    assert(actual.TBCRCLength == expected.TBCRCLength, ...
        "%s TB CRC length mismatch.", row.CaseID);
    assert(actual.BaseGraph == expected.BaseGraph, ...
        "%s base-graph mismatch.", row.CaseID);
    positiveCount = positiveCount + 1;

    % Exercise the production plan for every moderate frozen allocation.
    if actual.TBS <= 25000
        modulation = localModulation(row.Qm);
        quantum = double(row.Qm);
        G = max(quantum, quantum * ceil( ...
            (actual.TBS + actual.TBCRCLength) / ...
            double(row.TargetCodeRate) / quantum));
        plan = sixgr.pdsch.DLSCHCodingPlan.resolve( ...
            "TransportBlockSize", actual.TBS, ...
            "TargetCodeRate", row.TargetCodeRate, ...
            "RateMatchedBitCount", G, ...
            "RV", 0, ...
            "Modulation", modulation, ...
            "NumLayers", 1);
        assert(double(plan.BaseGraph) == expected.BaseGraph, ...
            "%s production plan base-graph mismatch.", row.CaseID);
        assert(string(plan.TBCRCType) == expected.TBCRCType, ...
            "%s production plan TB CRC mismatch.", row.CaseID);
        planCount = planCount + 1;
    end
end

assert(positiveCount == 18 && negativeCount == 5 && planCount >= 8, ...
    "Unexpected PDSCH TBS test coverage.");
fprintf(['PDSCH TBS/base graph: frozen positives %d/18, negatives %d/5, ' ...
    'production plans %d; mismatches=0\n'], positiveCount, negativeCount, planCount);
ok = true;
end

function T = localReadInput(path)
opt = detectImportOptions(path, "TextType", "string");
opt = setvartype(opt, ["CaseID","ExpectedStatus","ExpectedError"], "string");
T = readtable(path, opt);
end

function T = localReadExpected(path)
opt = detectImportOptions(path, "TextType", "string");
opt = setvartype(opt, ...
    ["CaseID","TBCRCType","Status","ExpectedError"], "string");
T = readtable(path, opt);
end

function localAssertClose(actual, expected, caseID)
tolerance = 1e-10 * max(1, abs(double(expected)));
assert(abs(double(actual) - double(expected)) <= tolerance, ...
    "%s numeric mismatch: actual %.15g expected %.15g.", ...
    caseID, actual, expected);
end

function modulation = localModulation(qm)
switch double(qm)
    case 2
        modulation = "QPSK";
    case 4
        modulation = "16QAM";
    case 6
        modulation = "64QAM";
    case 8
        modulation = "256QAM";
    case 10
        modulation = "1024QAM";
    otherwise
        error("testPDSCHTBSAndBaseGraphBoundaries:UnsupportedQm", ...
            "Unsupported Qm=%d.", qm);
end
end

function localAssertIdentifier(fn, suffix)
thrown = false;
try
    fn();
catch cause
    thrown = endsWith(string(cause.identifier), ":" + string(suffix));
    if ~thrown
        rethrow(cause);
    end
end
assert(thrown, "Expected typed error ending in :%s.", suffix);
end
