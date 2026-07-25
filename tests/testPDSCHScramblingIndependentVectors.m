function ok = testPDSCHScramblingIndependentVectors()
%TESTPDSCHSCRAMBLINGINDEPENDENTVECTORS Validate all frozen Gold vectors.

setup6GRSimToolkit("Verbose", false);
vectorDir = fullfile(fileparts(mfilename("fullpath")), "vectors", "pdsch");
inputPath = fullfile(vectorDir, "pdsch_scrambling_test_vectors.csv");
inputOptions = detectImportOptions(inputPath, "TextType", "string");
inputOptions = setvartype(inputOptions, "InputBits", "string");
inputT = readtable(inputPath, inputOptions);
expectedPath = fullfile(vectorDir, "expected_pdsch_scrambling_vectors.csv");
expectedOptions = detectImportOptions(expectedPath, "TextType", "string");
expectedOptions = setvartype(expectedOptions, ...
    ["GoldBits", "ScrambledBits"], "string");
expectedT = readtable(expectedPath, expectedOptions);

assert(height(inputT) == 12 && height(expectedT) == 12, ...
    "Scrambling vector pack must contain exactly 12 input and expected rows.");
for idx = 1:height(inputT)
    row = inputT(idx, :);
    expected = expectedT(expectedT.CaseID == row.CaseID, :);
    assert(height(expected) == 1, "Missing expected row for %s.", row.CaseID);

    bits = localBits(row.InputBits);
    goldExpected = localBits(expected.GoldBits);
    scrambledExpected = localBits(expected.ScrambledBits);
    cInit = double(row.RNTI) * 2^15 + double(row.CodewordIndexQ) * 2^14 ...
        + double(row.DataScramblingIdentityNID);

    goldActual = sixgr.pdsch.oracle.GoldSequenceSpec(cInit, double(row.Length));
    assert(isequal(goldActual, goldExpected), ...
        "%s independent Gold sequence mismatch.", row.CaseID);

    [scrambled, info] = sixgr.pdsch.PDSCHScrambler(bits, ...
        double(row.RNTI), double(row.CodewordIndexQ), ...
        double(row.DataScramblingIdentityNID));
    assert(isequal(int8(scrambled(:)), scrambledExpected), ...
        "%s production scrambled bits mismatch.", row.CaseID);
    assert(double(info.CInit) == double(expected.CInit), ...
        "%s c_init mismatch.", row.CaseID);

    scrambledLLR = double(1 - 2 * scrambledExpected);
    descrambledLLR = sixgr.pdsch.PDSCHScrambler(scrambledLLR, ...
        double(row.RNTI), double(row.CodewordIndexQ), ...
        double(row.DataScramblingIdentityNID), ...
        "Operation", "llr-descramble");
    assert(isequal(descrambledLLR(:) > 0, bits == 0), ...
        "%s LLR descrambling sign mismatch.", row.CaseID);
end

fprintf("PDSCH scrambling vectors: 12/12 pass; exact bit mismatches=0\n");
ok = true;
end

function bits = localBits(text)
chars = char(string(text));
bits = int8(chars(:) - '0');
end
