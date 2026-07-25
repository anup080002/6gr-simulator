function ok = testPDSCHTBCRCVectors()
%TESTPDSCHTBCRCVECTORS Validate every supplied TB CRC vector.

setup6GRSimToolkit("Verbose", false);
vectorDir = fullfile(fileparts(mfilename("fullpath")), "vectors", "pdsch");
expectedPath = fullfile(vectorDir, "expected_pdsch_tb_crc_vectors.csv");
expectedOptions = detectImportOptions(expectedPath, "TextType", "string");
expectedOptions = setvartype(expectedOptions, ...
    ["CRCType", "InputBits", "ExpectedCRCBits", "ExpectedBlockWithCRC"], ...
    "string");
expectedT = readtable(expectedPath, expectedOptions);
assert(height(expectedT) == 18, "TB CRC vector pack must contain exactly 18 rows.");

for idx = 1:height(expectedT)
    row = expectedT(idx, :);
    bits = localBits(row.InputBits);
    expectedCRC = localBits(row.ExpectedCRCBits);
    expectedBlock = localBits(row.ExpectedBlockWithCRC);
    [actualBlock, actualCRC] = sixgr.pdsch.oracle.CRCSpec(bits, row.CRCType);
    assert(isequal(actualCRC, expectedCRC), "%s CRC remainder mismatch.", row.CaseID);
    assert(isequal(actualBlock, expectedBlock), "%s CRC block mismatch.", row.CaseID);
    assert(numel(actualBlock) == double(row.PayloadLength) + numel(expectedCRC), ...
        "%s CRC output length mismatch.", row.CaseID);
end

% Exercise the independent 24B polynomial even though TB vectors use 16/24A.
probe = int8([1 0 1 1 0 0 1 0 1 0 0 1].');
[block24B, crc24B] = sixgr.pdsch.oracle.CRCSpec(probe, "24B");
assert(numel(crc24B) == 24 && numel(block24B) == numel(probe) + 24, ...
    "CRC-24B oracle attachment length mismatch.");

fprintf("PDSCH TB CRC vectors: 18/18 pass; exact bit mismatches=0\n");
ok = true;
end

function bits = localBits(text)
chars = char(string(text));
bits = int8(chars(:) - '0');
end
