function tests = testInitialAccessMIBPhaseCore
%TESTINITIALACCESSMIBPHASECORE Phase-06 23-bit MIB semantic vectors.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(mfilename("fullpath")));
addpath(repoRoot);
setup6GRSimToolkit("Verbose", false);
testCase.TestData.VectorRoot = fullfile( ...
    repoRoot, "tests", "vectors", "initial_access");
end

function testMIBSemanticPacking(testCase)
inputs = localReadStringTable(fullfile(testCase.TestData.VectorRoot, ...
    "pbch_mib_test_vectors.csv"));
expected = localReadStringTable(fullfile(testCase.TestData.VectorRoot, ...
    "expected_mib_semantics.csv"));
verifyEqual(testCase, height(inputs), 53);
verifyEqual(testCase, height(expected), 53);

validCount = 0;
invalidCount = 0;
for rowIndex = 1:height(inputs)
    inputRow = inputs(rowIndex, :);
    if lower(inputRow.ExpectedValid) == "true"
        actual = sixgr.phy.ia.MIBSemanticValidator.fromVectorRow(inputRow);
        expectedRow = expected(expected.CaseID == inputRow.CaseID, :);
        verifyEqual(testCase, height(expectedRow), 1);
        verifyEqual(testCase, actual.MIBInformationBits23, ...
            expectedRow.MIBInformationBits23, ...
            sprintf("MIB bits mismatch for %s.", inputRow.CaseID));
        verifyEqual(testCase, actual.NumBits, ...
            str2double(expectedRow.NumBits));
        verifyEqual(testCase, actual.SFNBits, expectedRow.SFNBits);
        verifyEqual(testCase, string(actual.SCSBit), expectedRow.SCSBit);
        verifyEqual(testCase, actual.KSSBBits, expectedRow.KSSBBits);
        verifyEqual(testCase, string(actual.DMRSTypeAPositionBit), ...
            expectedRow.DMRSTypeAPositionBit);
        verifyEqual(testCase, actual.PDCCHConfigSIB1Bits, ...
            expectedRow.PDCCHConfigSIB1Bits);
        verifyEqual(testCase, string(actual.CellBarredBit), ...
            expectedRow.CellBarredBit);
        verifyEqual(testCase, string(actual.IntraFreqReselectionBit), ...
            expectedRow.IntraFreqReselectionBit);
        verifyEqual(testCase, string(actual.SpareBit), ...
            expectedRow.SpareBit);

        decoded = sixgr.phy.ia.MIBSemanticValidator.decodeBits( ...
            actual.InformationBits);
        verifyEqual(testCase, decoded.MIBInformationBits23, ...
            actual.MIBInformationBits23);
        verifyEqual(testCase, decoded.SemanticSHA256, ...
            actual.SemanticSHA256);
        validCount = validCount + 1;
    else
        identifier = localCaptureError(@() ...
            sixgr.phy.ia.MIBSemanticValidator.fromVectorRow(inputRow));
        verifyEqual(testCase, identifier, inputRow.ExpectedError, ...
            sprintf("Wrong MIB error for %s.", inputRow.CaseID));
        invalidCount = invalidCount + 1;
    end
end
verifyEqual(testCase, validCount, 48);
verifyEqual(testCase, invalidCount, 5);
end

function testPBCHDecodedMIBSemanticState(testCase)
cfg = localConfig();
[waveform, ~, tx] = sixgr.phy.dl.SSB_Tx(cfg, "NumSubframes", 2);
[grid, sync] = sixgr.phy.dl.SSB_Rx( ...
    waveform, cfg, "SampleRate_Hz", tx.SampleRate_Hz);
[pbch, ~] = sixgr.phy.dl.PBCH_Recovery(grid, sync, cfg);
verifyTrue(testCase, pbch.Ok);
verifyEqual(testCase, pbch.MIBDecodedBitSource, "nrBCHDecode");
verifyTrue(testCase, pbch.DecodedMIBState.Immutable);
verifyEqual(testCase, pbch.DecodedMIBState.Source, ...
    "crc_valid_nrBCHDecode_transport_block");
verifyEqual(testCase, strlength(pbch.DecodedMIBState.EvidenceID), 64);

mib = sixgr.phy.broadcast.decodeMIBTransportBlock( ...
    pbch.TransportBlock);
verifyEqual(testCase, mib.SemanticValidationStatus, "PASS");
verifyEqual(testCase, strlength(mib.MIBInformationBits23), 23);
verifyEqual(testCase, numel(mib.MIBInformationBits), 23);
verifyEqual(testCase, mib.PDCCHConfigSIB1, ...
    mib.Semantic.PDCCHConfigSIB1);
verifyEqual(testCase, mib.DMRSTypeAPosition, ...
    mib.Semantic.DMRSTypeAPosition);
verifyEqual(testCase, strlength(mib.MIBSemanticSHA256), 64);
end

function tableOut = localReadStringTable(pathIn)
options = detectImportOptions(pathIn, "TextType", "string");
options = setvartype(options, options.VariableNames, "string");
tableOut = readtable(pathIn, options);
end

function identifier = localCaptureError(fcn)
identifier = "";
try
    fcn();
catch cause
    identifier = string(cause.identifier);
end
end

function cfg = localConfig()
cfg = sixgr.config.defaultConfig();
cfg.phy.carrier.NCellID = 17;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.SubcarrierSpacing_kHz = 30;
cfg.phy.carrier.NSizeGrid = 273;
end
